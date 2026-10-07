#!/usr/bin/env bash
# Host-side Verus. Same pin as Relay: 0.2026.09.27.3cf1832.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE="0.2026.09.27.3cf1832"
DEFAULT_VERUS="$HOME/.local/share/wawona/verus/$RELEASE/verus-arm64-macos/verus"
VERUS="${VERUS_BIN:-$DEFAULT_VERUS}"
if [[ ! -x "$VERUS" ]] && command -v verus >/dev/null 2>&1; then
  VERUS="$(command -v verus)"
fi
if [[ ! -x "$VERUS" ]]; then
  echo "Verus $RELEASE is required (VERUS_BIN or $DEFAULT_VERUS)" >&2
  exit 1
fi
"$VERUS" "$ROOT/verification/verus/rect_clamp.rs"
"$VERUS" "$ROOT/verification/verus/sanitize_ssh_host.rs"
