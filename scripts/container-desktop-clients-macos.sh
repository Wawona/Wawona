#!/usr/bin/env bash
# Run common Wayland desktop clients inside a macOS OCI container over vsock
# waypipe. Use for manual matrix checks (flower sizing, nested compositors, …).
#
# Usage:
#   scripts/container-desktop-clients-macos.sh flower
#   scripts/container-desktop-clients-macos.sh weston-terminal
#   scripts/container-desktop-clients-macos.sh weston
#   scripts/container-desktop-clients-macos.sh niri
#   scripts/container-desktop-clients-macos.sh sway
#   scripts/container-desktop-clients-macos.sh all   # sequential smoke (long)
#
# Requires Wawona compositor listening (launch Wawona or export WAYLAND_DISPLAY).
# Env: WAWONA_CONTAINER_IMAGE (default nixos/nix), WAWONA_CONTAINER_ID, VSOCK_PORT
set -euo pipefail

CLIENT="${1:-flower}"
IMAGE="${WAWONA_CONTAINER_IMAGE:-nixos/nix}"
CONTAINER_ID="${WAWONA_CONTAINER_ID:-wawona-cli-$(id -u)-$$}"
VSOCK="${WAWONA_CONTAINER_VSOCK:-1042}"
FS_MB="${WAWONA_CONTAINER_FS_MB:-8192}"
MEM_MB="${WAWONA_CONTAINER_MEM_MB:-2048}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${WAWONA_BIN_DIR:-/Applications/Wawona.app/Contents/Resources/bin}"
if [[ ! -x "$BIN/container" ]]; then
  BIN="$(dirname "$(command -v Wawona 2>/dev/null || true)")/../Resources/bin"
fi
if [[ ! -x "$BIN/container" ]]; then
  echo "container CLI not found; set WAWONA_BIN_DIR or nix run .#install" >&2
  exit 1
fi

export PATH="$BIN:$PATH"
export WAWONA_CONTAINER_BACKEND=containerization
export WWNP_WAYPIPE_BIN="$BIN/waypipe-fds"
export WAWONA_WAYPIPE_GUEST="$BIN/waypipe-guest-root"

UID_TAG="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wawona-$UID_TAG}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

NIX_SHELL='nix --extra-experimental-features '"'"'nix-command flakes'"'"' shell'

guest_cmd_for() {
  case "$1" in
    flower|weston-flower)
      echo "$NIX_SHELL nixpkgs#weston -c weston-flower"
      ;;
    weston-terminal|terminal)
      echo "$NIX_SHELL nixpkgs#weston -c weston-terminal"
      ;;
    weston|weston-compositor)
      echo "$NIX_SHELL nixpkgs#weston -c weston --backend=wayland"
      ;;
    niri)
      echo "$NIX_SHELL nixpkgs#niri -c niri"
      ;;
    sway)
      echo "$NIX_SHELL nixpkgs#sway -c sway"
      ;;
    foot)
      echo "$NIX_SHELL nixpkgs#foot -c foot"
      ;;
    *)
      echo "Unknown client: $1" >&2
      echo "Try: flower weston-terminal weston niri sway foot" >&2
      exit 1
      ;;
  esac
}

run_one() {
  local name="$1"
  local cmd
  cmd="$(guest_cmd_for "$name")"
  local id="${CONTAINER_ID}-${name}"
  echo "=== container desktop: $name ==="
  echo "image=$IMAGE id=$id vsock=$VSOCK"
  echo "guest: $cmd"
  echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  container run --rm --id "$id" --fs-size "$FS_MB" -m "$MEM_MB" \
    --wayland-vsock-port "$VSOCK" \
    --waypipe-guest-bin "$BIN/waypipe-guest" \
    --waypipe-guest-root "$BIN/waypipe-guest-root" \
    "$IMAGE" -- /bin/sh -c "$cmd"
}

if [[ "$CLIENT" == "all" ]]; then
  for c in flower weston-terminal weston niri sway; do
    run_one "$c" || exit 1
  done
else
  run_one "$CLIENT"
fi
