#!/usr/bin/env bash
# Populate ./waypipe for Cargo path dependency (same revision and hash as flake.nix `waypipe-src`).
# Upstream GitLab no longer allows anonymous git/cargo fetches; Nix fixed-output fetch still works.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/waypipe/Cargo.toml" ]]; then
  exit 0
fi
echo "Populating $ROOT/waypipe from Nix fetchFromGitLab (mstoeckl/waypipe v0.11.0)..." >&2
SRC="$(nix build --no-link --print-out-paths --impure --accept-flake-config \
  --expr "with import (builtins.getFlake \"$ROOT\").inputs.nixpkgs { system = builtins.currentSystem; }; fetchFromGitLab { owner = \"mstoeckl\"; repo = \"waypipe\"; rev = \"v0.11.0\"; sha256 = \"sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=\"; }")"
cp -rL "$SRC" "$ROOT/waypipe"
chmod -R u+w "$ROOT/waypipe"
