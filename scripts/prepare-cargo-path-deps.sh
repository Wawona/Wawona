#!/usr/bin/env bash
# After ensure-waypipe / ensure-coreutils: expand uutils `{ workspace = true }`
# pins in-place and strip nested [workspace*] tables so `cargo test --locked`
# sees a single workspace root without mutating the root Cargo.toml / lockfile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/scripts/lib/expand_uutils_workspace_deps.py"

if [[ -d "$ROOT/coreutils" ]]; then
  python3 "$PY" "$ROOT/coreutils"
fi
if [[ -f "$ROOT/waypipe/Cargo.toml" ]]; then
  # Writable copy from Nix store; drop gbmfallback (not in Wawona features).
  chmod -R u+w "$ROOT/waypipe" 2>/dev/null || true
  python3 "$PY" --waypipe "$ROOT/waypipe"
fi
