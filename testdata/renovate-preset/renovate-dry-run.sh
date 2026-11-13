#!/usr/bin/env bash
set -euo pipefail

mode=$1
config=$(realpath "$2")
dir=$3

base=$(mktemp -d)
cd "$dir"
LOG_LEVEL=${LOG_LEVEL:-debug} \
  LOG_FORMAT=json \
  RENOVATE_CONFIG_FILE="$config" \
  RENOVATE_REQUIRE_CONFIG=ignored \
  RENOVATE_ONBOARDING=false \
  RENOVATE_BASE_DIR="$base" \
  npx --yes --package "renovate@${RENOVATE_VERSION:?}" renovate --platform=local --dry-run="$mode"
