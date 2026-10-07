#!/usr/bin/env bash
# Leak-idle CI gate: launch product → sample memory for HOLD_SEC → plateau check.
#
# Runner tools only (industry standard):
#   iOS:    xcrun simctl install/launch + vmmap phys_footprint
#   Android: adb + uiautomator (Welcome/Start) + dumpsys meminfo TOTAL PSS
#   macOS:  direct exec of Wawona.app binary + vmmap
#
# Does NOT use agent-device CLI. Agent-device stays for local/lab/vphone.
# Instruments MCP / xctrace Allocations are NOT used (empty on iOS 26 sim).
#
# Usage:
#   scripts/leak-idle-gate.sh ios
#   scripts/leak-idle-gate.sh android
#   scripts/leak-idle-gate.sh macos
#   scripts/leak-idle-gate.sh all
#   scripts/leak-idle-gate.sh summary
#
# Env:
#   WAWONA_IOS_SIM / WAWONA_IOS_APP / WAWONA_ANDROID_SERIAL / WAWONA_ANDROID_APK
#   WAWONA_MACOS_APP
#   WAWONA_LEAK_HOLD_SEC=60
#   WAWONA_LEAK_SAMPLE_SEC=15
#   WAWONA_LEAK_PLATEAU_MB=20
#   WAWONA_LEAK_MONO_MB=8
#   WAWONA_LEAK_STRICT=1
#
# Exit: 0 all requested targets pass; 1 any fail; 2 skip-only when STRICT.
# Always writes: .agent-device/test-artifacts/leak-idle-gate/<target>/verdict.json

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_ROOT="$ROOT/.agent-device/test-artifacts/leak-idle-gate"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
IOS_BUNDLE="${WAWONA_IOS_BUNDLE:-com.aspauldingcode.Wawona}"
ANDROID_PKG="${WAWONA_ANDROID_PACKAGE:-com.aspauldingcode.wawona}"
ANDROID_ACTIVITY="${WAWONA_ANDROID_ACTIVITY:-com.aspauldingcode.wawona.MainActivity}"
LANE="${1:-all}"
STRICT="${WAWONA_LEAK_STRICT:-0}"

# shellcheck source=scripts/lib/leak-idle-measure.sh
source "$ROOT/scripts/lib/leak-idle-measure.sh"

mkdir -p "$ARTIFACTS_ROOT"
cd "$ROOT"

echo "== leak-idle-gate (simctl / adb / uiautomator; no agent-device) =="
echo "== hold=${WAWONA_LEAK_HOLD_SEC}s sample=${WAWONA_LEAK_SAMPLE_SEC}s plateau=${WAWONA_LEAK_PLATEAU_MB}MB mono=${WAWONA_LEAK_MONO_MB}MB =="

write_verdict() {
  local target="$1"
  local status="$2"
  local reason="$3"
  local out_dir="$ARTIFACTS_ROOT/$target"
  mkdir -p "$out_dir"
  TARGET="$target" STATUS="$status" REASON="$reason" OUT="$out_dir/verdict.json" \
    PLATEAU_FILE="$out_dir/${target}-plateau.json" python3 <<'PY'
import json, os, datetime, pathlib
target = os.environ["TARGET"]
status = os.environ["STATUS"]
reason = os.environ["REASON"]
path = pathlib.Path(os.environ["OUT"])
payload = {
    "target": target,
    "status": status,
    "reason": reason,
    "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hold_sec": int(os.environ.get("WAWONA_LEAK_HOLD_SEC", "60")),
    "plateau_mb": float(os.environ.get("WAWONA_LEAK_PLATEAU_MB", "20")),
}
pf = pathlib.Path(os.environ["PLATEAU_FILE"])
if pf.is_file():
    payload["plateau"] = json.loads(pf.read_text())
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
  echo "$status" >"$out_dir/status.txt"
  echo "== verdict $target: $status ($reason) =="
}

