#!/usr/bin/env bash
# Materialize src/term/screen.rs and src/term/kitty.rs from the flake input
# `terminal`. The committed paths are symlinks to the sibling Terminal
# checkout; CI and shallow clones do not have that tree. Same pattern as
# ensure-waypipe / ensure-coreutils.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN="$ROOT/src/term/screen.rs"
KITTY="$ROOT/src/term/kitty.rs"

# Real file, or a symlink that resolves locally.
if [[ -f "$SCREEN" && -f "$KITTY" ]]; then
  exit 0
fi

echo "Populating terminal sources from flake input terminal..." >&2
SRC="$(nix eval --raw --impure --accept-flake-config \
  --expr "(builtins.getFlake \"$ROOT\").inputs.terminal.outPath")"
if [[ ! -f "$SRC/src/screen.rs" || ! -f "$SRC/src/kitty.rs" ]]; then
  echo "error: terminal input missing src/screen.rs or src/kitty.rs at $SRC" >&2
  exit 1
fi

mkdir -p "$ROOT/src/term"
if [[ ! -f "$SCREEN" ]]; then
  rm -f "$SCREEN"
  cp "$SRC/src/screen.rs" "$SCREEN"
  chmod u+w "$SCREEN"
  echo "✓ terminal screen injected at $SCREEN" >&2
fi
if [[ ! -f "$KITTY" ]]; then
  rm -f "$KITTY"
  cp "$SRC/src/kitty.rs" "$KITTY"
  chmod u+w "$KITTY"
  echo "✓ terminal kitty injected at $KITTY" >&2
fi
