#!/usr/bin/env bash
# Populate ./coreutils for the Cargo path dependency from wwn-uutils-rs.
# Ownership: pin + patch live in github.com/Wawona/wwn-uutils-rs (safe-subset.txt,
# coreutils-src.nix, patch-coreutils-source.sh). Do not re-pin uutils here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$ROOT/coreutils/Cargo.toml" ]] || ! grep -q wawona_coreutils_main "$ROOT/coreutils/src/bin/coreutils.rs" 2>/dev/null; then
  echo "Populating $ROOT/coreutils from wwn-uutils-rs.lib.mkPatchedSrc (ios)..." >&2
  SRC="$(nix build --no-link --print-out-paths --impure --accept-flake-config \
    --expr "
      let
        flake = builtins.getFlake \"$ROOT\";
        pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      in flake.inputs.wwn-uutils-rs.lib.mkPatchedSrc { inherit pkgs; platform = \"ios\"; }
    ")"
  rm -rf "$ROOT/coreutils"
  cp -rL "$SRC" "$ROOT/coreutils"
  chmod -R u+w "$ROOT/coreutils"
fi
# Strip nested [workspace*] + merge workspace.dependencies into root.
"$ROOT/scripts/prepare-cargo-path-deps.sh"