sample_hold() {
  local target="$1"
  local out_dir="$2"
  shift 2
  local hold="${WAWONA_LEAK_HOLD_SEC}"
  local every="${WAWONA_LEAK_SAMPLE_SEC}"
  local timeline="$out_dir/${target}-timeline.txt"
  local csv=""
  local t=0
  local mb
  {
    echo "# target=$target hold_sec=$hold sample_sec=$every plateau_mb=$WAWONA_LEAK_PLATEAU_MB"
    echo "# t_sec mb iso"
  } >"$timeline"
  while [ "$t" -le "$hold" ]; do
    mb="$("$@")" || return 1
    if [ -z "$mb" ]; then
      echo "FAIL: empty sample at t=${t}s ($target)" >&2
      return 1
    fi
    echo "$t $mb $(leak_now_iso)" >>"$timeline"
    if [ -z "$csv" ]; then
      csv="$mb"
    else
      csv="$csv,$mb"
    fi
    if [ "$t" -ge "$hold" ]; then
      break
    fi
    sleep "$every"
    t=$((t + every))
  done
  printf '%s\n' "$csv" >"$out_dir/${target}-samples.csv"
  leak_analyze_plateau "$csv" "$out_dir/${target}-plateau.json"
}

ios_ensure_sim() {
  if ! xcrun simctl list devices available | grep -q "$IOS_DEVICE ("; then
    echo "Creating simulator '$IOS_DEVICE'"
    local DEVTYPE RUNTIME
    DEVTYPE=$(xcrun simctl list devicetypes | grep -F "$IOS_DEVICE (" | sed -E 's/.*\((com[^)]*)\).*/\1/' | head -1)
    RUNTIME=$(xcrun simctl list runtimes | grep -E "^iOS" | tail -1 | sed -E 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9._-]+).*/\1/')
    xcrun simctl create "$IOS_DEVICE" "$DEVTYPE" "$RUNTIME"
  fi
}

run_ios() {
  local out_dir="$ARTIFACTS_ROOT/ios"
  mkdir -p "$out_dir"

  echo "== iOS leak-idle: simulator '$IOS_DEVICE' (simctl) =="
  ios_ensure_sim
  local udid
  udid=$(xcrun simctl list devices available | grep "$IOS_DEVICE (" | grep -oE '[A-F0-9-]{36}' | head -1)
  if [ -z "$udid" ]; then
    write_verdict ios fail "no_sim_udid"
    return 1
  fi
  export WAWONA_IOS_UDID="$udid"

  xcrun simctl bootstatus "$udid" -b || xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid"

  if [ -n "${WAWONA_IOS_APP:-}" ]; then
    echo "== iOS: install $WAWONA_IOS_APP =="
    local stage
    stage="$(mktemp -d)/Wawona.app"
    cp -R "$WAWONA_IOS_APP" "$stage"
    chmod -R u+w "$stage"
    xcrun simctl uninstall "$udid" "$IOS_BUNDLE" 2>/dev/null || true
    xcrun simctl install "$udid" "$stage"
  fi

  rm -f "$out_dir"/ios-*.png
  xcrun simctl terminate "$udid" "$IOS_BUNDLE" 2>/dev/null || true
  set +e
  xcrun simctl launch "$udid" "$IOS_BUNDLE" >"$out_dir/launch.out" 2>"$out_dir/launch.err"
  local launch_rc=$?
  set -e
  if [ "$launch_rc" -ne 0 ]; then
    write_verdict ios fail "simctl_launch_rc=$launch_rc"
    cat "$out_dir/launch.out" "$out_dir/launch.err" || true
    return 1
  fi

  local pid=""
  local i
  for i in $(seq 1 45); do
    pid="$(leak_ios_pid "$udid" "$IOS_BUNDLE")"
    [ -n "$pid" ] && break
    sleep 1
  done
  xcrun simctl io "$udid" screenshot "$out_dir/ios-running.png" || true

  if [ -z "$pid" ]; then
    write_verdict ios fail "pid_not_found"
    xcrun simctl terminate "$udid" "$IOS_BUNDLE" 2>/dev/null || true
    return 1
  fi
  echo "== iOS pid=$pid udid=$udid =="

  if ! sample_hold ios "$out_dir" leak_sample_apple_mb "$pid" "$udid"; then
    write_verdict ios fail "plateau_or_sample"
    xcrun simctl terminate "$udid" "$IOS_BUNDLE" 2>/dev/null || true
    return 1
  fi

  xcrun simctl terminate "$udid" "$IOS_BUNDLE" 2>/dev/null || true
  xcrun simctl io "$udid" screenshot "$out_dir/ios-after-stop.png" || true
  write_verdict ios pass "plateau_ok"
  return 0
}

