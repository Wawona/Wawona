#!/usr/bin/env bash
# Populate ./coreutils for the Cargo path dependency (same revision and hash as
# flake.nix `coreutils-src`). Mirrors scripts/ensure-waypipe.sh.
#
# We vendor the uutils "coreutils" umbrella crate so the App-Store-compliant
# build can dispatch ls/cat/cp/... in-process (no fork/exec) via the umbrella
# util_map. macOS/Android use the same source for a normal multicall binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/coreutils/Cargo.toml" ]]; then
  exit 0
fi
echo "Populating $ROOT/coreutils from Nix fetchFromGitHub (uutils/coreutils 0.0.30)..." >&2
SRC="$(nix build --no-link --print-out-paths --impure --accept-flake-config \
  --expr "with import (builtins.getFlake \"$ROOT\").inputs.nixpkgs { system = builtins.currentSystem; }; fetchFromGitHub { owner = \"uutils\"; repo = \"coreutils\"; rev = \"0.0.30\"; sha256 = \"sha256-OZ9AsCJmQmn271OzEmqSZtt1OPn7zHTScQiiqvPhqB0=\"; }")"
cp -rL "$SRC" "$ROOT/coreutils"
chmod -R u+w "$ROOT/coreutils"
