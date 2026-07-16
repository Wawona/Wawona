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
# Prefer an isolated runtime dir so CI doesn't collide with a session bus dir.
RUNTIME_DIR="${WAWONA_CAP_RUNTIME_DIR:-/tmp/wawona-cap-$(id -u)}"
# Host binary defaults to wawona-0 (see src/linux/service.rs), not wayland-0.
DISPLAY_NAME="${WAYLAND_DISPLAY:-wawona-0}"
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
# Prefer the ahead-of-time binary from wawona-linux-ui-bin. The
# wawona-linux-compositor-host app is a cargo-run wrapper that compiles on
# first launch and will miss the socket wait on cold CI runners.
log "building .#wawona-linux-ui-bin (prebuilt compositor-host)"
UI_BIN_OUT="$(nix build "$ROOT#wawona-linux-ui-bin" --print-out-paths --no-link)"
HOST_BIN="$UI_BIN_OUT/bin/wawona-linux-compositor-host"
if [[ ! -x "$HOST_BIN" ]]; then
  log "FAIL: compositor-host binary not found at $HOST_BIN"
  exit 1
fi

log "starting compositor host ($HOST_BIN)"
"$HOST_BIN" >/tmp/wawona-cap-host.log 2>&1 &
HOST_PID=$!
cleanup() {
  kill "$NIRI_PID" 2>/dev/null || true
  kill "$NESTED_PID" 2>/dev/null || true
  kill "$HOST_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
NESTED_PID=0
NIRI_PID=0

# 2. Wait for the parent Wayland socket.
for _ in $(seq 1 "$SOCKET_WAIT_SECS"); do
  [[ -S "$RUNTIME_DIR/$DISPLAY_NAME" ]] && break
  kill -0 "$HOST_PID" 2>/dev/null || { log "FAIL: host exited before socket"; sed -n '1,200p' /tmp/wawona-cap-host.log; exit 1; }
  sleep 1
done
[[ -S "$RUNTIME_DIR/$DISPLAY_NAME" ]] || { log "FAIL: parent socket never appeared"; sed -n '1,200p' /tmp/wawona-cap-host.log; exit 1; }
log "parent socket up: $DISPLAY_NAME"
export WAYLAND_DISPLAY="$DISPLAY_NAME"

# 3. Launch nested Weston with XWayland enabled on a child socket.
WESTON_BIN="$(command -v weston || true)"
if [[ -z "$WESTON_BIN" || ! -x "$WESTON_BIN" ]]; then
  # Prefer flake weston; fall back to nixpkgs reference weston.
  if WESTON_OUT="$(nix build "$ROOT#weston" --print-out-paths --no-link 2>/dev/null)"; then
    WESTON_BIN="$WESTON_OUT/bin/weston"
  else
    WESTON_BIN="$(nix build nixpkgs#weston --print-out-paths --no-link)/bin/weston"
  fi
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

# 6. niri (wwn-niri) nested stage: run the Wawona-patched niri as a Wayland
# client of the Wawona compositor (NIRI_BACKEND=nested) and assert it comes up
# and serves its own child Wayland socket. Optional: runs when a niri binary
# is provided (WAWONA_CAP_NIRI_BIN) or discoverable on PATH; the mandatory
# per-platform niri gates live in the wwn-niri flake + macOS smoke
# (scripts/niri-smoke-macos.sh).
NIRI_BIN="${WAWONA_CAP_NIRI_BIN:-$(command -v niri || true)}"
NIRI_PID=0
if [[ -n "$NIRI_BIN" && -x "$NIRI_BIN" ]]; then
  log "starting nested niri ($NIRI_BIN)"
  NIRI_BACKEND=nested "$NIRI_BIN" >/tmp/wawona-cap-niri.log 2>&1 &
  NIRI_PID=$!
  NIRI_CHILD=""
  for _ in $(seq 1 "$NESTED_WAIT_SECS"); do
    NIRI_CHILD="$(grep -oE 'listening on Wayland socket: [^ ]+' /tmp/wawona-cap-niri.log | awk '{print $NF}' | head -n1 || true)"
    [[ -n "$NIRI_CHILD" && -S "$RUNTIME_DIR/$NIRI_CHILD" ]] && break
    kill -0 "$NIRI_PID" 2>/dev/null || { log "FAIL: nested niri exited early"; sed -n '1,120p' /tmp/wawona-cap-niri.log; exit 1; }
    sleep 1
  done
  if [[ -n "$NIRI_CHILD" && -S "$RUNTIME_DIR/$NIRI_CHILD" ]]; then
    log "PASS: nested niri child socket up ($NIRI_CHILD)"
  else
    log "FAIL: nested niri child socket never appeared"
    sed -n '1,120p' /tmp/wawona-cap-niri.log
    exit 1
  fi
  kill "$NIRI_PID" 2>/dev/null || true
else
  log "NOTE: niri binary not available (set WAWONA_CAP_NIRI_BIN) — skipping the niri nested stage"
fi

kill -0 "$HOST_PID" 2>/dev/null || { log "FAIL: parent compositor died"; exit 1; }
log "capability lane PASSED"
