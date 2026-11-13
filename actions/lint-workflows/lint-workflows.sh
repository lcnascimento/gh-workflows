#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
files=("$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml)
if ((${#files[@]} == 0)); then
  echo "::notice::no workflows found in $WORKFLOWS"
  exit 0
fi

config=()
if [[ ! -f .github/zizmor.yml && ! -f zizmor.yml ]]; then
  config=(--config "$(dirname "$0")/zizmor.yml")
fi

status=0
uvx --from "actionlint-py==$ACTIONLINT_VERSION" actionlint "${files[@]}" || status=1
uvx "zizmor==$ZIZMOR_VERSION" --format=github "${config[@]}" "${files[@]}" || status=1
exit "$status"
