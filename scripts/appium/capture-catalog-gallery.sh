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

chmod +x "$ROOT/scripts/appium/run-appium-suite.sh"
chmod +x "$ROOT/scripts/appium/launch-wayland-client.sh"

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
