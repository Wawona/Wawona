#!/usr/bin/env bash
# Keep a local Appium 3 server on :4723 (Mac2 / XCUITest / UiAutomator2).
# macOS has no setsid; use nohup + pidfile. Idempotent.
#
# Do NOT export DYLD_* here. Node/Appium dies when MacOSX Developer Testing
# paths override its dyld search. Xcode 26 WDA DYLD belongs in ensure-wda-mac.sh.
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

# New session so Cursor/agent shell teardown cannot SIGHUP Node.
# Strip inherited Testing DYLD so a parent shell cannot poison Node.
python3 - "$HOST" "$PORT" "$PIDFILE" "$LOG" "$PATH" "$APPIUM_HOME" <<'PY'
import os, subprocess, sys, shutil

host, port, pidfile, log, path, appium_home = sys.argv[1:7]
env = os.environ.copy()
env["PATH"] = path
env["APPIUM_HOME"] = appium_home
for k in (
    "DYLD_FRAMEWORK_PATH",
    "DYLD_LIBRARY_PATH",
    "DYLD_FALLBACK_FRAMEWORK_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
):
    env.pop(k, None)
appium = shutil.which("appium", path=path) or "appium"
with open(log, "a", encoding="utf-8") as out:
    proc = subprocess.Popen(
        [
            appium,
            "--address",
            host,
            "--port",
            port,
            "--base-path",
            "/",
            "--log-level",
            "info",
        ],
        stdout=out,
        stderr=subprocess.STDOUT,
        env=env,
        start_new_session=True,
        close_fds=True,
    )
open(pidfile, "w", encoding="utf-8").write(str(proc.pid))
print(proc.pid)
PY

for _ in $(seq 1 40); do
  if curl -sf "http://${HOST}:${PORT}/status" >/dev/null; then
    echo "appium ready pid=$(cat "$PIDFILE") url=http://${HOST}:${PORT}"
    exit 0
  fi
  sleep 1
done
echo "FAIL: Appium did not become ready (log: $LOG)" >&2
exit 1
