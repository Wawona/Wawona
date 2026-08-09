#!/usr/bin/env bash
# Incremental Nix gates for bundled shell tools (Apple mobile archives + Android).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

targets=(
  ".#zsh-ios-sim"
  ".#fastfetch-ios"
  ".#phoon-ios"
  ".#neovim-ios"
  ".#neovim-rootfs-ios-sim"
  ".#wawona-pty-ios-sim"
  ".#wawona-rootfs-ios-sim"
  ".#zsh-android"
  ".#fastfetch-android"
  ".#phoon-android"
  ".#neovim-android"
)

echo "[wawona] Building bundled shell-tool Nix outputs..."
for target in "${targets[@]}"; do
  echo "  - ${target}"
  nix build --print-build-logs "${target}"
done
echo "[wawona] Shell-tool Nix builds passed."
