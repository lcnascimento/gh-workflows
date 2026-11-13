#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_EVENT_PATH:?}" "${REPO:?}" "${BOT:?}" "${MAX_ATTEMPTS:?}"

sonar_check="SonarQube Code Analysis"

if jq -e 'has("check_run")' "$GITHUB_EVENT_PATH" >/dev/null; then
  source=check_run label="check run"
  name="$(jq -r '.check_run.name' "$GITHUB_EVENT_PATH")"
  if [[ "$name" != "$sonar_check" ]]; then
    echo "check run $name is not $sonar_check"
    exit 0
  fi
else
  source=workflow_run label=run
fi
id="$(jq -r --arg s "$source" '.[$s].id' "$GITHUB_EVENT_PATH")"
conclusion="$(jq -r --arg s "$source" '.[$s].conclusion' "$GITHUB_EVENT_PATH")"
if [[ "$conclusion" != failure ]]; then
  echo "$label $id concluded $conclusion"
  exit 0
fi
sha="$(jq -r --arg s "$source" '.[$s].head_sha' "$GITHUB_EVENT_PATH")"
run_url="$(jq -r --arg s "$source" '.[$s].html_url' "$GITHUB_EVENT_PATH")"
pr="$(jq -r --arg s "$source" '.[$s].pull_requests[0].number // empty' "$GITHUB_EVENT_PATH")"

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
  gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="O relay parou depois de $MAX_ATTEMPTS relatos de falha neste PR. A falha do commit $sha ($run_url) precisa de um humano.

$limit_marker" >/dev/null
  echo "PR #$pr reached $MAX_ATTEMPTS CI failure reports"
  exit 0
fi

if [[ "$source" == check_run ]]; then
  gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="@$BOT o SonarQube reprovou o commit $sha: $run_url

Investigue os problemas apontados e envie uma correção para este PR.

$marker" >/dev/null
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

gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="@$BOT o CI falhou no commit $sha: $run_url

${jobs_section}Investigue a falha e envie uma correção para este PR.

$marker" >/dev/null
echo "reported $sha on PR #$pr"
