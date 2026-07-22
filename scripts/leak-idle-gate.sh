#!/usr/bin/env bash
# Leak-idle CI gate: Start nested client → sample memory for HOLD_SEC → plateau check.
#
# Replaces ad-hoc agent-device + Instruments MCP dogfood with a runner-safe script.
# Instruments MCP / xctrace Allocations are NOT used here (empty on iOS 26 sim —
# see ISSUE-012). Gate is phys_footprint / dumpsys TOTAL PSS plateau, matching the
# Leak+Idle campaign in .agent-device/test-artifacts/instruments/.
#
# Usage:
#   scripts/leak-idle-gate.sh ios
#   scripts/leak-idle-gate.sh android
#   scripts/leak-idle-gate.sh macos
#   scripts/leak-idle-gate.sh all          # ios + android + macos (skip if no device)
#   scripts/leak-idle-gate.sh summary      # print LEAK_GATE_* lines from prior runs
#
# Env (shared with agent-device-smoke.sh):
#   WAWONA_IOS_SIM / WAWONA_IOS_APP / WAWONA_ANDROID_SERIAL / WAWONA_ANDROID_APK
#   WAWONA_MACOS_APP
# Gate thresholds:
#   WAWONA_LEAK_HOLD_SEC=60
#   WAWONA_LEAK_SAMPLE_SEC=15
#   WAWONA_LEAK_PLATEAU_MB=20   # max(max−min) during hold
#   WAWONA_LEAK_MONO_MB=8       # fail if every sample climbs and total ≥ this
#   WAWONA_LEAK_STRICT=1        # fail if target skipped (CI); default 0 locally
#
# Exit: 0 all requested targets pass; 1 any fail; 2 skip-only when STRICT.
# On failure prints: LEAK_GATE_FAIL targets=ios,android
# Always writes: .agent-device/test-artifacts/leak-idle-gate/<target>/verdict.json

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_ROOT="$ROOT/.agent-device/test-artifacts/leak-idle-gate"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
IOS_BUNDLE="${WAWONA_IOS_BUNDLE:-com.aspauldingcode.Wawona}"
ANDROID_PKG="${WAWONA_ANDROID_PACKAGE:-com.aspauldingcode.wawona}"
LANE="${1:-all}"
STRICT="${WAWONA_LEAK_STRICT:-0}"

# shellcheck source=scripts/lib/leak-idle-measure.sh
source "$ROOT/scripts/lib/leak-idle-measure.sh"
# shellcheck source=scripts/lib/agent-device-ios-system-ui.sh
source "$ROOT/scripts/lib/agent-device-ios-system-ui.sh"

mkdir -p "$ARTIFACTS_ROOT"
cd "$ROOT"

if ! command -v agent-device >/dev/null; then
  echo "agent-device not found on PATH" >&2
  exit 1
fi
echo "== leak-idle-gate agent-device $(agent-device --version) =="
echo "== hold=${WAWONA_LEAK_HOLD_SEC}s sample=${WAWONA_LEAK_SAMPLE_SEC}s plateau=${WAWONA_LEAK_PLATEAU_MB}MB mono=${WAWONA_LEAK_MONO_MB}MB =="

stop_agent_device_daemons() {
  pkill -f "agent-device/dist/src/internal/daemon.js" 2>/dev/null || true
  sleep 1
}

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

# Sample hold loop for a target. sample_cmd is a shell snippet that prints MB.
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

