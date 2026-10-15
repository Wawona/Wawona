#!/usr/bin/env bash
# Launch a Wayland client into the live Wawona compositor for Appium catalog
# tests.
#
# Darwin / macOS: Colima Linux guest + waypipe SSH only. No local-bundle, no
# Apple Containerization shortcut. Fail closed if Colima is down.
# Linux runners: nested on the same WAYLAND_DISPLAY (CI sets nested).
#
# Usage:
#   scripts/appium/launch-wayland-client.sh <client-id>
#   WAWONA_WAYLAND_GUEST=colima|nested scripts/appium/launch-wayland-client.sh swaywm
#
# Env:
#   WAWONA_RUNTIME / XDG_RUNTIME_DIR  compositor runtime (default /tmp/wawona-$UID)
#   WAYLAND_DISPLAY                   default wayland-0
#   WAWONA_WAYLAND_GUEST              colima (default Darwin) | nested (default Linux)
#   WAWONA_COLIMA_START=1             ensure-colima may start a stopped VM
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLIENT="${1:?client id required (e.g. weston, swaywm, firefox_wayland)}"
RUNTIME="${WAWONA_RUNTIME:-${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}}"
export XDG_RUNTIME_DIR="$RUNTIME"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
SOCK="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"

if [[ ! -S "$SOCK" ]]; then
  echo "FAIL: no Wayland socket at $SOCK (start Wawona host compositor first)" >&2
  exit 2
fi

# Map Appium matrix ids → guest:command (apt / PATH name inside Colima).
recipe_for() {
  case "$1" in
    weston) echo "colima:weston" ;;
    weston_terminal) echo "colima:weston-terminal" ;;
    niri) echo "colima:niri" ;;
    swaywm) echo "colima:sway" ;;
    hyprland) echo "colima:Hyprland" ;;
    weston_simple_shm) echo "colima:weston-simple-shm" ;;
    foot) echo "colima:foot" ;;
    ghostty_terminal) echo "colima:ghostty" ;;
    konsole) echo "colima:konsole" ;;
    firefox_wayland) echo "colima:firefox" ;;
    thunar) echo "colima:thunar" ;;
    dolphin) echo "colima:dolphin" ;;
    mangowm) echo "colima:mango" ;;
    cosmic_de) echo "colima:cosmic-comp" ;;
    phosh_de) echo "colima:phosh" ;;
    kde_plasma_de|kde_plasma_mobile_de) echo "colima:plasmashell" ;;
    gnome_de) echo "colima:gnome-shell" ;;
    *) echo "unknown:$1" ;;
  esac
}

GUEST="${WAWONA_WAYLAND_GUEST:-}"
if [[ -z "$GUEST" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    GUEST=colima
  else
    GUEST=nested
  fi
fi

# Catalog testing never uses Apple containerization or local host bins.
if [[ "$GUEST" == "container" || "$GUEST" == "local" || "$GUEST" == "local-bundle" ]]; then
  echo "FAIL: WAWONA_WAYLAND_GUEST=$GUEST forbidden for catalog tests; use colima (Darwin) or nested (Linux)." >&2
  exit 5
fi

SPEC="$(recipe_for "$CLIENT")"
KIND="${SPEC%%:*}"
TARGET="${SPEC#*:}"

if [[ "$KIND" == "unknown" ]]; then
  echo "FAIL: no Wayland guest mapping for $CLIENT" >&2
  exit 3
fi

# Recipe kind is always colima in the map; nested only via explicit env on Linux.
if [[ "$GUEST" != "nested" ]]; then
  GUEST=colima
fi

launch_colima() {
  local cmd="$1"
  local pkg="$cmd"
  case "$cmd" in
    firefox) pkg=firefox ;;
    ghostty) pkg=ghostty ;;
    konsole) pkg=konsole ;;
    thunar) pkg=thunar ;;
    dolphin) pkg=dolphin ;;
    mango) pkg=mangowm ;;
    cosmic-comp) pkg=cosmic-comp ;;
    phosh) pkg=phosh ;;
    gnome-shell) pkg=gnome-shell ;;
    plasmashell) pkg=plasma-workspace ;;
    niri) pkg=niri ;;
    sway) pkg=sway ;;
    Hyprland|hyprland) pkg=hyprland; cmd=Hyprland ;;
    weston) pkg=weston; cmd="weston --backend=wayland --socket=appium-colima-weston --width=1024 --height=768" ;;
    weston-terminal|weston-simple-shm) pkg=weston ;;
  esac
  chmod +x "$ROOT/scripts/appium/ensure-colima.sh"
  "$ROOT/scripts/appium/ensure-colima.sh"
  if [[ ! -x "$ROOT/scripts/waypipe-ssh-colima-lab.sh" && ! -f "$ROOT/scripts/waypipe-ssh-colima-lab.sh" ]]; then
    echo "FAIL: waypipe-ssh-colima-lab.sh missing" >&2
    exit 4
  fi
  COLIMA_SSH_CONFIG="${COLIMA_SSH_CONFIG:-$HOME/.colima/ssh_config}"
  KEY="${COLIMA_SSH_KEY:-$HOME/.colima/_lima/_config/user}"
  PORT="$(awk '$1=="Port" { print $2; exit }' "$COLIMA_SSH_CONFIG" 2>/dev/null || echo 49419)"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$KEY" -p "$PORT" "lima@127.0.0.1" \
    "command -v ${cmd%% *} >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg" \
    >/tmp/wawona-colima-apt-"$CLIENT".log 2>&1 || true
  chmod +x "$ROOT/scripts/waypipe-ssh-colima-lab.sh"
  # shellcheck disable=SC2086
  "$ROOT/scripts/waypipe-ssh-colima-lab.sh" "$CLIENT" $cmd
}

launch_nested() {
  local cmd="$1"
  case "$CLIENT" in
    weston) cmd="weston --backend=wayland --socket=appium-nested-weston --width=1024 --height=768" ;;
    niri) cmd="env NIRI_BACKEND=nested niri" ;;
    swaywm) cmd="sway" ;;
    hyprland) cmd="Hyprland" ;;
    weston_terminal) cmd="weston-terminal" ;;
    weston_simple_shm) cmd="weston-simple-shm" ;;
    foot) cmd="foot" ;;
    kde_plasma_de|kde_plasma_mobile_de) cmd="plasmashell" ;;
    gnome_de) cmd="gnome-shell --wayland" ;;
    *) cmd="$TARGET" ;;
  esac
  mkdir -p "$ROOT/.agent-device/test-artifacts/appium"
  nohup bash -lc "$cmd" \
    >"$ROOT/.agent-device/test-artifacts/appium/nested-${CLIENT}.log" 2>&1 &
  echo "nested pid=$! client=$CLIENT cmd=$cmd"
}

echo "wayland-guest: client=$CLIENT guest=$GUEST target=$TARGET sock=$SOCK"
mkdir -p "$ROOT/.agent-device/test-artifacts/appium"

case "$GUEST" in
  colima)
    launch_colima "$TARGET"
    ;;
  nested)
    launch_nested "$TARGET"
    ;;
  *)
    echo "FAIL: unknown WAWONA_WAYLAND_GUEST=$GUEST (allowed: colima, nested)" >&2
    exit 5
    ;;
esac

echo "wayland-guest: launched $CLIENT via $GUEST"
