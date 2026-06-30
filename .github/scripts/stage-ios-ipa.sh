#!/usr/bin/env bash
# Build the signed iPhone IPA via Nix and stage it for GitHub Release upload.
set -euo pipefail

VERSION="${1:-$(tr -d 'v' < VERSION)}"
ATTR="${2:-wawona-ios-ipa}"
OUT_NAME="${3:-Wawona-${VERSION}-iOS.ipa}"

: "${TEAM_ID:?TEAM_ID must be set for signed IPA builds}"

mkdir -p dist
OUT="$(nix build ".#${ATTR}" --impure --print-out-paths | tail -1)"
IPA="$(find "$OUT" -name '*.ipa' -print -quit)"
if [ -z "$IPA" ]; then
  echo "::error::No .ipa found under $OUT (attr ${ATTR})"
  exit 1
fi
cp "$IPA" "dist/${OUT_NAME}"
echo "Staged dist/${OUT_NAME}"