run_android() {
  local out_dir="$ARTIFACTS_ROOT/android"
  mkdir -p "$out_dir"
  local serial="${WAWONA_ANDROID_SERIAL:-}"
  if [ -z "$serial" ]; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  if [ -z "$serial" ]; then
    echo "== Android: no device =="
    write_verdict android skip "no_device"
    [ "$STRICT" = "1" ] && return 2
    return 0
  fi
  export ANDROID_SERIAL="$serial"
  echo "== Android leak-idle: serial=$serial (adb + uiautomator) =="
  adb -s "$serial" shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

  if [ -n "${WAWONA_ANDROID_APK:-}" ]; then
    adb -s "$serial" uninstall "$ANDROID_PKG" >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"

  dismiss_android_blockers() {
    adb -s "$serial" shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
  }

  adb -s "$serial" shell am force-stop "$ANDROID_PKG" 2>/dev/null || true
  adb -s "$serial" shell am start -W -n "$ANDROID_PKG/$ANDROID_ACTIVITY" \
    | tee "$out_dir/am-start.txt"
  sleep 3
  dismiss_android_blockers

  # Welcome → Machines (uiautomator resource-id / text).
  android_uia_tap_id "wwn.welcome.continue" || android_uia_tap_text "Continue" || true
  sleep 2
  dismiss_android_blockers

  if ! android_uia_wait id "wwn.machines.root" 20000 \
    && ! android_uia_wait text "Machine Configuration" 8000; then
    write_verdict android fail "machines_home_not_reached"
    adb -s "$serial" exec-out screencap -p >"$out_dir/android-no-machines.png" || true
    android_uia_dump >"$out_dir/android-no-machines-ui.xml" 2>/dev/null || true
    adb -s "$serial" shell am force-stop "$ANDROID_PKG" 2>/dev/null || true
    return 1
  fi

  dismiss_android_blockers
  if ! android_uia_tap_id "wwn.machines.start" \
    && ! android_uia_tap_text "Start" \
    && ! android_tap_ref 227 1039; then
    write_verdict android fail "start_not_found"
    adb -s "$serial" exec-out screencap -p >"$out_dir/android-start-fail.png" || true
    android_uia_dump >"$out_dir/android-start-fail-ui.xml" 2>/dev/null || true
    adb -s "$serial" shell am force-stop "$ANDROID_PKG" 2>/dev/null || true
    return 1
  fi
  sleep 5
  adb -s "$serial" exec-out screencap -p >"$out_dir/android-running.png" || true

  if ! sample_hold android "$out_dir" leak_sample_android_pss_mb "$serial" "$ANDROID_PKG"; then
    write_verdict android fail "plateau_or_sample"
    android_uia_tap_id "wwn.machines.stop" || android_uia_tap_text "Stop" || true
    adb -s "$serial" exec-out screencap -p >"$out_dir/android-after-fail.png" || true
    adb -s "$serial" shell am force-stop "$ANDROID_PKG" 2>/dev/null || true
    return 1
  fi

  android_uia_tap_id "wwn.machines.stop" || android_uia_tap_text "Stop" || true
  adb -s "$serial" exec-out screencap -p >"$out_dir/android-after-stop.png" || true
  write_verdict android pass "plateau_ok"
  adb -s "$serial" shell am force-stop "$ANDROID_PKG" 2>/dev/null || true
  return 0
}

