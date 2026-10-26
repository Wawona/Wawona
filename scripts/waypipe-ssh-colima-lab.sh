#!/usr/bin/env bash
# Colima Linux guest + waypipe SSH client matrix into host Wawona (macOS).
#
# Prerequisites:
#   - colima running (Ubuntu guest with waypipe/weston/foot)
#   - Wawona.app running with wayland-0 under $WAWONA_RUNTIME
#
# Usage:
#   scripts/waypipe-ssh-colima-lab.sh              # launch default matrix
#   scripts/waypipe-ssh-colima-lab.sh foot          # one client
#   scripts/waypipe-ssh-colima-lab.sh --status
#   scripts/waypipe-ssh-colima-lab.sh --kill
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ART="$ROOT/.agent-device/test-artifacts"
WAWONA_RUNTIME="${WAWONA_RUNTIME:-/tmp/wawona-$(id -u)}"
# Prefer tip test app Resources; never default to a stale /Applications install.
if [[ -z "${WAWONA_WAYPIPE_BIN:-}" ]]; then
  for _wp in \
    "${WAWONA_APP_PATH:-}/Contents/Resources/bin/waypipe" \
    /tmp/wawona-macos-tip/Wawona.app/Contents/Resources/bin/waypipe \
    /tmp/wawona-macos-tip/DerivedData/Build/Products/Debug/Wawona.app/Contents/Resources/bin/waypipe
  do
    if [[ -x "$_wp" ]]; then
      WP="$_wp"
      break
    fi
  done
fi
WP="${WAWONA_WAYPIPE_BIN:-${WP:-}}"
if [[ -z "$WP" || ! -x "$WP" ]]; then
  echo "FAIL: waypipe missing. Set WAWONA_APP_PATH to tip Wawona.app (wawona-test-tip-app)." >&2
  exit 2
fi
COLIMA_HOME="${COLIMA_HOME:-$HOME/.colima}"
SSH_CONFIG="${COLIMA_SSH_CONFIG:-$COLIMA_HOME/ssh_config}"
COLIMA_SSH_HOST="$("$ROOT/scripts/appium/colima-ssh-host.sh" "$SSH_CONFIG")"
REMOTE_WAYPIPE="${COLIMA_REMOTE_WAYPIPE:-/usr/bin/waypipe}"

mkdir -p "$ART"

if [ "${1:-}" = "--kill" ]; then
  pkill -f 'waypipe.*ssh.*colima' 2>/dev/null || true
  echo "killed waypipe ssh sessions to Colima"
  exit 0
fi

if [ ! -s "$SSH_CONFIG" ]; then
  echo "lab: Colima SSH configuration missing at $SSH_CONFIG" >&2
  exit 1
fi

if [ "${1:-}" = "--status" ]; then
  echo "runtime=$WAWONA_RUNTIME ssh_config=$SSH_CONFIG wp=$WP"
  ls -la "$WAWONA_RUNTIME/wayland-0" 2>&1 || true
  ssh -F "$SSH_CONFIG" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$COLIMA_SSH_HOST" 'command -v waypipe foot weston weston-terminal' 2>&1 | tail -20
  pgrep -lf "Resources/bin/waypipe|waypipe --no-gpu" | head -30 || true
  exit 0
fi

if [ ! -S "$WAWONA_RUNTIME/wayland-0" ]; then
  echo "lab: missing $WAWONA_RUNTIME/wayland-0 (start Wawona first)" >&2
  exit 1
fi
if [ ! -x "$WP" ]; then
  echo "lab: waypipe binary missing at $WP" >&2
  exit 1
fi

export XDG_RUNTIME_DIR="$WAWONA_RUNTIME"
export WAYLAND_DISPLAY=wayland-0

DEFAULT_CLIENTS=(
  "foot:foot"
  "weston-terminal:weston-terminal"
  "weston-simple-shm:weston-simple-shm"
  "weston-flower:weston-flower"
  "weston-smoke:weston-smoke"
  "nested-weston:weston --backend=wayland --socket=nested-lab --width=900 --height=600"
)

launch_one() {
  local name="$1"
  local cmd="$2"
  local log="$ART/waypipe-ssh-${name}.log"
  # shellcheck disable=SC2086
  nohup "$WP" --no-gpu --remote-bin "$REMOTE_WAYPIPE" \
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -F "$SSH_CONFIG" -T "$COLIMA_SSH_HOST" -- $cmd \
    >"$log" 2>&1 &
  echo "started $name pid=$! -> $log"
}

if [ $# -gt 0 ] && [ "$1" != "--all" ]; then
  name="$1"
  shift
  cmd="${*:-$name}"
  launch_one "$name" "$cmd"
else
  for entry in "${DEFAULT_CLIENTS[@]}"; do
    name="${entry%%:*}"
    cmd="${entry#*:}"
    launch_one "$name" "$cmd"
    sleep 1
  done
fi

sleep 2
echo "lab: live sessions:"
pgrep -lf "$WP" | head -30 || true
echo "lab: touch $WAWONA_RUNTIME/show-session-surface if Metal view is hidden"
touch "$WAWONA_RUNTIME/show-session-surface" 2>/dev/null || true
