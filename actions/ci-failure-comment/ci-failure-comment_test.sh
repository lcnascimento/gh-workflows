#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/ci-failure-comment.sh"
failures=0

setup() {
  work="$(mktemp -d)"
  mkdir -p "$work/bin" "$work/api"
  cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
method=GET body=""
args=()
while (($#)); do
  case "$1" in
    api | --paginate) ;;
    -X) method="$2"; shift ;;
    -f) body="${2#body=}"; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
path="${args[0]}"
if [[ "$method" == POST ]]; then
  printf '%s' "$body" >"$GH_STUB_DIR/posted-${path//\//_}"
  echo '{}'
else
  cat "$GH_STUB_DIR/api/${path//[\/?&=]/_}.json"
fi
STUB
  chmod +x "$work/bin/gh"
}

event() {
  cat >"$work/event.json" <<JSON
{"workflow_run": {"id": 42, "conclusion": "${2:-failure}", "head_sha": "abc123", "html_url": "https://github.com/o/r/actions/runs/42", "pull_requests": $1}}
JSON
  api 'repos/o/r/actions/runs/42/jobs?per_page=100' '{"jobs": [{"name": "discover", "conclusion": "success"}, {"name": "lint", "conclusion": "failure"}, {"name": "test-unit", "conclusion": "failure"}]}'
}

check_event() {
  cat >"$work/event.json" <<JSON
{"check_run": {"id": 77, "name": "${3:-SonarQube Code Analysis}", "conclusion": "${2:-failure}", "head_sha": "abc123", "html_url": "https://github.com/o/r/runs/77", "pull_requests": $1}}
JSON
}

pr() { api "repos/o/r/pulls/$1" "{\"number\": $1, \"state\": \"${3:-open}\", \"user\": {\"login\": \"${2:-homelab-cyrus[bot]}\"}}"; }

api() { printf '%s' "$2" >"$work/api/${1//[\/?&=]/_}.json"; }

run() {
  GH_STUB_DIR="$work" PATH="$work/bin:$PATH" GITHUB_EVENT_PATH="$work/event.json" \
    REPO=o/r BOT=homelab-cyrus[bot] AUTHOR="${AUTHOR-homelab-cyrus[bot]}" MAX_ATTEMPTS=3 "$script" >"$work/out" 2>&1 || echo "exit $?" >>"$work/out"
}

posted() { cat "$work/posted-repos_o_r_issues_$1_comments" 2>/dev/null || true; }

check() {
  if [[ "$2" == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"; printf '  want: %q\n  got:  %q\n' "$3" "$2"
    failures=$((failures + 1))
  fi
}

expected_body='@homelab-cyrus[bot] o CI falhou no commit abc123: https://github.com/o/r/actions/runs/42

Jobs que falharam:
- lint
- test-unit

Investigue a falha e envie uma correção para este PR.

<!-- cyrus-ci-failure sha=abc123 -->'

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "comments on the PR from the event" "$(posted 7)" "$expected_body"

setup
event '[]'
api 'repos/o/r/pulls?state=open&per_page=100' '[{"number": 5, "state": "open", "user": {"login": "homelab-cyrus[bot]"}, "head": {"sha": "zzz"}}, {"number": 9, "state": "open", "user": {"login": "homelab-cyrus[bot]"}, "head": {"sha": "abc123"}}]'
api repos/o/r/issues/9/comments '[]'
run
check "finds a fork PR by head SHA" "$(posted 9)" "$expected_body"

setup
event '[]'
api 'repos/o/r/pulls?state=open&per_page=100' '[{"number": 5, "head": {"sha": "zzz"}}]'
run
check "skips when no PR matches" "$(cat "$work/out")" "no open PR for abc123"

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[{"body": "hi"}, {"body": "x\n\n<!-- cyrus-ci-failure sha=abc123 -->"}]'
run
check "skips a SHA already reported" "$(posted 7)|$(cat "$work/out")" "|PR #7 already reported for abc123"

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}, {"body": "<!-- cyrus-ci-failure sha=b -->"}, {"body": "<!-- cyrus-ci-failure sha=c -->"}]'
run
check "posts a final notice without mention after MAX_ATTEMPTS reports" "$(posted 7)|$(cat "$work/out")" "O relay parou depois de 3 relatos de falha neste PR. A falha do commit abc123 (https://github.com/o/r/actions/runs/42) precisa de um humano.

<!-- cyrus-ci-failure limit -->|PR #7 reached 3 CI failure reports"

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}, {"body": "<!-- cyrus-ci-failure sha=b -->"}, {"body": "<!-- cyrus-ci-failure sha=c -->"}, {"body": "x\n\n<!-- cyrus-ci-failure limit -->"}]'
run
check "stays silent after the final notice" "$(posted 7)|$(cat "$work/out")" "|PR #7 already got the final notice"

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}]'
run
check "reports again on a new SHA" "$(posted 7)" "$expected_body"

setup
event '[{"number": 7}]' success
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "skips a run that did not fail" "$(posted 7)|$(cat "$work/out")" "|run 42 concluded success"

