#!/usr/bin/env bash
set -euo pipefail

: "${EVENT_PATH:?}" "${REPO:?}" "${BOT:?}" "${MAX_ATTEMPTS:?}"

sonar_check="SonarQube Code Analysis"
login_key='def key: ascii_downcase | sub("\\[bot\\]$"; "");'
reviewers="$(jq -Rnc "$login_key"'
  reduce (inputs | gsub("^\\s+|\\s+$"; "") | select(. != "")) as $login
    ([]; if any(.[]; key == ($login | key)) then . else . + [$login] end)' <<<"${REVIEWERS:-}")"

IFS=$'\x1f' read -r kind name id conclusion sha run_url pr reviewer < <(
  jq -r 'if has("review") then ["review", "", .review.id, "", .pull_request.head.sha, .review.html_url, .pull_request.number, .review.user.login]
    else (if has("check_run") then "check_run" else "workflow_run" end) as $kind | .[$kind]
      | [$kind, .name, .id, .conclusion, .head_sha, .html_url, .pull_requests[0].number] end
    | map(. // "" | tostring) | join("\u001f")' \
    "$EVENT_PATH"
)

post_comment() { gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="$1" >/dev/null; }

report() {
  post_comment "$1"
  echo "reported $sha on PR #$pr"
  exit 0
}

if [[ "$kind" == review ]]; then
  if [[ "$reviewers" == "[]" ]]; then
    echo "review $id ignored without reviewer logins"
    exit 0
  fi
  if ! jq -e --arg login "$reviewer" "$login_key"' any(.[]; key == ($login | key))' <<<"$reviewers" >/dev/null; then
    echo "review $id by $reviewer is not by a listed reviewer"
    exit 0
  fi
elif [[ "$kind" == check_run ]]; then
  label="check run"
  if [[ "$name" != "$sonar_check" ]]; then
    echo "check run $name is not $sonar_check"
    exit 0
  fi
else
  label=run
fi
if [[ "$kind" != review && "$conclusion" != failure ]]; then
  echo "$label $id concluded $conclusion"
  exit 0
fi

if [[ -n "$pr" ]]; then
  pull="$(gh api "repos/$REPO/pulls/$pr")"
else
  pull="$(gh api --paginate "repos/$REPO/pulls?state=open&per_page=100" |
    jq -c --arg sha "$sha" '.[] | select(.head.sha == $sha)' | head -n 1)"
fi
if [[ -z "$pull" ]]; then
  echo "no open PR for $sha"
  exit 0
fi
pr="$(jq -r '.number' <<<"$pull")"
state="$(jq -r '.state' <<<"$pull")"
author="$(jq -r '.user.login' <<<"$pull")"
if [[ "$state" != open ]]; then
  echo "PR #$pr is $state"
  exit 0
fi
if [[ -n "${AUTHOR:-}" && "$author" != "$AUTHOR" ]]; then
  echo "PR #$pr is by $author, not $AUTHOR"
  exit 0
fi

if [[ "$kind" == review ]]; then
  threads_by_reviewer="$(gh api graphql -F number="$pr" -f owner="${REPO%/*}" -f name="${REPO#*/}" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(last: 100) {
            nodes {
              isResolved
              opener: comments(first: 1) { nodes { author { login } } }
              latest: comments(last: 1) { nodes { author { login } } }
            }
          }
        }
      }
    }' | jq -c --argjson reviewers "$reviewers" --arg bot "$BOT" "$login_key"'
      [.data.repository.pullRequest.reviewThreads.nodes[]
        | select((.isResolved | not) and (.latest.nodes[0].author.login // "" | key) != ($bot | key))
        | .opener.nodes[0].author.login // "" | key] as $openers
      | [$reviewers[] | {login: ., count: (key as $k | [$openers[] | select(. == $k)] | length)} | select(.count > 0)]')"
  open_total="$(jq 'map(.count) | add // 0' <<<"$threads_by_reviewer")"
  if ((open_total == 0)); then
    echo "PR #$pr has no open threads of the reviewers"
    exit 0
  fi
fi

marker_prefix="<!-- cyrus-ci-failure "
marker="${marker_prefix}sha=$sha -->"
limit_marker="${marker_prefix}limit -->"
markers="$(gh api --paginate "repos/$REPO/issues/$pr/comments" |
  jq -r --arg bot "$BOT" '
    .[] | select(.user.type == "Bot" and .user.login != $bot)
    | .body | sub("\\s+$"; "") | split("\n") | last
    | select(test("^<!-- cyrus-ci-failure (sha=\\S+|limit) -->$"))')"

if grep -qxF "$marker" <<<"$markers"; then
  echo "PR #$pr already reported for $sha"
  exit 0
fi
if grep -qxF "$limit_marker" <<<"$markers"; then
  echo "PR #$pr already got the final notice"
  exit 0
fi
if (($(grep -c "^${marker_prefix}sha=" <<<"$markers" || true) >= MAX_ATTEMPTS)); then
  post_comment "O relay parou depois de $MAX_ATTEMPTS relatos de falha neste PR. A falha do commit $sha ($run_url) precisa de um humano.

$limit_marker"
  echo "PR #$pr reached $MAX_ATTEMPTS CI failure reports"
  exit 0
fi

if [[ "$kind" == review ]]; then
  reviewer_lines="$(jq -r '.[] | "- \(.login): \(.count)"' <<<"$threads_by_reviewer")"
  report "@$BOT há $open_total threads abertas de Revisores no commit $sha: $run_url

$reviewer_lines

$marker"
fi

if [[ "$kind" == check_run ]]; then
  report "@$BOT o SonarQube reprovou o commit $sha: $run_url

Investigue os problemas apontados e envie uma correção para este PR.

$marker"
fi

jobs_section=""
if jobs="$(gh api --paginate "repos/$REPO/actions/runs/$id/jobs?per_page=100")"; then
  failed="$(jq -r '.jobs[] | select(.conclusion == "failure") | "- " + .name' <<<"$jobs")"
  if [[ -n "$failed" ]]; then
    jobs_section="Jobs que falharam:
$failed

"
  fi
else
  echo "::warning::could not list the jobs of run $id; grant actions: read to include them"
fi

report "@$BOT o CI falhou no commit $sha: $run_url

${jobs_section}Investigue a falha e envie uma correção para este PR.

$marker"
