#!/usr/bin/env bash
# Low-memory `nix build` for machines that OOM on a cold Wawona compile.
#
# Symptom: librsvg / adwaita-icon-theme dies with Killed: 9 and exit 137
# (gdk-pixbuf-loader install). The flake still uses pkgs.adwaita-icon-theme;
# this wrapper only lowers Nix parallelism so the compile fits in RAM.
#
# Prefer FlakeHub first so librsvg is substituted, not rebuilt:
#   determinate-nixd login
#   determinate-nixd status   # Logged in: true
#
# Usage (from repo root):
#   ./scripts/nix-build-low-mem.sh
#   ./scripts/nix-build-low-mem.sh .#wawona-macos
#   ./scripts/nix-build-low-mem.sh .#wawona-macos .#xcodegen-macos
#
# Environment:
#   WAWONA_NIX_MAX_JOBS  concurrent derivations (default 1)
#   WAWONA_NIX_CORES     cores per derivation (default 2)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MAX_JOBS="${WAWONA_NIX_MAX_JOBS:-1}"
CORES="${WAWONA_NIX_CORES:-2}"

if [ "$#" -eq 0 ]; then
  set -- .#wawona-macos
fi

if command -v determinate-nixd >/dev/null 2>&1; then
  if ! determinate-nixd status 2>/dev/null | grep -q 'Logged in: true'; then
    echo "hint: determinate-nixd login substitutes prebuilt librsvg/adwaita-icon-theme from FlakeHub." >&2
    echo "      Without it, a cold compile can OOM (exit 137 / Killed: 9)." >&2
  fi
else
  echo "hint: install Determinate Nix and run determinate-nixd login to pull FlakeHub substitutes." >&2
fi

echo "nix build --option max-jobs ${MAX_JOBS} --option cores ${CORES} -L $*"
exec nix build \
  --option max-jobs "${MAX_JOBS}" \
  --option cores "${CORES}" \
  -L \
  "$@"
