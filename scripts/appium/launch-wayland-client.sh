#!/usr/bin/env bash
# Launch a Wayland client into the live Wawona compositor for Appium catalog
# tests. Prefer a Linux container (macOS Containerization / wawona-container-
# desktop) or a Colima guest over waypipe SSH. Nested is for Linux runners.
# Never invent a fake client or skip because a packaging card is missing.
#
# Usage:
#   scripts/appium/launch-wayland-client.sh <client-id>
#   WAWONA_WAYLAND_GUEST=container|colima|nested scripts/appium/launch-wayland-client.sh swaywm
#
# Env:
#   WAWONA_RUNTIME / XDG_RUNTIME_DIR  compositor runtime (default /tmp/wawona-$UID)
#   WAYLAND_DISPLAY                   default wayland-0
#   WAWONA_WAYLAND_GUEST              container (default on Darwin) | colima | nested
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

# Map Appium matrix ids → guest:target.
# Container recipes match scripts/container-desktop-clients-macos.sh /
# assert-container-recipes-no-nix.sh (weston-container, sway, hyprland, …).
# Everything else uses Colima + waypipe SSH into the same host socket.
recipe_for() {
  case "$1" in
    weston) echo "container:weston-container" ;;
    weston_terminal) echo "colima:weston-terminal" ;;
    niri) echo "colima:niri" ;;
    swaywm) echo "container:sway" ;;
    hyprland) echo "container:hyprland" ;;
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
    GUEST=container
  else
    GUEST=nested
  fi
fi

SPEC="$(recipe_for "$CLIENT")"
KIND="${SPEC%%:*}"
TARGET="${SPEC#*:}"

if [[ "$KIND" == "unknown" ]]; then
  echo "FAIL: no Wayland guest mapping for $CLIENT" >&2
  exit 3
fi

# Recipe kind wins over default guest when they disagree.
if [[ "$KIND" == "colima" ]]; then
  GUEST=colima
elif [[ "$KIND" == "container" && "$GUEST" == "nested" ]]; then
  # Linux CI: nest instead of macOS containerization.
  GUEST=nested
fi

launch_container() {
  local recipe="$1"
  chmod +x "$ROOT/scripts/container-desktop-clients-macos.sh"
  WAWONA_CONTAINER_BACKEND="${WAWONA_CONTAINER_BACKEND:-containerization}" \
    "$ROOT/scripts/container-desktop-clients-macos.sh" "$recipe"
}

launch_local_bundle() {
  # macOS: prefer clients bundled in Wawona.app against the live host socket.
  # Prefer WAWONA_APP_PATH (nix product) over /Applications so modules match.
  local app_root="${WAWONA_APP_PATH:-/Applications/Wawona.app}"
  app_root="${app_root%/}"
  local bin_dir="$app_root/Contents/Resources/bin"
  local res_lib="$app_root/Contents/Resources/lib"
  local exe=""
  case "$CLIENT" in
    foot) exe="$bin_dir/foot" ;;
    weston) exe="$bin_dir/weston" ;;
    weston_terminal) exe="$bin_dir/weston-terminal" ;;
    weston_simple_shm) exe="$bin_dir/weston-simple-shm" ;;
    niri) exe="$bin_dir/niri" ;;
    *) return 1 ;;
  esac
  if [[ ! -x "$exe" ]]; then
    return 1
  fi
  mkdir -p "$ROOT/.agent-device/test-artifacts/appium"
  local cmd="$exe"
  local env_prefix="export XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR' WAYLAND_DISPLAY='$WAYLAND_DISPLAY'"
  case "$CLIENT" in
    weston)
      # Weston 13 aborts if wayland-backend.so is loaded from a stale nix
      # module dir before weston_log_set_handler. Point at this app's modules.
      env_prefix="$env_prefix DYLD_LIBRARY_PATH='$res_lib\${DYLD_LIBRARY_PATH:+:\$DYLD_LIBRARY_PATH}'"
      env_prefix="$env_prefix WESTON_BACKEND_DIR='$res_lib/libweston-13'"
      env_prefix="$env_prefix WESTON_MODULE_DIR='$res_lib/weston'"
      cmd="$exe --backend=wayland --socket=appium-local-weston --width=1024 --height=768"
      ;;
    niri) cmd="env NIRI_BACKEND=nested $exe" ;;
  esac
  nohup bash -lc "$env_prefix; $cmd" \
    >"$ROOT/.agent-device/test-artifacts/appium/local-${CLIENT}.log" 2>&1 &
  echo "local-bundle pid=$! client=$CLIENT cmd=$cmd app=$app_root"
  return 0
}

launch_colima() {
  # Prefer in-app binaries when present (stable host socket; no SSH race).
  if [[ "$(uname -s)" == "Darwin" ]] && launch_local_bundle; then
    return 0
  fi
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
    weston-terminal|weston-simple-shm) pkg=weston ;;
  esac
  if [[ ! -x "$ROOT/scripts/waypipe-ssh-colima-lab.sh" && ! -f "$ROOT/scripts/waypipe-ssh-colima-lab.sh" ]]; then
    echo "FAIL: waypipe-ssh-colima-lab.sh missing" >&2
    exit 4
  fi
  COLIMA_SSH_CONFIG="${COLIMA_SSH_CONFIG:-$HOME/.colima/ssh_config}"
  KEY="${COLIMA_SSH_KEY:-$HOME/.colima/_lima/_config/user}"
  PORT="$(awk '$1=="Port" { print $2; exit }' "$COLIMA_SSH_CONFIG" 2>/dev/null || echo 49419)"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$KEY" -p "$PORT" "lima@127.0.0.1" \
    "command -v $cmd >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg" \
    >/tmp/wawona-colima-apt-"$CLIENT".log 2>&1 || true
  chmod +x "$ROOT/scripts/waypipe-ssh-colima-lab.sh"
  "$ROOT/scripts/waypipe-ssh-colima-lab.sh" "$CLIENT" "$cmd"
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
  container)
    launch_container "$TARGET"
    ;;
  colima)
    launch_colima "$TARGET"
    ;;
  nested)
    launch_nested "$TARGET"
    ;;
  *)
    echo "FAIL: unknown WAWONA_WAYLAND_GUEST=$GUEST" >&2
    exit 5
    ;;
esac

echo "wayland-guest: launched $CLIENT via $GUEST"
