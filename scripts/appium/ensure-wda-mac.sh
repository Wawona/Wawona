#!/usr/bin/env bash
# Keep WebDriverAgentMac listening (default :10100) for Appium Mac2.
# Xcode 26 WDA needs MacOSX Developer Testing frameworks on DYLD paths;
# without them the Runner aborts on lib_TestingInterop / _Testing_Foundation.
set -euo pipefail

HOST="${WAWONA_MAC2_WDA_HOST:-127.0.0.1}"
PORT="${WAWONA_MAC2_WDA_PORT:-10100}"
PIDFILE="${WAWONA_MAC2_WDA_PIDFILE:-/tmp/wawona-wda-mac.pid}"
LOG="${WAWONA_MAC2_WDA_LOG:-/tmp/wawona-wda-mac.log}"
URL="http://${HOST}:${PORT}"

XCODE_DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MAC_FW="${XCODE_DEV}/Platforms/MacOSX.platform/Developer/Library/Frameworks"
MAC_LIB="${XCODE_DEV}/Platforms/MacOSX.platform/Developer/usr/lib"
SHARED_FW="/Applications/Xcode.app/Contents/SharedFrameworks"

if [[ "${WAWONA_MAC2_FORCE_RESTART:-0}" == "1" ]]; then
  echo "WAWONA_MAC2_FORCE_RESTART=1: stopping WDA on ${URL}"
  if [[ -f "$PIDFILE" ]]; then
    old="$(cat "$PIDFILE" || true)"
    if [[ -n "${old}" ]]; then
      kill "$old" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  fi
  killall WebDriverAgentRunner-Runner 2>/dev/null || true
  sleep 1
elif curl -sf "${URL}/status" >/dev/null; then
  echo "wda-mac already up on ${URL}"
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

# Prefer TCC-granted /tmp/wda-mac-dd, then DerivedData / Appium-bundled.
# Override with WAWONA_MAC2_WDA_APP.
APP="${WAWONA_MAC2_WDA_APP:-}"
if [[ -z "$APP" || ! -x "$APP/Contents/MacOS/WebDriverAgentRunner-Runner" ]]; then
  APP=""
  for cand in \
    /tmp/wda-mac-dd/Build/Products/Debug/WebDriverAgentRunner-Runner.app \
    "${HOME}/Library/Developer/Xcode/DerivedData"/WebDriverAgentMac-*/Build/Products/Debug/WebDriverAgentRunner-Runner.app \
    "${HOME}/.appium/node_modules/appium-mac2-driver/WebDriverAgentMac"/build/Build/Products/Debug/WebDriverAgentRunner-Runner.app \
    "${HOME}/.local/share/appium-cli/node_modules/appium-mac2-driver/WebDriverAgentMac"/build/Build/Products/Debug/WebDriverAgentRunner-Runner.app
  do
    if [[ -x "${cand}/Contents/MacOS/WebDriverAgentRunner-Runner" ]]; then
      APP="$cand"
      break
    fi
  done
fi

if [[ -z "$APP" ]]; then
  echo "FAIL: no WebDriverAgentRunner-Runner.app. Build once via Appium Mac2 session or xcodebuild." >&2
  exit 1
fi

# Bundle TestingInterop next to Testing.framework when missing (Xcode 26).
FW_DIR="$APP/Contents/Frameworks"
mkdir -p "$FW_DIR"
if [[ ! -f "$FW_DIR/lib_TestingInterop.dylib" && -f "$MAC_LIB/lib_TestingInterop.dylib" ]]; then
  cp -f "$MAC_LIB/lib_TestingInterop.dylib" "$FW_DIR/"
  codesign --force --sign - "$FW_DIR/lib_TestingInterop.dylib" 2>/dev/null || true
fi

BIN="$APP/Contents/MacOS/WebDriverAgentRunner-Runner"
export DYLD_FRAMEWORK_PATH="${MAC_FW}${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
export DYLD_LIBRARY_PATH="${MAC_LIB}${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export DYLD_FALLBACK_FRAMEWORK_PATH="${SHARED_FW}${DYLD_FALLBACK_FRAMEWORK_PATH:+:$DYLD_FALLBACK_FRAMEWORK_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="${SHARED_FW}:${MAC_LIB}${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export USE_PORT="$PORT"
export USE_HOST="$HOST"

killall WebDriverAgentRunner-Runner 2>/dev/null || true
sleep 0.5

# New session: survive agent shell teardown; keep Xcode 26 Testing DYLD only on WDA.
python3 - "$BIN" "$PIDFILE" "$LOG" "$PORT" "$HOST" \
  "$DYLD_FRAMEWORK_PATH" "$DYLD_LIBRARY_PATH" \
  "$DYLD_FALLBACK_FRAMEWORK_PATH" "$DYLD_FALLBACK_LIBRARY_PATH" <<'PY'
import os, subprocess, sys

bin_path, pidfile, log, port, host, fw, lib, fbw, fbl = sys.argv[1:10]
env = os.environ.copy()
env["DYLD_FRAMEWORK_PATH"] = fw
env["DYLD_LIBRARY_PATH"] = lib
env["DYLD_FALLBACK_FRAMEWORK_PATH"] = fbw
env["DYLD_FALLBACK_LIBRARY_PATH"] = fbl
env["USE_PORT"] = port
env["USE_HOST"] = host
with open(log, "a", encoding="utf-8") as out:
    proc = subprocess.Popen(
        [bin_path],
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
  if curl -sf "${URL}/status" >/dev/null; then
    echo "wda-mac ready pid=$(cat "$PIDFILE") url=${URL} app=${APP}"
    exit 0
  fi
  sleep 1
done
echo "FAIL: WDA did not become ready (log: $LOG)" >&2
tail -40 "$LOG" >&2 || true
exit 1
