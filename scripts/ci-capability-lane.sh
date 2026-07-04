#!/usr/bin/env bash
# Layer-2 capability lane (ci-capability-lane): on Linux, bring up the Wawona
# compositor headlessly, run a nested Weston child compositor against it, and
# verify a nested Wayland socket + (optionally) XWayland come up. This is the
# deep "nested compositor + X11 bridge works" gate; it runs in the nightly
# full-matrix workflow, not on the PR path.
#
# Local:  ./scripts/ci-capability-lane.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wawona-cap-$(id -u)}"
DISPLAY_NAME="${WAYLAND_DISPLAY:-wayland-0}"
SOCKET_WAIT_SECS="${WAWONA_CAP_SOCKET_WAIT:-90}"
NESTED_WAIT_SECS="${WAWONA_CAP_NESTED_WAIT:-30}"

log() { echo "[capability-lane] $*"; }

if [[ "$(uname)" != "Linux" ]]; then
  log "FAIL: capability lane is Linux-only (got $(uname))"
  exit 1
fi

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
rm -f "$RUNTIME_DIR/$DISPLAY_NAME" "$RUNTIME_DIR/$DISPLAY_NAME.lock"

# 1. Build + launch the Wawona Linux compositor in host mode.
log "building .#wawona-linux-compositor-host"
HOST_BIN="$(nix build "$ROOT#wawona-linux-compositor-host" --print-out-paths --no-link)/bin/wawona-linux-compositor-host-run"
if [[ ! -x "$HOST_BIN" ]]; then
  log "FAIL: compositor-host binary not found at $HOST_BIN"
  exit 1
fi

log "starting compositor host"
"$HOST_BIN" >/tmp/wawona-cap-host.log 2>&1 &
HOST_PID=$!
cleanup() {
  kill "$NESTED_PID" 2>/dev/null || true
  kill "$HOST_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
NESTED_PID=0

# 2. Wait for the parent Wayland socket.
for _ in $(seq 1 "$SOCKET_WAIT_SECS"); do
  [[ -S "$RUNTIME_DIR/$DISPLAY_NAME" ]] && break
  kill -0 "$HOST_PID" 2>/dev/null || { log "FAIL: host exited before socket"; sed -n '1,120p' /tmp/wawona-cap-host.log; exit 1; }
  sleep 1
done
[[ -S "$RUNTIME_DIR/$DISPLAY_NAME" ]] || { log "FAIL: parent socket never appeared"; sed -n '1,120p' /tmp/wawona-cap-host.log; exit 1; }
log "parent socket up: $DISPLAY_NAME"
export WAYLAND_DISPLAY="$DISPLAY_NAME"

# 3. Launch nested Weston with XWayland enabled on a child socket.
WESTON_BIN="$(nix build "$ROOT#weston-simple-shm" --print-out-paths --no-link 2>/dev/null)/bin/weston 2>/dev/null || command -v weston || true"
WESTON_BIN="$(command -v weston || true)"
if [[ -z "$WESTON_BIN" ]]; then
  # Fall back to nixpkgs weston (reference target).
  WESTON_BIN="$(nix build nixpkgs#weston --print-out-paths --no-link)/bin/weston"
fi
CHILD_SOCKET="wayland-cap-child"
log "starting nested Weston ($WESTON_BIN) socket=$CHILD_SOCKET"
"$WESTON_BIN" --backend=wayland --socket="$CHILD_SOCKET" --xwayland >/tmp/wawona-cap-nested.log 2>&1 &
NESTED_PID=$!

# 4. Verify the child socket appears.
for _ in $(seq 1 "$NESTED_WAIT_SECS"); do
  [[ -S "$RUNTIME_DIR/$CHILD_SOCKET" ]] && break
  kill -0 "$NESTED_PID" 2>/dev/null || { log "FAIL: nested weston exited early"; sed -n '1,120p' /tmp/wawona-cap-nested.log; exit 1; }
  sleep 1
done
[[ -S "$RUNTIME_DIR/$CHILD_SOCKET" ]] || { log "FAIL: nested child socket never appeared"; sed -n '1,120p' /tmp/wawona-cap-nested.log; exit 1; }
log "PASS: nested child socket up ($CHILD_SOCKET)"

# 5. XWayland readiness (advisory): nested weston logs an X DISPLAY when ready.
if grep -qiE 'xwayland|DISPLAY=|X11' /tmp/wawona-cap-nested.log; then
  log "PASS: XWayland bridge initialized"
else
  log "NOTE: XWayland readiness not observed in log (may be lazy-start)"
fi

kill -0 "$HOST_PID" 2>/dev/null || { log "FAIL: parent compositor died"; exit 1; }
log "capability lane PASSED"
