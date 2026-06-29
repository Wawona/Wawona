#!/usr/bin/env bash
# Thin wrapper: prefer `nix run .#gradlegen` (repo-root Android Studio layout).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec nix run .#gradlegen "$@"
