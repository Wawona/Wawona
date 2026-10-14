#!/usr/bin/env bash
# Keep a local Appium 3 server on :4723 (Mac2 / XCUITest / UiAutomator2).
# macOS has no setsid; use nohup + pidfile. Idempotent.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
export APPIUM_HOME="${APPIUM_HOME:-${HOME}/.local/share/appium-cli}"
PIDFILE="${WAWONA_APPIUM_PIDFILE:-/tmp/wawona-appium.pid}"
LOG="${WAWONA_APPIUM_LOG:-/tmp/wawona-appium-server.log}"
HOST="${WAWONA_APPIUM_HOST:-127.0.0.1}"
PORT="${WAWONA_APPIUM_PORT:-4723}"

if curl -sf "http://${HOST}:${PORT}/status" >/dev/null; then
  echo "appium already up on ${HOST}:${PORT}"
  exit 0
fi

if [[ -f "$PIDFILE" ]]; then
  old="$(cat "$PIDFILE" || true)"
  if [[ -n "${old}" ]] && kill -0 "$old" 2>/dev/null; then
    kill "$old" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PIDFILE"
fi

nohup env PATH="$PATH" APPIUM_HOME="$APPIUM_HOME" appium \
  --address "$HOST" --port "$PORT" --base-path / --log-level info \
  >>"$LOG" 2>&1 &
echo $! >"$PIDFILE"
disown "$(cat "$PIDFILE")" 2>/dev/null || true

for _ in $(seq 1 40); do
  if curl -sf "http://${HOST}:${PORT}/status" >/dev/null; then
    echo "appium ready pid=$(cat "$PIDFILE") url=http://${HOST}:${PORT}"
    exit 0
  fi
  sleep 1
done
echo "FAIL: Appium did not become ready (log: $LOG)" >&2
exit 1
