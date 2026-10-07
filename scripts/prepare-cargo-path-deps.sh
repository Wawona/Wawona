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
  python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "$ROOT/scripts/lib")
from expand_uutils_workspace_deps import strip_file
strip_file(Path("$ROOT/waypipe/Cargo.toml"))
PY
fi
