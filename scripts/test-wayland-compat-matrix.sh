#!/usr/bin/env bash
set -euo pipefail

# Smoke matrix for local Wayland client compatibility.
# Run this while Wawona is active (`nix run`) or export runtime vars first.

RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
DISPLAY_NAME="${WAYLAND_DISPLAY:-wayland-0}"

if [[ -z "${RUNTIME_DIR}" ]]; then
  echo "XDG_RUNTIME_DIR is not set."
  echo "Example:"
  echo "  export XDG_RUNTIME_DIR=/tmp/wawona-\$(id -u)"
  echo "  export WAYLAND_DISPLAY=wayland-0"
  exit 1
fi

export WAYLAND_DISPLAY="${DISPLAY_NAME}"

echo "[matrix] runtime=${XDG_RUNTIME_DIR} display=${WAYLAND_DISPLAY}"

run_case() {
  local name="$1"
  shift
  local bin="$1"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "[matrix] SKIP  ${name} (missing ${bin})"
    return
  fi
  echo "[matrix] START ${name}"
  local rc=0
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout 20 "$@" >/tmp/wawona-matrix-"${name}".log 2>&1 || rc=$?
  else
    python3 - "$@" >/tmp/wawona-matrix-"${name}".log 2>&1 <<'PY' || rc=$?
import subprocess, sys
cmd = sys.argv[1:]
try:
    rc = subprocess.run(cmd, timeout=20).returncode
except subprocess.TimeoutExpired:
    rc = 124
sys.exit(rc)
PY
  fi
  if [[ ${rc} -eq 0 ]]; then
    echo "[matrix] PASS  ${name}"
  else
    echo "[matrix] FAIL  ${name} (exit=${rc})"
    echo "----- ${name} log -----"
    sed -n '1,120p' /tmp/wawona-matrix-"${name}".log || true
    echo "-----------------------"
  fi
}

# Core local clients (expected to exist in the dev environment).
run_case weston-terminal weston-terminal
run_case foot foot -e sh -lc 'printf "foot-ok\n"; sleep 1'

# Optional toolkit probes (skip if missing).
if command -v gtk4-demo >/dev/null 2>&1; then
  run_case gtk4-demo gtk4-demo --run=application >/dev/null
fi
if command -v qml >/dev/null 2>&1; then
  run_case qt-qml qml -v
fi

echo "[matrix] done"
