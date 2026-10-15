#!/usr/bin/env bash
# CI Appium artifact root. Non-hidden so upload-artifact finds files without
# include-hidden-files. Local default stays .agent-device/test-artifacts/appium.
#
# Usage (workflow):
#   eval "$(scripts/appium/ci-prepare-artifacts.sh)"
#   # exports WAWONA_APPIUM_ARTIFACTS, creates dirs, writes GITHUB_ENV when set
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# On GitHub Actions always use a non-hidden tree. upload-artifact v4+ drops
# paths under .agent-device unless include-hidden-files is set.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  ART="${GITHUB_WORKSPACE:-$ROOT}/test-artifacts/appium"
else
  ART="${WAWONA_APPIUM_ARTIFACTS:-$ROOT/.agent-device/test-artifacts/appium}"
fi
mkdir -p "$ART" "$ART/catalog-gallery"
export WAWONA_APPIUM_ARTIFACTS="$ART"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "WAWONA_APPIUM_ARTIFACTS=$ART" >>"$GITHUB_ENV"
fi

# stdout is eval'd
echo "export WAWONA_APPIUM_ARTIFACTS=$(printf '%q' "$ART")"