run_macos() {
  local out_dir="$ARTIFACTS_ROOT/macos"
  mkdir -p "$out_dir"
  local app="${WAWONA_MACOS_APP:-}"
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    for cand in \
      "$ROOT/result-macos/Wawona.app" \
      "$ROOT/dist/Wawona.app" \
      "$ROOT/product-macos-app/Wawona.app"; do
      if [ -d "$cand" ]; then
        app="$cand"
        break
      fi
    done
  fi
  if [ -z "$app" ] || [ ! -d "$app" ]; then
    echo "== macOS: no Wawona.app (set WAWONA_MACOS_APP) =="
    write_verdict macos skip "no_app"
    [ "$STRICT" = "1" ] && return 2
    return 0
  fi

  echo "== macOS leak-idle: $app =="
  pkill -x Wawona 2>/dev/null || true
  sleep 1
  xattr -cr "$app" 2>/dev/null || true
  chmod +x "$app/Contents/MacOS/Wawona" 2>/dev/null || true
  find "$app/Contents/MacOS" -type f -exec chmod +x {} + 2>/dev/null || true
  find "$app/Contents/Resources/bin" -type f -exec chmod +x {} + 2>/dev/null || true
  "$app/Contents/MacOS/Wawona" >"$out_dir/macos-app.log" 2>&1 &
  local pid=$!
  local settle=0
  while [ "$settle" -lt "${WAWONA_LEAK_LAUNCH_SETTLE_SEC:-8}" ]; do
    kill -0 "$pid" 2>/dev/null && break
    sleep 1
    settle=$((settle + 1))
  done
  if ! kill -0 "$pid" 2>/dev/null; then
    pid="$(leak_macos_pid)"
  fi
  if [ -z "$pid" ]; then
    write_verdict macos fail "pid_not_found (see macos-app.log)"
    return 1
  fi
  echo "== macOS pid=$pid =="

  # Optional AX Start (TCC may deny on runners; idle launch still samples).
  osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  if exists process "Wawona" then
    tell process "Wawona"
      set frontmost to true
      try
        click (first button whose name is "Start")
      end try
    end tell
  end if
end tell
EOF
  sleep 4

  if ! sample_hold macos "$out_dir" leak_sample_apple_mb "$pid"; then
    write_verdict macos fail "plateau_or_sample"
    pkill -x Wawona 2>/dev/null || true
    return 1
  fi

  if command -v leaks >/dev/null; then
    leaks "$pid" 2>&1 | tee "$out_dir/macos-leaks.txt" >/dev/null || true
  fi

  write_verdict macos pass "plateau_ok"
  pkill -x Wawona 2>/dev/null || true
  return 0
}

print_summary() {
  local failed="" skipped="" passed=""
  local d t st
  for d in "$ARTIFACTS_ROOT"/*/; do
    [ -d "$d" ] || continue
    t="$(basename "$d")"
    st="$(cat "$d/status.txt" 2>/dev/null || echo missing)"
    case "$st" in
      pass) passed="${passed:+$passed,}$t" ;;
      skip) skipped="${skipped:+$skipped,}$t" ;;
      *) failed="${failed:+$failed,}$t" ;;
    esac
  done
  echo "LEAK_GATE_PASS targets=${passed:-}"
  echo "LEAK_GATE_SKIP targets=${skipped:-}"
  if [ -n "$failed" ]; then
    echo "LEAK_GATE_FAIL targets=$failed"
    return 1
  fi
  return 0
}

FAILED=0
SKIPPED_STRICT=0

run_one() {
  local name="$1"
  local rc=0
  set +e
  "run_$name"
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    SKIPPED_STRICT=1
  elif [ "$rc" -ne 0 ]; then
    FAILED=1
  fi
}

case "$LANE" in
  ios) run_one ios ;;
  android) run_one android ;;
  macos) run_one macos ;;
  all)
    run_one ios
    run_one android
    run_one macos
    ;;
  summary)
    print_summary
    exit $?
    ;;
  *)
    echo "usage: $0 [ios|android|macos|all|summary]" >&2
    exit 1
    ;;
esac

print_summary || true
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
if [ "$SKIPPED_STRICT" -ne 0 ]; then
  exit 2
fi
exit 0
