#!/usr/bin/env bash
# Functional macOS compat-matrix smoke: launch the Wawona compositor in
# headless host mode, verify the Wayland socket comes up, then run each
# bundled client against it briefly and assert it holds a live connection.
#
# Local:  ./scripts/ci-macos-compat-smoke.sh
# CI:     runs on the macOS smoke jobs after the app package is built.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/wawona-$(id -u)}"
DISPLAY_NAME="${WAYLAND_DISPLAY:-wayland-0}"
CLIENT_HOLD_SECS="${WAWONA_SMOKE_CLIENT_SECS:-6}"
SOCKET_WAIT_SECS="${WAWONA_SMOKE_SOCKET_WAIT:-60}"

log() { echo "[macos-smoke] $*"; }

# 1. Resolve the app bundle (build if needed).
APP_BIN="${WAWONA_APP_BIN:-}"
if [[ -z "$APP_BIN" ]]; then
  log "building .#wawona-macos"
  OUT=$(nix build "$ROOT#wawona-macos" --print-out-paths --no-link)
  APP_BIN="$OUT/Applications/Wawona.app/Contents/MacOS/Wawona"
fi
if [[ ! -x "$APP_BIN" ]]; then
  log "FAIL: compositor binary not found at $APP_BIN"
  exit 1
fi
APP_RES="$(cd "$(dirname "$APP_BIN")/../Resources" 2>/dev/null && pwd || true)"

# 2. Launch compositor in host mode.
mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
rm -f "$RUNTIME_DIR/$DISPLAY_NAME" "$RUNTIME_DIR/$DISPLAY_NAME.lock" "$RUNTIME_DIR/instance.lock"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"

log "starting compositor host ($APP_BIN --compositor-host)"
"$APP_BIN" --compositor-host >/tmp/wawona-smoke-host.log 2>&1 &
HOST_PID=$!
cleanup() {
  kill "$HOST_PID" 2>/dev/null || true
  wait "$HOST_PID" 2>/dev/null || true
}
trap cleanup EXIT

# 3. Wait for the Wayland socket.
for _ in $(seq 1 "$SOCKET_WAIT_SECS"); do
  if [[ -S "$RUNTIME_DIR/$DISPLAY_NAME" ]]; then
    break
  fi
  if ! kill -0 "$HOST_PID" 2>/dev/null; then
    log "FAIL: compositor exited before socket appeared"
    sed -n '1,120p' /tmp/wawona-smoke-host.log || true
    exit 1
  fi
  sleep 1
done
if [[ ! -S "$RUNTIME_DIR/$DISPLAY_NAME" ]]; then
  log "FAIL: socket $RUNTIME_DIR/$DISPLAY_NAME never appeared"
  sed -n '1,120p' /tmp/wawona-smoke-host.log || true
  exit 1
fi
log "socket up: $RUNTIME_DIR/$DISPLAY_NAME"
export WAYLAND_DISPLAY="$DISPLAY_NAME"

# 4. Locate bundled clients (inside the app bundle) or fall back to PATH.
find_client() {
  local name="$1"
  local candidate
  for candidate in \
    "$APP_RES/bin/$name" \
    "$APP_RES/libexec/$name" \
    "$(dirname "$APP_BIN")/$name"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  command -v "$name" 2>/dev/null || true
}

FAILURES=0
run_case() {
  local name="$1"
  local bin
  bin="$(find_client "$name")"
  if [[ -z "$bin" ]]; then
    log "SKIP  $name (binary not found)"
    return 0
  fi
  log "START $name ($bin)"
  "$bin" >/tmp/wawona-smoke-"$name".log 2>&1 &
  local pid=$!
  sleep "$CLIENT_HOLD_SECS"
  if kill -0 "$pid" 2>/dev/null; then
    # Client held a connection for the whole window: pass.
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    log "PASS  $name"
  else
    local rc=0
    wait "$pid" || rc=$?
    log "FAIL  $name (exited early rc=$rc)"
    sed -n '1,60p' /tmp/wawona-smoke-"$name".log || true
    FAILURES=$((FAILURES + 1))
  fi
}

run_case weston-simple-shm
run_case weston-flower
run_case weston-smoke
run_case weston-clickdot

# 5. Compositor must still be alive after the client matrix.
if ! kill -0 "$HOST_PID" 2>/dev/null; then
  log "FAIL: compositor died during client matrix"
  sed -n '1,160p' /tmp/wawona-smoke-host.log || true
  exit 1
fi

if [[ "$FAILURES" -gt 0 ]]; then
  log "done with $FAILURES failing client(s)"
  exit 1
fi
log "all clients passed"
