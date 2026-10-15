#!/usr/bin/env bash
# Fail closed unless WAWONA_APP_PATH is a tip test build (not stale install).
# Sourced or exec'd by Appium / agent-device / smoke harnesses.
#
# Escape (lab only, never Appium catalog): WAWONA_ALLOW_STALE_TEST_APP=1
set -euo pipefail

wawona_refuse_stale_app_path() {
  local app="${1:-${WAWONA_APP_PATH:-}}"
  if [[ -z "$app" ]]; then
    echo "FAIL: WAWONA_APP_PATH empty" >&2
    return 2
  fi
  # String gate before existence (install may be absent and still forbidden).
  case "$app" in
    /Applications/*|*/Applications/Wawona.app|~/Applications/*|"$HOME"/Applications/*)
      echo "FAIL: refusing stale install path: $app" >&2
      echo "Build tip and set WAWONA_APP_PATH (see scripts/appium/ensure-tip-wawona-macos.sh)." >&2
      return 2
      ;;
  esac
  if [[ ! -d "$app" ]]; then
    echo "FAIL: WAWONA_APP_PATH not a directory: $app" >&2
    return 2
  fi
  local resolved
  resolved="$(cd "$app" && pwd -P)"
  case "$resolved" in
    /Applications/*|*/Applications/Wawona.app)
      echo "FAIL: refusing stale install path: $resolved" >&2
      return 2
      ;;
  esac
  # Old dogfood trees (not tip stamp dir).
  case "$resolved" in
    */build/DerivedData-macos/*|*/build/DerivedData-macos-new/*|*/Library/Developer/Xcode/DerivedData/*)
      if [[ "$resolved" != /tmp/wawona-macos-tip/* && "$resolved" != /tmp/wawona-macos-a11y/* ]]; then
        echo "FAIL: refusing stale DerivedData: $resolved" >&2
        return 2
      fi
      ;;
  esac
  if [[ "${WAWONA_ALLOW_STALE_TEST_APP:-0}" == "1" ]]; then
    echo "WARN: WAWONA_ALLOW_STALE_TEST_APP=1 (forbidden for Appium catalog)" >&2
  fi
  return 0
}

wawona_tip_app_macos() {
  echo "${WAWONA_TIP_APP:-/tmp/wawona-macos-tip/DerivedData/Build/Products/Debug/Wawona.app}"
}