run_ios() {
  local out_dir="$ARTIFACTS_ROOT/ios"
  mkdir -p "$out_dir"
  local sess=wawona-ios-leak-idle
  local ad_common=(--platform ios --device "$IOS_DEVICE" --session "$sess")

  echo "== iOS leak-idle: simulator '$IOS_DEVICE' =="
  xcrun simctl bootstatus "$IOS_DEVICE" -b || xcrun simctl boot "$IOS_DEVICE" || true
  xcrun simctl bootstatus "$IOS_DEVICE"
  stop_agent_device_daemons

  agent-device prepare ios-runner --device "$IOS_DEVICE" --session "$sess" \
    --timeout "${WAWONA_IOS_PREPARE_TIMEOUT_MS:-600000}"

  if [ -n "${WAWONA_IOS_APP:-}" ]; then
    echo "== iOS: install $WAWONA_IOS_APP =="
    agent-device install "$WAWONA_IOS_APP" "${ad_common[@]}"
  fi

  agent-device open "$IOS_BUNDLE" "${ad_common[@]}"
  ios_prepare_system_ui || true
  agent-device wait 2000 "${ad_common[@]}" || true

  agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device press 'text="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device find Continue press --first "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device click 201 493 "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 2500 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"

  if ! agent-device wait 'id="wwn.machines.root"' 20000 "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device wait 'text="Machine Configuration"' 8000 "${ad_common[@]}" >/dev/null 2>&1; then
    agent-device screenshot "$out_dir/ios-no-machines.png" "${ad_common[@]}" || true
    write_verdict ios fail "machines_home_not_reached"
    agent-device close "${ad_common[@]}" || true
    stop_agent_device_daemons
    return 1
  fi

  local udid
  udid="$(ios_resolve_udid)"
  if [ -z "$udid" ]; then
    write_verdict ios fail "no_sim_udid"
    return 1
  fi
  export WAWONA_IOS_UDID="$udid"

  if ! agent-device press 'id="wwn.machines.start"' "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device press 'label="Start"' "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device find Start press --first "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device click 69 374 "${ad_common[@]}" >/dev/null 2>&1; then
    agent-device screenshot "$out_dir/ios-start-fail.png" "${ad_common[@]}" || true
    write_verdict ios fail "start_not_found"
    agent-device close "${ad_common[@]}" || true
    stop_agent_device_daemons
    return 1
  fi
  agent-device wait 4000 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"
  agent-device wait 2000 "${ad_common[@]}" || true
  agent-device screenshot "$out_dir/ios-running.png" "${ad_common[@]}" || true

  local pid
  pid="$(leak_ios_pid "$udid" "$IOS_BUNDLE")"
  if [ -z "$pid" ]; then
    write_verdict ios fail "pid_not_found"
    agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 || true
    agent-device close "${ad_common[@]}" || true
    stop_agent_device_daemons
    return 1
  fi
  echo "== iOS pid=$pid udid=$udid =="

  if ! sample_hold ios "$out_dir" leak_sample_apple_mb "$pid" "$udid"; then
    write_verdict ios fail "plateau_or_sample"
    agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 || true
    agent-device screenshot "$out_dir/ios-after-fail.png" "${ad_common[@]}" || true
    agent-device close "${ad_common[@]}" || true
    stop_agent_device_daemons
    return 1
  fi

  agent-device press 'id="wwn.machines.stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || true
  agent-device wait 2000 "${ad_common[@]}" || true
  agent-device screenshot "$out_dir/ios-after-stop.png" "${ad_common[@]}" || true
  write_verdict ios pass "plateau_ok"
  agent-device close "${ad_common[@]}" || true
  stop_agent_device_daemons
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
  echo "== Android leak-idle: serial=$serial =="
  adb -s "$serial" shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

  if [ -n "${WAWONA_ANDROID_APK:-}" ]; then
    adb -s "$serial" uninstall "$ANDROID_PKG" >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"

  local sess=wawona-android-leak-idle
  local ad_common=(--platform android --serial "$serial" --session "$sess")

  android_press_id() {
    local id="$1"
    agent-device press "id=\"$id\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    android_uia_tap_id "$id" && return 0
    return 1
  }

  agent-device open "$ANDROID_PKG" "${ad_common[@]}"
  agent-device wait 3000 "${ad_common[@]}" || true
  agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 2000 "${ad_common[@]}" || true

  if ! agent-device wait 'id="wwn.machines.root"' 20000 "${ad_common[@]}" >/dev/null 2>&1 \
    && ! android_uia_has_text "Machine Configuration"; then
    write_verdict android fail "machines_home_not_reached"
    agent-device close "${ad_common[@]}" || true
    return 1
  fi

  if ! android_press_id "wwn.machines.start" \
    && ! agent-device press 'label="Start"' "${ad_common[@]}" >/dev/null 2>&1; then
    write_verdict android fail "start_not_found"
    agent-device screenshot "$out_dir/android-start-fail.png" "${ad_common[@]}" || true
    agent-device close "${ad_common[@]}" || true
    return 1
  fi
  agent-device wait 5000 "${ad_common[@]}" || true
  agent-device screenshot "$out_dir/android-running.png" "${ad_common[@]}" || true

  if ! sample_hold android "$out_dir" leak_sample_android_pss_mb "$serial" "$ANDROID_PKG"; then
    write_verdict android fail "plateau_or_sample"
    agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 || true
    agent-device screenshot "$out_dir/android-after-fail.png" "${ad_common[@]}" || true
    agent-device close "${ad_common[@]}" || true
    return 1
  fi

  agent-device press 'id="wwn.machines.stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || true
  agent-device screenshot "$out_dir/android-after-stop.png" "${ad_common[@]}" || true
  write_verdict android pass "plateau_ok"
  agent-device close "${ad_common[@]}" || true
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
  open "$app"
  sleep 5

  local pid
  pid="$(leak_macos_pid)"
  if [ -z "$pid" ]; then
    write_verdict macos fail "pid_not_found"
    return 1
  fi
  echo "== macOS pid=$pid =="

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
