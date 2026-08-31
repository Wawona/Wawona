#!/usr/bin/env bash
# Thin wrapper: container desktop recipes go through `Wawona run` so CLI and
# the Machines GUI stay in sync (auto-create card if missing).
#
# Usage:
#   scripts/container-desktop-clients-macos.sh flower
#   scripts/container-desktop-clients-macos.sh sway
#   scripts/container-desktop-clients-macos.sh weston
#
# Prefer: Wawona run <recipe>
set -euo pipefail

CLIENT="${1:-flower}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WAWONA_BIN="${WAWONA_BIN:-}"
if [[ -z "$WAWONA_BIN" ]]; then
  if [[ -x /Applications/Wawona.app/Contents/MacOS/Wawona ]]; then
    WAWONA_BIN=/Applications/Wawona.app/Contents/MacOS/Wawona
  elif command -v Wawona >/dev/null 2>&1; then
    WAWONA_BIN="$(command -v Wawona)"
  else
    echo "Wawona not found; nix run .#install or set WAWONA_BIN" >&2
    exit 1
  fi
fi

case "$CLIENT" in
  -h|--help|help)
    exec "$WAWONA_BIN" run --help
    ;;
  all)
    for c in flower weston-terminal weston niri sway labwc; do
      echo "=== Wawona run $c ==="
      "$WAWONA_BIN" run "$c" --headless || exit 1
    done
    ;;
  *)
    # Force container path for weston/niri when using this script name.
    recipe="$CLIENT"
    if [[ "$CLIENT" == "weston" ]]; then
      recipe="weston-container"
    fi
    exec "$WAWONA_BIN" run "$recipe"
    ;;
esac
