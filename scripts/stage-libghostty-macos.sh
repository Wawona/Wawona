#!/usr/bin/env bash
# Stage wwn-ghostty#libghostty-macos into .nix-deps for tip link.
# Opt-in tip: WAWONA_LINK_LIBGHOSTTY=1 → GhosttySurfaceHost paints via
# ghostty_surface_draw. Rust VT stays wwn_term_*; Zig owns ghostty_surface_*.
# Default tip (flag off): GhosttyGpu atlas fallback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OVERRIDE=()
if [[ -d "${WAWONA_GHOSTTY_SRC:-}" ]]; then
  OVERRIDE+=(--override-input wwn-ghostty "path:${WAWONA_GHOSTTY_SRC}")
elif [[ -f ../Ghostty/flake.nix ]]; then
  OVERRIDE+=(--override-input wwn-ghostty "path:$(cd ../Ghostty && pwd)")
fi

echo "stage-libghostty-macos: building archive ${OVERRIDE[*]:-}"
nix build .#libghostty-macos --out-link .nix-deps/libghostty-macos-result \
  --accept-flake-config "${OVERRIDE[@]}"
DEST=".nix-deps/libghostty-macos"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a .nix-deps/libghostty-macos-result/. "$DEST/"
test -f "$DEST/lib/libghostty-internal.a"
test -f "$DEST/include/ghostty.h"
SIZE=$(stat -f%z "$DEST/lib/libghostty-internal.a" 2>/dev/null || stat -c%s "$DEST/lib/libghostty-internal.a")
echo "staged $DEST/lib/libghostty-internal.a ($SIZE bytes)"
nm -gU "$DEST/lib/libghostty-internal.a" 2>/dev/null | grep 'T _ghostty_surface_draw' | head -1 \
  || (grep -a -q 'ghostty_surface_draw' "$DEST/lib/libghostty-internal.a" && echo "ghostty_surface_draw present (archive)")
echo "OK. Tip with WAWONA_LINK_LIBGHOSTTY=1 → GhosttySurfaceHost Zig paint."
echo "Draw proof: nix build .#libghostty-macos-draw-proof ${OVERRIDE[*]:-}"
