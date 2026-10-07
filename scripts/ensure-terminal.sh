#!/usr/bin/env bash
# Materialize src/term/screen.rs from the flake input `terminal`.
# The committed path is a symlink to the sibling Terminal checkout; CI and
# shallow clones do not have that tree. Same pattern as ensure-waypipe /
# ensure-coreutils.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/src/term/screen.rs"

# Real file, or a symlink that resolves locally.
if [[ -f "$DEST" ]]; then
  exit 0
fi

echo "Populating $DEST from flake input terminal..." >&2
SRC="$(nix eval --raw --impure --accept-flake-config \
  --expr "(builtins.getFlake \"$ROOT\").inputs.terminal.outPath")"
if [[ ! -f "$SRC/src/screen.rs" ]]; then
  echo "error: terminal input missing src/screen.rs at $SRC" >&2
  exit 1
fi

mkdir -p "$ROOT/src/term"
rm -f "$DEST"
cp "$SRC/src/screen.rs" "$DEST"
chmod u+w "$DEST"
echo "✓ terminal screen injected at $DEST" >&2
