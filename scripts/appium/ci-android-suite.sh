#!/usr/bin/env bash
# Entry point for reactivecircus/android-emulator-runner (Watch: Appium UI).
# Keep the workflow `script:` a one-liner so dash/YAML cannot break if/fi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APK="${GITHUB_WORKSPACE:-$ROOT}/dist/Wawona.apk"
if [[ ! -f "$APK" ]]; then
  echo "No product APK; offline Appium checks only"
  export WAWONA_APPIUM_DRY=1
else
  export WAWONA_APP_PATH="$APK"
fi

export WAWONA_APPIUM_PLATFORM=android
export WAWONA_APPIUM_SERVER="${WAWONA_APPIUM_SERVER:-http://127.0.0.1:4723}"

# Watch lane: non-blocking until the product APK is wired into this job.
if ! cargo xtask appium run --group "${WAWONA_APPIUM_GROUPS:-native,wayland}"; then
  echo "Appium Android suite returned non-zero (Watch lane)"
fi
