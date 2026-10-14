#!/usr/bin/env bash
# Launch each matrix Wayland client into live Wawona and capture Appium Mac2 /
# Linux screenshots into .agent-device/test-artifacts/appium/catalog-gallery/.
#
# Prerequisites:
#   - Wawona running with $WAWONA_RUNTIME/wayland-0
#   - Appium on :4723 (mac2 on Darwin, linux driver on Linux)
#   - Colima (macOS colima guests) and/or container recipes as needed
#
# Usage:
#   scripts/appium/capture-catalog-gallery.sh           # all clients
#   scripts/appium/capture-catalog-gallery.sh foot kde_plasma_de
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ART="${WAWONA_APPIUM_ARTIFACTS:-$ROOT/.agent-device/test-artifacts/appium}"
export WAWONA_APPIUM_ARTIFACTS="$ART"
export WAWONA_APPIUM_PLATFORM="${WAWONA_APPIUM_PLATFORM:-macos}"
export WAWONA_APPIUM_SERVER="${WAWONA_APPIUM_SERVER:-http://127.0.0.1:4723}"
unset WAWONA_APPIUM_DRY || true

RUNTIME="${WAWONA_RUNTIME:-${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}}"
SOCK="$RUNTIME/wayland-0"
if [[ ! -S "$SOCK" ]]; then
  echo "FAIL: no Wayland socket at $SOCK. Start Wawona first." >&2
  exit 2
fi

chmod +x "$ROOT/scripts/appium/ensure-appium.sh"
chmod +x "$ROOT/scripts/appium/ensure-wda-mac.sh"
chmod +x "$ROOT/scripts/appium/run-appium-suite.sh"
chmod +x "$ROOT/scripts/appium/launch-wayland-client.sh"
# Local Mac2 / Linux sessions flap :4723; never start pytest cold.
"$ROOT/scripts/appium/ensure-appium.sh"
# Darwin: pre-warm WDA with Xcode 26 Testing DYLD paths, then Mac2 attaches.
if [[ "$(uname -s)" == "Darwin" && "${WAWONA_APPIUM_PLATFORM}" == "macos" ]]; then
  "$ROOT/scripts/appium/ensure-wda-mac.sh"
  export WAWONA_MAC2_WDA_URL="${WAWONA_MAC2_WDA_URL:-http://127.0.0.1:${WAWONA_MAC2_WDA_PORT:-10100}}"
  export WAWONA_MAC2_MANAGE_APP="${WAWONA_MAC2_MANAGE_APP:-1}"
  export WAWONA_APPIUM_NO_RESET="${WAWONA_APPIUM_NO_RESET:-1}"
  export WAWONA_MAC2_SKIP_APP_KILL="${WAWONA_MAC2_SKIP_APP_KILL:-1}"
  if [[ -z "${WAWONA_APP_PATH:-}" ]]; then
    for cand in \
      /tmp/wawona-macos-a11y/Wawona.app \
      /tmp/wawona-macos/Wawona.app \
      "$ROOT/result/Applications/Wawona.app"
    do
      if [[ -d "$cand" ]]; then
        export WAWONA_APP_PATH="$cand"
        break
      fi
    done
  fi
  # Prefer activate over cold launch when Wawona is already up.
  osascript -e 'tell application id "com.aspauldingcode.Wawona" to activate' \
    >/dev/null 2>&1 || true
fi

cd "$ROOT/Tests/appium"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install -q -r requirements.txt
else
  # shellcheck disable=SC1091
  source .venv/bin/activate
fi
export PYTHONPATH="$ROOT/Tests/appium"

if [[ $# -gt 0 ]]; then
  # Filter parametrize ids: test_catalog_*[name]
  ARGS=()
  for c in "$@"; do
    ARGS+=("-k" "$c")
  done
  pytest tests/test_catalog_wayland.py -q --tb=short "${ARGS[@]}"
else
  pytest tests/test_catalog_wayland.py -q --tb=short
fi

python3 "$ROOT/scripts/appium/verify-catalog-gallery.py"
echo "Gallery: $ART/catalog-gallery/index.html"
