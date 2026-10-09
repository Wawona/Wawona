#!/usr/bin/env bash
# Linux-first MicroVM + waypipe automation proof (macOS).
#
# Prerequisites:
#   - Wawona.app running with wayland-0 bound
#   - Determinate / nix flakes; aarch64-linux builder for the guest
#
# Usage:
#   scripts/microvm-waypipe-session-smoke.sh
#   WAWONA_RUNTIME=/tmp/wawona-$UID scripts/microvm-waypipe-session-smoke.sh
#
# Success: session stays up, guest ready marker or vsock listen is observed,
# optional agent-device screenshot under .agent-device/test-artifacts/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELAY_OVERRIDE="${WAWONA_RELAY_FLAKE:-$ROOT/../Relay}"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
WAWONA_RUNTIME="${WAWONA_RUNTIME:-/tmp/wawona-$(id -u)}"
STATEDIR="${XDG_STATE_HOME:-$HOME/.local/state}/wawona-microvm"
READY_TIMEOUT="${WAWONA_MICROVM_READY_TIMEOUT:-240}"
SESSION_LOG="$STATEDIR/smoke-session.log"

mkdir -p "$ARTIFACTS" "$STATEDIR"
cd "$ROOT"

if [ ! -S "$WAWONA_RUNTIME/wayland-0" ]; then
  echo "smoke: missing $WAWONA_RUNTIME/wayland-0" >&2
  echo "  Start Wawona first (open -a Wawona / LaunchAgent), then re-run." >&2
  exit 1
fi

NIX_ARGS=(--extra-experimental-features "nix-command flakes")
if [ -f "$RELAY_OVERRIDE/import/vms/dependencies/vms/microvm-guest.nix" ]; then
  NIX_ARGS+=(--override-input wwn-relay "path:$RELAY_OVERRIDE")
  echo "smoke: overriding wwn-relay -> $RELAY_OVERRIDE" >&2
fi

echo "smoke: building wawona-microvm-session (local-before-CI)" >&2
nix build "${NIX_ARGS[@]}" "path:$ROOT#wawona-microvm-session" -o "$STATEDIR/result-session"

SESSION_BIN="$STATEDIR/result-session/bin/wawona-microvm-session"
if [ ! -x "$SESSION_BIN" ]; then
  echo "smoke: session binary missing at $SESSION_BIN" >&2
  exit 1
fi

export WAWONA_RUNTIME
export WAWONA_MICROVM_READY_TIMEOUT="$READY_TIMEOUT"
export WAWONA_MICROVM_SESSION="$SESSION_BIN"

echo "smoke: launching session -> $SESSION_LOG" >&2
"$SESSION_BIN" >"$SESSION_LOG" 2>&1 &
SESSION_PID=$!

cleanup() {
  if kill -0 "$SESSION_PID" 2>/dev/null; then
    kill "$SESSION_PID" 2>/dev/null || true
    wait "$SESSION_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ok=0
for _ in $(seq 1 "$READY_TIMEOUT"); do
  if ! kill -0 "$SESSION_PID" 2>/dev/null; then
    echo "smoke: session exited early; tail of $SESSION_LOG:" >&2
    tail -n 80 "$SESSION_LOG" >&2 || true
    exit 1
  fi
  if grep -qE 'guest ready|supervising|proceeding \(vsock' "$SESSION_LOG" 2>/dev/null; then
    ok=1
    break
  fi
  sleep 1
done

if [ "$ok" -ne 1 ]; then
  echo "smoke: timed out waiting for session ready; tail:" >&2
  tail -n 80 "$SESSION_LOG" >&2 || true
  exit 1
fi

echo "smoke: session ready (pid=$SESSION_PID)" >&2
cp "$SESSION_LOG" "$ARTIFACTS/microvm-waypipe-session.log" 2>/dev/null || true

if command -v agent-device >/dev/null 2>&1; then
  echo "smoke: capturing agent-device screenshot (Multi-Touch path for client taps)" >&2
  # Host UI chrome may use AX; guest foot pixels need Multi-Touch when interacting.
  agent-device screenshot --session microvm-smoke \
    --out "$ARTIFACTS/microvm-waypipe-session.png" 2>/dev/null \
    || echo "smoke: screenshot skipped (no agent-device session); log proof retained" >&2
fi

echo "smoke: PASS (supervised MicroVM + waypipe session is up)" >&2
# Leave session running only if WAWONA_MICROVM_SMOKE_KEEP=1
if [ "${WAWONA_MICROVM_SMOKE_KEEP:-0}" != "1" ]; then
  cleanup
  trap - EXIT INT TERM
fi
