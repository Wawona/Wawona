#!/usr/bin/env bash
# Stage Nix-generated UniFFI Swift into .nix-deps/uniffi for local xcodegen.
# Never commit generated bindings (wawona-nix-generated).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/.nix-deps/uniffi"
mkdir -p "${DEST}"

candidates=(
  "${ROOT}/macos-dependencies/uniffi"
  "${WAWONA_RUST_BACKEND:-}/uniffi/swift"
)

copied=0
for src in "${candidates[@]}"; do
  if [[ -n "${src}" && -d "${src}" && -n "$(ls -A "${src}" 2>/dev/null || true)" ]]; then
    cp -R "${src}/." "${DEST}/"
    copied=1
    echo "staged UniFFI Swift from ${src} -> ${DEST}"
    break
  fi
done

if [[ "${copied}" -eq 0 ]]; then
  echo "stage-uniffi-swift: no generated Swift found (C trampolines remain)."
  exit 0
fi
ls -la "${DEST}" | head -20
