#!/usr/bin/env bash
# Gate: wasm-wayland. Prove the locked Wawona Runtime can run a real
# wl_shm + xdg client against Weston (same compositor class Wawona nests).
#
# Steps:
#   1. Build .#wawona-wasm (host CLI + staticlib)
#   2. Clone Relay @ flake.lock rev (import/wasm owns the smoke guest)
#   3. Run import/wasm smoke-wayland-shm.sh with WASM_BIN from the Nix build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: need $1" >&2
    exit 1
  }
}
need nix
need jq
need git

# Relay replaced the standalone wwn-wasm flake input (Mode A WASI).
REV="$(jq -r '.nodes["wwn-relay"].locked.rev // empty' flake.lock)"
if [[ -z "$REV" ]]; then
  echo "error: flake.lock has no wwn-relay rev" >&2
  exit 1
fi

OWNER="$(jq -r '.nodes["wwn-relay"].locked.owner // "Wawona"' flake.lock)"
REPO="$(jq -r '.nodes["wwn-relay"].locked.repo // "Relay"' flake.lock)"

echo "==> nix build .#wawona-wasm (host runtime)"
nix build .#wawona-wasm -o result-wawona-wasm -L
WASM_BIN="$ROOT/result-wawona-wasm/bin/wasm"
if [[ ! -x "$WASM_BIN" ]]; then
  echo "error: missing $WASM_BIN (linux/macos recipe must install bin/wasm)" >&2
  find result-wawona-wasm -maxdepth 3 -type f >&2 || true
  exit 1
fi

WORKDIR="${TMPDIR:-/tmp}/wawona-relay-wasm-src-$$"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> clone $OWNER/$REPO @ $REV"
git clone --filter=blob:none "https://github.com/${OWNER}/${REPO}.git" "$WORKDIR"
git -C "$WORKDIR" checkout --quiet "$REV"

SMOKE_DIR="$WORKDIR/import/wasm"
SMOKE_SH="$SMOKE_DIR/.github/scripts/smoke-wayland-shm.sh"
if [[ ! -x "$SMOKE_SH" && ! -f "$SMOKE_SH" ]]; then
  echo "error: locked Relay @$REV has no import/wasm smoke-wayland-shm.sh. Bump wwn-relay" >&2
  exit 1
fi

echo "==> Wayland SHM smoke (Weston headless + locked guest)"
export WASM_BIN
# Guest build uses host rustc/cargo (CI installs via rust-toolchain).
# Weston comes from nixpkgs so runners need no system compositor packages.
need rustc
need cargo
need rustup
rustup target add wasm32-wasip1 >/dev/null
nix shell nixpkgs#weston --command \
  bash -c "cd '$SMOKE_DIR' && chmod +x ./.github/scripts/smoke-wayland-shm.sh && ./.github/scripts/smoke-wayland-shm.sh"

echo "OK Gate: wasm-wayland"
