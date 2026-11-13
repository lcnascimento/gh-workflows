#!/usr/bin/env bash
set -euo pipefail

: "${EVENT_PATH:?}" "${REPO:?}" "${BOT:?}" "${MAX_ATTEMPTS:?}"

sonar_check="SonarQube Code Analysis"

IFS=$'\x1f' read -r kind name id conclusion sha run_url pr < <(
  jq -r 'if has("review") then ["review", "", .review.id, "", .pull_request.head.sha, .review.html_url, .pull_request.number]
    else (if has("check_run") then "check_run" else "workflow_run" end) as $kind | .[$kind]
      | [$kind, .name, .id, .conclusion, .head_sha, .html_url, .pull_requests[0].number] end
    | map(. // "" | tostring) | join("\u001f")' \
    "$EVENT_PATH"
)

post_comment() { gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="$1" >/dev/null; }

if [[ "$kind" == review ]]; then
  if [[ -z "${REVIEWER:-}" ]]; then
    echo "review $id ignored without a reviewer login"
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
  open_threads="$(gh api graphql -F number="$pr" -f owner="${REPO%/*}" -f name="${REPO#*/}" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              isResolved
              opener: comments(first: 1) { nodes { author { login } } }
              latest: comments(last: 1) { nodes { author { login } } }
            }
          }
        }
      }
    }' | jq --arg reviewer "${REVIEWER%\[bot\]}" --arg bot "${BOT%\[bot\]}" '
      [.data.repository.pullRequest.reviewThreads.nodes[]
        | select((.isResolved | not)
          and .opener.nodes[0].author.login == $reviewer
          and .latest.nodes[0].author.login != $bot)]
      | length')"
  if ((open_threads == 0)); then
    echo "PR #$pr has no open threads of $REVIEWER"
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
  post_comment "@$BOT o Revisor deixou $open_threads threads abertas no commit $sha: $run_url

$marker"
  echo "reported $sha on PR #$pr"
  exit 0
fi

if [[ "$kind" == check_run ]]; then
  post_comment "@$BOT o SonarQube reprovou o commit $sha: $run_url

Investigue os problemas apontados e envie uma correção para este PR.

$marker"
  echo "reported $sha on PR #$pr"
  exit 0
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

post_comment "@$BOT o CI falhou no commit $sha: $run_url

${jobs_section}Investigue a falha e envie uma correção para este PR.

$marker"
echo "reported $sha on PR #$pr"
