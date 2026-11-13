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
{"workflow_run": {"head_sha": "abc123", "html_url": "https://github.com/o/r/actions/runs/42", "pull_requests": $1}}
JSON
}

api() { printf '%s' "$2" >"$work/api/${1//[\/?&=]/_}.json"; }

run() {
  GH_STUB_DIR="$work" PATH="$work/bin:$PATH" GITHUB_EVENT_PATH="$work/event.json" \
    REPO=o/r BOT=homelab-cyrus[bot] MAX_ATTEMPTS=3 "$script" >"$work/out" 2>&1 || echo "exit $?" >>"$work/out"
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

Investigue a falha e envie uma correção para este PR.

<!-- cyrus-ci-failure sha=abc123 -->'

setup
event '[{"number": 7}]'
api repos/o/r/issues/7/comments '[]'
run
check "comments on the PR from the event" "$(posted 7)" "$expected_body"

setup
event '[]'
api 'repos/o/r/pulls?state=open&per_page=100' '[{"number": 5, "head": {"sha": "zzz"}}, {"number": 9, "head": {"sha": "abc123"}}]'
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
api repos/o/r/issues/7/comments '[{"body": "hi"}, {"body": "x\n\n<!-- cyrus-ci-failure sha=abc123 -->"}]'
run
check "skips a SHA already reported" "$(posted 7)|$(cat "$work/out")" "|PR #7 already reported for abc123"

setup
event '[{"number": 7}]'
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}, {"body": "<!-- cyrus-ci-failure sha=b -->"}, {"body": "<!-- cyrus-ci-failure sha=c -->"}]'
run
check "stops after MAX_ATTEMPTS reports" "$(posted 7)|$(cat "$work/out")" "|PR #7 reached 3 CI failure reports"

setup
event '[{"number": 7}]'
api repos/o/r/issues/7/comments '[{"body": "<!-- cyrus-ci-failure sha=a -->"}]'
run
check "reports again on a new SHA" "$(posted 7)" "$expected_body"

exit "$failures"