setup
event '[{"number": 7}]'
pr 7 renovate[bot]
api repos/o/r/issues/7/comments '[]'
run
check "skips a PR of another author" "$(posted 7)|$(cat "$work/out")" "|PR #7 is by renovate[bot], not homelab-cyrus[bot]"

setup
event '[]'
api 'repos/o/r/pulls?state=open&per_page=100' '[{"number": 9, "state": "open", "user": {"login": "lcnascimento"}, "head": {"sha": "abc123"}}]'
api repos/o/r/issues/9/comments '[]'
run
check "skips a fork PR of another author" "$(posted 9)|$(cat "$work/out")" "|PR #9 is by lcnascimento, not homelab-cyrus[bot]"

setup
event '[{"number": 7}]'
pr 7 homelab-cyrus[bot] closed
api repos/o/r/issues/7/comments '[]'
run
check "skips a closed PR" "$(posted 7)|$(cat "$work/out")" "|PR #7 is closed"

setup
event '[{"number": 7}]'
pr 7 lcnascimento
api repos/o/r/issues/7/comments '[]'
AUTHOR='' run
check "comments on any author without AUTHOR" "$(posted 7)" "$expected_body"

setup
event '[{"number": 7}]'
rm "$work/api/repos_o_r_actions_runs_42_jobs_per_page_100.json"
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "omits the job list when the jobs API is denied" "$(posted 7)" '@homelab-cyrus[bot] o CI falhou no commit abc123: https://github.com/o/r/actions/runs/42

Investigue a falha e envie uma correção para este PR.

<!-- cyrus-ci-failure sha=abc123 -->'

setup
event '[{"number": 7}]'
api 'repos/o/r/actions/runs/42/jobs?per_page=100' '{"jobs": [{"name": "lint", "conclusion": "success"}]}'
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "omits the job list when no job failed" "$(posted 7)" '@homelab-cyrus[bot] o CI falhou no commit abc123: https://github.com/o/r/actions/runs/42

Investigue a falha e envie uma correção para este PR.

<!-- cyrus-ci-failure sha=abc123 -->'

sonar_body='@homelab-cyrus[bot] o SonarQube reprovou o commit abc123: https://github.com/o/r/runs/77

Investigue os problemas apontados e envie uma correção para este PR.

<!-- cyrus-ci-failure sha=abc123 -->'

setup
check_event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "comments on a failed Sonar check" "$(posted 7)" "$sonar_body"

for conclusion in success neutral skipped; do
  setup
  check_event '[{"number": 7}]' "$conclusion"
  pr 7
  api repos/o/r/issues/7/comments '[]'
  run
  check "skips a Sonar check that concluded $conclusion" "$(posted 7)|$(cat "$work/out")" "|check run 77 concluded $conclusion"
done

setup
check_event '[{"number": 7}]' failure lint
pr 7
api repos/o/r/issues/7/comments '[]'
run
check "skips a failed check run of another name" "$(posted 7)|$(cat "$work/out")" "|check run lint is not SonarQube Code Analysis"

setup
check_event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments "[{\"body\": $(jq -Rs . <<<"$expected_body")}]"
run
check "skips a Sonar failure on a SHA already reported by CI" "$(posted 7)|$(cat "$work/out")" "|PR #7 already reported for abc123"

setup
event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments "[{\"body\": $(jq -Rs . <<<"$sonar_body")}]"
run
check "skips a CI failure on a SHA already reported by Sonar" "$(posted 7)|$(cat "$work/out")" "|PR #7 already reported for abc123"

setup
check_event '[]'
api 'repos/o/r/pulls?state=open&per_page=100' '[{"number": 9, "state": "open", "user": {"login": "homelab-cyrus[bot]"}, "head": {"sha": "abc123"}}]'
api repos/o/r/issues/9/comments '[]'
run
check "finds the PR of a Sonar check by head SHA" "$(posted 9)" "$sonar_body"

setup
check_event '[{"number": 7}]'
pr 7 renovate[bot]
api repos/o/r/issues/7/comments '[]'
run
check "skips a Sonar failure on a PR of another author" "$(posted 7)|$(cat "$work/out")" "|PR #7 is by renovate[bot], not homelab-cyrus[bot]"

setup
check_event '[{"number": 7}]'
pr 7 homelab-cyrus[bot] closed
api repos/o/r/issues/7/comments '[]'
run
check "skips a Sonar failure on a closed PR" "$(posted 7)|$(cat "$work/out")" "|PR #7 is closed"

setup
check_event '[{"number": 7}]'
pr 7
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}, {"body": "<!-- cyrus-ci-failure sha=b -->"}, {"body": "<!-- cyrus-ci-failure sha=c -->"}]'
run
check "counts Sonar failures against the same limit" "$(posted 7)|$(cat "$work/out")" "O relay parou depois de 3 relatos de falha neste PR. A falha do commit abc123 (https://github.com/o/r/runs/77) precisa de um humano.

<!-- cyrus-ci-failure limit -->|PR #7 reached 3 CI failure reports"

exit "$failures"
