#!/usr/bin/env bash
# Low-memory `nix build` for machines that OOM on a cold Wawona compile.
#
# Cursor assets no longer pull librsvg / adwaita-icon-theme. This wrapper
# still lowers Nix parallelism for other heavy nixpkgs compiles on small RAM.
#
# Prefer FlakeHub so `wwn-*` slices substitute:
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
    echo "hint: determinate-nixd login substitutes prebuilt wwn-* slices from FlakeHub." >&2
    echo "      Without it, unmatched hashes compile from source." >&2
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
