#!/usr/bin/env bash
# Materialize src/term/{cell,engine,ffi_surface,key_input}.rs from the flake input
# `terminal`. The committed paths are symlinks to the sibling Terminal
# checkout; CI and shallow clones do not have that tree. Same pattern as
# ensure-waypipe / ensure-coreutils.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CELL="$ROOT/src/term/cell.rs"
ENGINE="$ROOT/src/term/engine.rs"
FFI="$ROOT/src/term/ffi_surface.rs"
KEYIN="$ROOT/src/term/key_input.rs"

# Real files, or symlinks that resolve locally.
if [[ -f "$CELL" && -f "$ENGINE" && -f "$FFI" && -f "$KEYIN" ]]; then
  exit 0
fi

echo "Populating terminal VT sources from flake input terminal..." >&2
SRC="$(nix eval --raw --impure --accept-flake-config \
  --expr "(builtins.getFlake \"$ROOT\").inputs.terminal.outPath")"
for need in cell.rs engine.rs ffi_surface.rs key_input.rs; do
  if [[ ! -f "$SRC/src/$need" ]]; then
    echo "error: terminal input missing src/$need at $SRC" >&2
    exit 1
  fi
done

mkdir -p "$ROOT/src/term"
# Drop retired homemade VT if still present.
rm -f "$ROOT/src/term/screen.rs" "$ROOT/src/term/kitty.rs"

copy_one() {
  local name="$1"
  local dest="$ROOT/src/term/$name"
  if [[ ! -f "$dest" ]]; then
    rm -f "$dest"
    cp "$SRC/src/$name" "$dest"
    chmod u+w "$dest"
    echo "✓ terminal $name injected at $dest" >&2
  fi
}

copy_one cell.rs
copy_one engine.rs
copy_one ffi_surface.rs
copy_one key_input.rs
