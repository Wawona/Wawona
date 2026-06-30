#!/usr/bin/env bash
# Build the Android meson weston stack under a Nix sandbox (default: relaxed).
# Matches the macOS GitHub Actions builder where /usr/bin/env is denied.
#
# Local monorepo (sibling checkouts):
#   WWN_TOOLCHAIN_ROOT=/path/to/wwn-toolchain WWN_WESTON_ROOT=/path/to/wwn-weston \
#     ./.github/scripts/nix-build-android-meson-sandbox-gate.sh
#
# Force cold rebuild of meson leaves (slow; catches missing patchShebangs hooks):
#   VERIFY_REBUILD=1 ./.github/scripts/nix-build-android-meson-sandbox-gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SANDBOX="${NIX_SANDBOX:-relaxed}"
NIX_ARGS=(--option sandbox "$SANDBOX" --no-link)

OVERRIDE=()
if [[ -n "${WWN_TOOLCHAIN_ROOT:-}" && -d "${WWN_TOOLCHAIN_ROOT}" ]]; then
  OVERRIDE+=(--override-input wwn-toolchain "path:${WWN_TOOLCHAIN_ROOT}")
fi
if [[ -n "${WWN_WESTON_ROOT:-}" && -d "${WWN_WESTON_ROOT}" ]]; then
  OVERRIDE+=(--override-input wwn-weston "path:${WWN_WESTON_ROOT}")
fi

if [[ "${VERIFY_REBUILD:-}" == "1" ]]; then
  NIX_ARGS+=(--rebuild)
fi

ATTRS=(
  .#freetype-android
  .#fontconfig-android
  .#pixman-android
  .#cairo-android
  .#glib-android
  .#harfbuzz-android
  .#fribidi-android
  .#pango-android
  .#weston-android
  .#weston-compositor-android
)

echo "Android meson sandbox gate: sandbox=$SANDBOX attrs=${#ATTRS[@]}"
nix build "${ATTRS[@]}" "${NIX_ARGS[@]}" "${OVERRIDE[@]}"
echo "Android meson sandbox gate: OK"
