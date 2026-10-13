#!/usr/bin/env bash
# Entry point for reactivecircus/android-emulator-runner (Watch: Appium UI).
# Keep the workflow `script:` a one-liner so dash/YAML cannot break if/fi.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APK="${GITHUB_WORKSPACE:-$ROOT}/dist/Wawona.apk"
if [[ ! -f "$APK" ]]; then
  echo "No product APK; unit-level Appium dry path only"
  export WAWONA_APPIUM_DRY=1
else
  export WAWONA_APP_PATH="$APK"
fi

export WAWONA_APPIUM_PLATFORM=android
export WAWONA_APPIUM_SERVER="${WAWONA_APPIUM_SERVER:-http://127.0.0.1:4723}"
export WAWONA_APPIUM_MARKERS="${WAWONA_APPIUM_MARKERS:-native or wayland or (not catalog)}"

chmod +x "$ROOT/scripts/appium/run-appium-suite.sh"
# Watch lane: non-blocking until product APK is wired into this job.
if ! "$ROOT/scripts/appium/run-appium-suite.sh"; then
  echo "Appium Android suite returned non-zero (Watch lane)"
fi
