#!/usr/bin/env bash
# Launch each matrix Wayland client into live Wawona and capture Appium Mac2 /
# Linux screenshots into .agent-device/test-artifacts/appium/catalog-gallery/.
#
# Prerequisites:
#   - Wawona running with $WAWONA_RUNTIME/wayland-0
#   - Appium on :4723 (mac2 on Darwin, linux driver on Linux)
#   - Darwin: Colima running (ensure-colima.sh). No local-bundle / container.
#   - Linux: nested guest on the same WAYLAND_DISPLAY
#   - Present revealed (Focus / close Wawona Terminal) so wwn.compositor.surface
#     exists. Dark terminals pass require_client_screenshot via stddev, not mean.
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
# Dark clients (weston-terminal) often need >4s before first SHM attach.
export WAWONA_CATALOG_SETTLE_SEC="${WAWONA_CATALOG_SETTLE_SEC:-8}"
unset WAWONA_APPIUM_DRY || true

RUNTIME="${WAWONA_RUNTIME:-${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}}"
export XDG_RUNTIME_DIR="$RUNTIME"
SOCK="$RUNTIME/wayland-0"
if [[ -z "${FONTCONFIG_FILE:-}" && -f "$RUNTIME/fonts.conf" ]]; then
  export FONTCONFIG_FILE="$RUNTIME/fonts.conf"
fi
if [[ ! -S "$SOCK" ]]; then
  echo "FAIL: no Wayland socket at $SOCK. Start Wawona first." >&2
  exit 2
fi

chmod +x "$ROOT/scripts/appium/ensure-appium.sh"
chmod +x "$ROOT/scripts/appium/ensure-wda-mac.sh"
chmod +x "$ROOT/scripts/appium/ensure-colima.sh"
chmod +x "$ROOT/scripts/appium/run-appium-suite.sh"
chmod +x "$ROOT/scripts/appium/launch-wayland-client.sh"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export WAWONA_WAYLAND_GUEST=colima
  "$ROOT/scripts/appium/ensure-colima.sh"
else
  export WAWONA_WAYLAND_GUEST="${WAWONA_WAYLAND_GUEST:-nested}"
fi
# Local Mac2 / Linux sessions flap :4723; never start pytest cold.
"$ROOT/scripts/appium/ensure-appium.sh"
# Darwin: tip build + clean launch (never /Applications or stale DD), then WDA.
if [[ "$(uname -s)" == "Darwin" && "${WAWONA_APPIUM_PLATFORM}" == "macos" ]]; then
  chmod +x "$ROOT/scripts/appium/ensure-tip-wawona-macos.sh"
  chmod +x "$ROOT/scripts/lib/require-tip-wawona-app.sh"
  # Rebuild when git HEAD drifts; always quit + relaunch tip binary.
  eval "$("$ROOT/scripts/appium/ensure-tip-wawona-macos.sh")"
  # shellcheck source=/dev/null
  source "$ROOT/scripts/lib/require-tip-wawona-app.sh"
  wawona_refuse_stale_app_path "$WAWONA_APP_PATH"
  "$ROOT/scripts/appium/ensure-wda-mac.sh"
  export WAWONA_MAC2_WDA_URL="${WAWONA_MAC2_WDA_URL:-http://127.0.0.1:${WAWONA_MAC2_WDA_PORT:-10100}}"
  # Keep manageApp=1 so Mac2 gets bundleId (required for wwn.* AX). Prefer
  # skipAppKill + noReset so the tip compositor we just launched is not killed.
  # MANAGE_APP=0 is only for desktop-wide AX probes (no Machines root).
  export WAWONA_MAC2_MANAGE_APP="${WAWONA_MAC2_MANAGE_APP:-1}"
  export WAWONA_APPIUM_NO_RESET="${WAWONA_APPIUM_NO_RESET:-1}"
  export WAWONA_MAC2_SKIP_APP_KILL="${WAWONA_MAC2_SKIP_APP_KILL:-1}"
  echo "WAWONA_APP_PATH=$WAWONA_APP_PATH"
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
  # Single -k expression: multiple -k flags do not OR in pytest.
  expr="$(printf '%s or ' "$@" | sed 's/ or $//')"
  pytest tests/test_catalog_wayland.py -q --tb=short -k "$expr"
else
  pytest tests/test_catalog_wayland.py -q --tb=short
fi

python3 "$ROOT/scripts/appium/verify-catalog-gallery.py"
echo "Gallery: $ART/catalog-gallery/index.html"
