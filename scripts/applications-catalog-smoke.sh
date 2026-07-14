#!/usr/bin/env bash
# Headless Freedesktop catalog assertion for Linux/macOS CI (issue #78).
# Builds applications-catalog.nix and checks .desktop Names + icons without
# needing a compositor or agent-device session.
#
# Usage: scripts/applications-catalog-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT=/tmp/wawona-applications-catalog-smoke

echo "== building applications catalog =="
# Prefer the flake's already-locked nixpkgs (narHash → store hit) so we do not
# need builtins.getFlake (dirty trees / .cache perms can break that path).
read -r NIXPKGS_REV NIXPKGS_HASH <<<"$(python3 - <<'PY'
import json
n = json.load(open("flake.lock"))["nodes"]["nixpkgs"]["locked"]
print(n["rev"], n["narHash"])
PY
)"

nix build --impure --expr "
  let
    pkgs = import (fetchTarball {
      url = \"https://github.com/NixOS/nixpkgs/archive/${NIXPKGS_REV}.tar.gz\";
      sha256 = \"${NIXPKGS_HASH}\";
    }) { system = builtins.currentSystem; };
    catalog = pkgs.callPackage ${ROOT}/dependencies/generators/applications-catalog.nix {
      inherit pkgs;
      lib = pkgs.lib;
      wawonaSrc = ${ROOT};
    };
  in catalog
" --out-link "$OUT"

DESK="$(find "$OUT/share/applications" -name '*.desktop' | wc -l | tr -d ' ')"
ICONS="$(find "$OUT/share/icons/hicolor" -type f | wc -l | tr -d ' ')"
[[ "$DESK" -ge 3 ]] || { echo "FAIL: desktop count $DESK"; exit 1; }
[[ "$ICONS" -ge 1 ]] || { echo "FAIL: icon count $ICONS"; exit 1; }

python3 - "$OUT/share/applications" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
names = []
for p in sorted(root.glob("*.desktop")):
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("Name="):
            names.append(line.split("=", 1)[1].strip())
            break
need = {"Foot Terminal", "Neovim"}
missing = need - set(names)
if missing:
    raise SystemExit(f"missing {sorted(missing)}; have={names}")
print(f"PASS: {len(names)} desktop Names include {sorted(need)}")
PY

echo "PASS: applications-catalog ($DESK desktops, $ICONS icons)"
