#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_EVENT_PATH:?}" "${REPO:?}" "${BOT:?}" "${MAX_ATTEMPTS:?}"

sha="$(jq -r '.workflow_run.head_sha' "$GITHUB_EVENT_PATH")"
run_url="$(jq -r '.workflow_run.html_url' "$GITHUB_EVENT_PATH")"
pr="$(jq -r '.workflow_run.pull_requests[0].number // empty' "$GITHUB_EVENT_PATH")"

if [[ -z "$pr" ]]; then
  pr="$(gh api --paginate "repos/$REPO/pulls?state=open&per_page=100" |
    jq -r --arg sha "$sha" '.[] | select(.head.sha == $sha) | .number' | head -n 1)"
fi
if [[ -z "$pr" ]]; then
  echo "no open PR for $sha"
  exit 0
fi

marker_prefix="<!-- cyrus-ci-failure sha="
marker="$marker_prefix$sha -->"
reports="$(gh api --paginate "repos/$REPO/issues/$pr/comments" |
  jq -r --arg prefix "$marker_prefix" '.[].body | select(contains($prefix)) | match($prefix + "[^ ]* -->").string')"

if grep -qxF "$marker" <<<"$reports"; then
  echo "PR #$pr already reported for $sha"
  exit 0
fi
if (($(grep -c . <<<"$reports" || true) >= MAX_ATTEMPTS)); then
  echo "PR #$pr reached $MAX_ATTEMPTS CI failure reports"
  exit 0
fi

gh api -X POST "repos/$REPO/issues/$pr/comments" -f body="@$BOT o CI falhou no commit $sha: $run_url

Investigue a falha e envie uma correção para este PR.

$marker" >/dev/null
echo "reported $sha on PR #$pr"
