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
SSH_CONFIG="${COLIMA_SSH_CONFIG:-$HOME/.colima/ssh_config}"
KEY="${COLIMA_SSH_KEY:-$HOME/.colima/_lima/_config/user}"
PORT="${COLIMA_SSH_PORT:-}"
USER_NAME="${COLIMA_SSH_USER:-lima}"
HOST="${COLIMA_SSH_HOST:-127.0.0.1}"
REMOTE_WAYPIPE="${COLIMA_REMOTE_WAYPIPE:-/usr/bin/waypipe}"

mkdir -p "$ART"

resolve_port() {
  if [ -n "$PORT" ]; then
    echo "$PORT"
    return
  fi
  if [ -f "$SSH_CONFIG" ]; then
    # First Port= line in lima/colima ssh_config (Host colima or lima-colima).
    local p
    p="$(awk '$1=="Port" { print $2; exit }' "$SSH_CONFIG")"
    if [ -n "$p" ]; then
      echo "$p"
      return
    fi
  fi
  echo "49419"
}

if [ "${1:-}" = "--kill" ]; then
  pkill -f "waypipe.*${USER_NAME}@${HOST}" 2>/dev/null || true
  echo "killed waypipe ssh sessions to ${USER_NAME}@${HOST}"
  exit 0
fi

PORT="$(resolve_port)"
if [ -z "$PORT" ]; then
  echo "lab: could not resolve Colima SSH port" >&2
  exit 1
fi

if [ "${1:-}" = "--status" ]; then
  echo "runtime=$WAWONA_RUNTIME port=$PORT wp=$WP"
  ls -la "$WAWONA_RUNTIME/wayland-0" 2>&1 || true
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$KEY" -p "$PORT" "${USER_NAME}@${HOST}" 'command -v waypipe foot weston weston-terminal' 2>&1 | tail -20
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
    -i "$KEY" -p "$PORT" -T "${USER_NAME}@${HOST}" -- $cmd \
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
