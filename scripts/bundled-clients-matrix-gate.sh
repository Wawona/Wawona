#!/usr/bin/env bash
# Bundled clients × platform matrix gate.
#
# One automated pass: for every Apple/Android/macOS target that has a runnable
# binary, exercise every kBundledClients option (nested weston/niri + demos).
# Writes a rolling log + summary that names each FAIL cell.
#
# Usage:
#   scripts/bundled-clients-matrix-gate.sh              # all platforms × all clients
#   scripts/bundled-clients-matrix-gate.sh ios android  # subset of platforms
#   WAWONA_MATRIX_CLIENTS="niri,weston" ./scripts/bundled-clients-matrix-gate.sh ios
#
# Env (apps / devices):
#   WAWONA_IOS_APP=/tmp/wawona-ios-gate.app
#   WAWONA_IPAD_APP=/tmp/wawona-ipad-gate.app
#   WAWONA_VISION_APP=/tmp/wawona-vision-gate.app
#   WAWONA_TVOS_APP=/tmp/wawona-tvos-gate.app
#   WAWONA_WATCH_APP=/tmp/wawona-watch-gate.app
#   WAWONA_MACOS_APP=...
#   WAWONA_ANDROID_APK=...
#   WAWONA_ANDROID_SERIAL=...
#   WAWONA_MATRIX_HOLD overrides per-client hold (seconds)
#   WAWONA_MATRIX_STRICT=1  treat SKIP (no app) as FAIL (CI)
#
# Exit: 0 all exercised cells PASS; 1 any FAIL; 2 only skips when STRICT.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/bundled-clients-catalog.sh
source "$ROOT/scripts/lib/bundled-clients-catalog.sh"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_ROOT="${WAWONA_MATRIX_OUT:-$ROOT/.agent-device/test-artifacts/bundled-clients-matrix/$STAMP}"
mkdir -p "$OUT_ROOT"
LOG="$OUT_ROOT/matrix.log"
SUMMARY_MD="$OUT_ROOT/SUMMARY.md"
SUMMARY_JSON="$OUT_ROOT/summary.json"
STRICT="${WAWONA_MATRIX_STRICT:-0}"

IOS_BUNDLE="${WAWONA_IOS_BUNDLE:-com.aspauldingcode.Wawona}"
WATCH_BUNDLE="${WAWONA_WATCH_BUNDLE:-com.aspauldingcode.Wawona.watch}"
ANDROID_PKG="${WAWONA_ANDROID_PACKAGE:-com.aspauldingcode.wawona}"

log() { printf '%s\n' "$*" | tee -a "$LOG"; }
logf() { printf "$@" | tee -a "$LOG"; }

# --- platform defaults -------------------------------------------------------

default_sim_for() {
  case "$1" in
    ios) echo "${WAWONA_IOS_SIM:-iPhone 17 Pro}" ;;
    ipados) echo "${WAWONA_IPAD_SIM:-iPad Pro 13-inch (M5)}" ;;
    visionos) echo "${WAWONA_VISION_SIM:-Apple Vision Pro}" ;;
    tvos) echo "${WAWONA_TVOS_SIM:-Apple TV 4K (3rd generation)}" ;;
    watchos) echo "${WAWONA_WATCH_SIM:-Apple Watch Series 11 (46mm)}" ;;
    *) echo "" ;;
  esac
}

default_app_for() {
  case "$1" in
    ios) echo "${WAWONA_IOS_APP:-/tmp/wawona-ios-gate.app}" ;;
    ipados) echo "${WAWONA_IPAD_APP:-/tmp/wawona-ipad-gate.app}" ;;
    visionos) echo "${WAWONA_VISION_APP:-/tmp/wawona-vision-gate.app}" ;;
    tvos) echo "${WAWONA_TVOS_APP:-/tmp/wawona-tvos-gate.app}" ;;
    watchos) echo "${WAWONA_WATCH_APP:-/tmp/wawona-watch-gate.app}" ;;
    macos) echo "${WAWONA_MACOS_APP:-}" ;;
    android) echo "${WAWONA_ANDROID_APK:-}" ;;
    *) echo "" ;;
  esac
}

bundle_for() {
  case "$1" in
    watchos) echo "$WATCH_BUNDLE" ;;
    android) echo "$ANDROID_PKG" ;;
    macos) echo "com.aspauldingcode.Wawona" ;;
    *) echo "$IOS_BUNDLE" ;;
  esac
}

resolve_udid() {
  local name="$1"
  # Already a UDID — do not awk-parse (Watch lines have (46mm) before the UDID,
  # so index(UDID) + print $2 wrongly yields "46mm").
  if [[ "$name" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  local udid
  # Prefer the last parenthesized UUID on the matching device line.
  udid="$(xcrun simctl list devices booted 2>/dev/null | awk -v n="$name" '
    index($0, n) {
      while (match($0, /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/)) {
        u = substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
      if (u != "") { print u; exit }
    }')"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl list devices available 2>/dev/null | awk -v n="$name" '
      index($0, n) && /(Shutdown|Booted)/ {
        while (match($0, /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/)) {
          u = substr($0, RSTART, RLENGTH)
          $0 = substr($0, RSTART + RLENGTH)
        }
        if (u != "") { print u; exit }
      }')"
  fi
  printf '%s\n' "$udid"
}

apple_pid() {
  local udid="$1" bundle="$2"
  # iOS 26 labels look like UIKitApplication:com.aspauldingcode.Wawona[…]
  local pid
  pid="$(xcrun simctl spawn "$udid" launchctl list 2>/dev/null \
    | awk -v b="$bundle" 'index($0, b) && $1 ~ /^[0-9]+$/ {print $1; exit}')"
  if [[ -n "$pid" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi
  # Host-visible Simulator process path contains the UDID + Wawona binary.
  pgrep -f "$udid.*Wawona.app/Wawona" 2>/dev/null | head -1
}

# --- lldb connect / disconnect (Apple) ---------------------------------------

run_lldb_batch() {
  local script="$1" out="$2"
  local timeout_sec="${WAWONA_MATRIX_LLDB_TIMEOUT_SEC:-45}"
  local debugger_pid watchdog_pid status=0

  xcrun lldb -b -s "$script" >"$out" 2>&1 &
  debugger_pid=$!
  (
    sleep "$timeout_sec"
    if kill -0 "$debugger_pid" 2>/dev/null; then
      printf 'MATRIX_LLDB_TIMEOUT after %ss\n' "$timeout_sec" >>"$out"
      kill -TERM "$debugger_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!

  wait "$debugger_pid" || status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$status"
}

lldb_connect() {
  local pid="$1" out="$2"
  local script
  script="$(mktemp)"
  # Release product apps have no debug symbols, so the ObjC expression parser
  # rejects a bare `WWNMachineSessionBridge` receiver with "use of undeclared
  # identifier" (the class token is unknown at compile time). Resolve the class
  # at runtime with NSClassFromString and send the real selectors to the Class
  # object — that compiles without headers and dumps `(BOOL) $N = YES`.
  # iOS 26 sim: `-l objc++` + @autoreleasepool returns empty; plain `-l objc` works.
  cat >"$script" <<EOF
process attach --pid $pid
expr -l objc -- Class store = NSClassFromString(@"WWNMachineProfileStore"); Class bridge = NSClassFromString(@"WWNMachineSessionBridge"); id profile = [[store loadProfiles] firstObject]; NSError *e = nil; BOOL ok = (store != nil && bridge != nil) ? [bridge connectProfile:profile error:&e] : (BOOL)0; if (!ok) { NSLog(@"WWN_MATRIX_CONNECT_ERR store=%@ bridge=%@ err=%@", store, bridge, e); } ok
detach
quit
EOF
  run_lldb_batch "$script" "$out" || true
  rm -f "$script"
  if grep -Eq '\(BOOL\) \$[0-9]+ = YES' "$out"; then
    return 0
  fi
  # Surface the real reason (undeclared class → symbol/link issue; err=… → runtime).
  {
    echo "--- connectProfile did not return YES; diagnostics ---"
    grep -iE 'error:|undeclared|WWN_MATRIX_CONNECT_ERR|nil' "$out" | head -8 || true
  } >>"$out"
  return 1
}

lldb_disconnect() {
  local pid="$1" out="$2"
  local script
  script="$(mktemp)"
  cat >"$script" <<EOF
process attach --pid $pid
expr -l objc -- Class store = NSClassFromString(@"WWNMachineProfileStore"); Class bridge = NSClassFromString(@"WWNMachineSessionBridge"); id profile = [[store loadProfiles] firstObject]; if (bridge != nil) { [bridge disconnectProfile:profile]; } (int)1
detach
quit
EOF
  run_lldb_batch "$script" "$out" || true
  rm -f "$script"
}

# --- agent-device Start (Apple simulators) -----------------------------------

# Drive the Machines "Start" button via agent-device — the same model Android
# and the leak-idle gate use. Replaces LLDB connectProfile, which the Release
# ObjC expression parser rejects. Returns 0 iff Start was pressed.
apple_start_client() {
  local platform="$1" sim="$2" bundle="$3" cell="$4"
  local ad_plat
  case "$platform" in
    ios | ipados) ad_plat=ios ;;
    visionos) ad_plat=visionos ;;
    tvos) ad_plat=tvos ;;
    watchos) ad_plat=watchos ;;
    *) ad_plat=ios ;;
  esac
  local sess="wawona-${platform}-matrix"
  local ad=(--platform "$ad_plat" --device "$sim" --session "$sess")

  # Retry the whole open→dismiss→Start sequence: the first `open` on a cold
  # session can still time out building the runner (SESSION_NOT_FOUND on the
  # follow-up snapshot). A second attempt reuses the now-warm runner.
  local attempt
  for attempt in 1 2; do
    agent-device open "$bundle" --relaunch "${ad[@]}" >"$cell/ad-open.log" 2>&1 || true
    agent-device wait 3000 "${ad[@]}" >/dev/null 2>&1 || true
    agent-device alert dismiss "${ad[@]}" >/dev/null 2>&1 || true

    # Welcome sheet (first launch) blocks the Machines Start button.
    if ! agent-device is visible 'id="wwn.machines.root"' "${ad[@]}" >/dev/null 2>&1; then
      agent-device press 'id="wwn.welcome.continue"' "${ad[@]}" >/dev/null 2>&1 || true
      agent-device press 'label="Continue"' "${ad[@]}" >/dev/null 2>&1 || true
      agent-device find Continue press --first "${ad[@]}" >/dev/null 2>&1 || true
      agent-device wait 1500 "${ad[@]}" >/dev/null 2>&1 || true
      agent-device alert dismiss "${ad[@]}" >/dev/null 2>&1 || true
    fi

    if agent-device press 'id="wwn.machines.start"' "${ad[@]}" >/dev/null 2>&1 \
      || agent-device press 'label="Start"' "${ad[@]}" >/dev/null 2>&1 \
      || agent-device find Start press --first "${ad[@]}" >/dev/null 2>&1; then
      agent-device wait 3000 "${ad[@]}" >/dev/null 2>&1 || true
      agent-device screenshot "$cell/running.png" "${ad[@]}" >/dev/null 2>&1 || true
      return 0
    fi
    [[ "$attempt" == 1 ]] && agent-device wait 2000 "${ad[@]}" >/dev/null 2>&1 || true
  done
  agent-device screenshot "$cell/start-fail.png" "${ad[@]}" >/dev/null 2>&1 || true
  agent-device snapshot -i --raw "${ad[@]}" >"$cell/start-fail-snapshot.txt" 2>&1 || true
  return 1
}

# --- console capture ---------------------------------------------------------

start_sim_log() {
  local udid="$1" bundle="$2" out="$3"
  # predicate: process + subsystem-ish; keep broad so client tags show up
  xcrun simctl spawn "$udid" log stream --level debug \
    --predicate "processImagePath CONTAINS \"Wawona\" OR eventMessage CONTAINS \"Wawona\" OR eventMessage CONTAINS \"WESTON\" OR eventMessage CONTAINS \"NIRI\" OR eventMessage CONTAINS \"niri\" OR eventMessage CONTAINS \"Launching\"" \
    >"$out" 2>&1 &
  echo $!
}

stop_log_pid() {
  local pid="$1"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

scan_fail() {
  local logf="$1"
  local pat
  while IFS= read -r pat; do
    [[ -z "$pat" ]] && continue
    if grep -Fqi -- "$pat" "$logf" 2>/dev/null; then
      echo "$pat"
      return 0
    fi
  done < <(bundled_client_fail_patterns)
  # also scan lldb / console artifacts in same dir
  return 1
}

# --- results -----------------------------------------------------------------

RESULTS_TSV="$OUT_ROOT/results.tsv"
echo -e "platform\tclient\tstatus\treason\thold_sec\tartifact_dir" >"$RESULTS_TSV"

record() {
  local platform="$1" client="$2" status="$3" reason="$4" hold="$5" adir="$6"
  echo -e "${platform}\t${client}\t${status}\t${reason}\t${hold}\t${adir}" >>"$RESULTS_TSV"
  log "RESULT ${platform}/${client}: ${status} — ${reason}"
}

# --- Apple cell --------------------------------------------------------------

run_apple_cell() {
  local platform="$1" client="$2"
  local app sim bundle udid cell hold skip
  app="$(default_app_for "$platform")"
  sim="$(default_sim_for "$platform")"
  bundle="$(bundle_for "$platform")"
  cell="$OUT_ROOT/$platform/$client"
  mkdir -p "$cell"
  hold="$(bundled_client_hold_sec "$client")"
  [[ -n "${WAWONA_MATRIX_HOLD:-}" ]] && hold="$WAWONA_MATRIX_HOLD"

  skip="$(bundled_client_skip_reason "$platform" "$client")"
  if [[ -n "$skip" ]]; then
    record "$platform" "$client" SKIP "$skip" "$hold" "$cell"
    return 0
  fi

  if [[ -z "$app" || ! -d "$app" ]]; then
    record "$platform" "$client" SKIP "no app at $app" "$hold" "$cell"
    return 0
  fi

  udid="$(resolve_udid "$sim")"
  if [[ -z "$udid" ]]; then
    record "$platform" "$client" SKIP "no simulator matching '$sim'" "$hold" "$cell"
    return 0
  fi

  log "== $platform / $client  sim=$sim udid=$udid hold=${hold}s =="

  xcrun simctl bootstatus "$udid" -b 2>/dev/null || xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1 || true

  # Writable stage (nix/gate apps may be read-only)
  local stage stagedir
  stagedir="$(mktemp -d)" || {
    record "$platform" "$client" FAIL "mktemp failed" "$hold" "$cell"
    return 1
  }
  stage="$stagedir/Wawona.app"
  if ! cp -R "$app" "$stage" >"$cell/stage.log" 2>&1; then
    record "$platform" "$client" FAIL "cp stage app failed" "$hold" "$cell"
    rm -rf "$stagedir"
    return 1
  fi
  chmod -R u+w "$stage" 2>/dev/null || true

  # Install first so the app container exists — `defaults write` via
  # simctl spawn fails when the bundle has never been installed on that sim.
  xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
  if ! xcrun simctl install "$udid" "$stage" >"$cell/install.log" 2>&1; then
    record "$platform" "$client" FAIL "simctl install failed" "$hold" "$cell"
    rm -rf "$stagedir"
    return 1
  fi
  rm -rf "$stagedir"

  WAWONA_IOS_BUNDLE="$bundle" \
    "$ROOT/scripts/agent-device-set-client-ios.sh" "$client" "$udid" \
    >"$cell/prefs.log" 2>&1 || {
      record "$platform" "$client" FAIL "prefs set failed" "$hold" "$cell"
      return 1
    }

  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true

  local logpid=""
  logpid="$(start_sim_log "$udid" "$bundle" "$cell/console.log")"
  echo "$logpid" >"$cell/logpid.txt"

  local use_lldb="${WAWONA_MATRIX_USE_LLDB:-0}"
  local pid=""

  if [[ "$use_lldb" == "1" ]]; then
    # Legacy local-debug path: simctl launch + LLDB connectProfile injection.
    local launch_out
    launch_out="$(xcrun simctl launch "$udid" "$bundle" 2>&1)" || true
    printf '%s\n' "$launch_out" >"$cell/launch.log"
    pid="$(printf '%s\n' "$launch_out" | sed -nE 's/.*: ([0-9]+)$/\1/p' | head -1)"
    sleep "${WAWONA_MATRIX_LAUNCH_SETTLE_SEC:-5}"
    if [[ -z "$pid" || "$pid" == "-" ]]; then pid="$(apple_pid "$udid" "$bundle")"; fi
    if [[ -z "$pid" || "$pid" == "-" ]]; then sleep 2; pid="$(apple_pid "$udid" "$bundle")"; fi
    if [[ -z "$pid" || "$pid" == "-" ]]; then
      stop_log_pid "$logpid"
      record "$platform" "$client" FAIL "app pid not found after launch" "$hold" "$cell"
      return 1
    fi
    echo "$pid" >"$cell/pid.txt"
    if ! lldb_connect "$pid" "$cell/lldb-connect.log"; then
      stop_log_pid "$logpid"
      if [[ "$platform" == "watchos" ]] && grep -qi 'error\|undeclared\|use of undeclared' "$cell/lldb-connect.log" 2>/dev/null; then
        record "$platform" "$client" FAIL "lldb connectProfile unavailable/error (see lldb-connect.log)" "$hold" "$cell"
      else
        record "$platform" "$client" FAIL "lldb connectProfile did not return ok=1" "$hold" "$cell"
      fi
      return 1
    fi
  elif [[ "${WAWONA_MATRIX_USE_AGENT_DEVICE:-0}" == "1" ]]; then
    # Opt-in path: drive the Machines "Start" button via agent-device. This needs
    # a built XCUITest runner (agent-device prepare ios-runner), which times out
    # on cold CI — hence it is no longer the default. Kept for local UI runs.
    if ! apple_start_client "$platform" "$sim" "$bundle" "$cell"; then
      stop_log_pid "$logpid"
      record "$platform" "$client" FAIL "agent-device Start not pressed (see start-fail-snapshot.txt)" "$hold" "$cell"
      xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
      return 1
    fi
    pid="$(apple_pid "$udid" "$bundle")"
    if [[ -z "$pid" || "$pid" == "-" ]]; then
      stop_log_pid "$logpid"
      record "$platform" "$client" FAIL "app pid not found after Start" "$hold" "$cell"
      xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
      return 1
    fi
    echo "$pid" >"$cell/pid.txt"
  else
    # Default path (parity with macOS WAWONA_AUTO_CLIENT): launch the app via
    # simctl with SIMCTL_CHILD_WAWONA_AUTO_CLIENT so it auto-starts the bundled
    # client itself. No XCUITest runner / agent-device UI automation is needed,
    # so there is nothing to build and time out on cold CI. WWNSceneDelegate's
    # -startAutoClientIfRequested reads WAWONA_AUTO_CLIENT and drives the client.
    local launch_out
    launch_out="$(SIMCTL_CHILD_WAWONA_AUTO_CLIENT="$client" \
      xcrun simctl launch "$udid" "$bundle" 2>&1)" || true
    printf '%s\n' "$launch_out" >"$cell/launch.log"
    pid="$(printf '%s\n' "$launch_out" | sed -nE 's/.*: ([0-9]+)$/\1/p' | head -1)"
    sleep "${WAWONA_MATRIX_LAUNCH_SETTLE_SEC:-5}"
    if [[ -z "$pid" || "$pid" == "-" ]]; then pid="$(apple_pid "$udid" "$bundle")"; fi
    if [[ -z "$pid" || "$pid" == "-" ]]; then sleep 2; pid="$(apple_pid "$udid" "$bundle")"; fi
    if [[ -z "$pid" || "$pid" == "-" ]]; then
      stop_log_pid "$logpid"
      record "$platform" "$client" FAIL "app pid not found after WAWONA_AUTO_CLIENT launch" "$hold" "$cell"
      xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
      return 1
    fi
    echo "$pid" >"$cell/pid.txt"
    xcrun simctl io "$udid" screenshot "$cell/running.png" >/dev/null 2>&1 || true
  fi

  local t=0 alive=1
  while [[ "$t" -lt "$hold" ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      # sim guest pid may not be visible to host kill -0; re-check via launchctl
      local p2
      p2="$(apple_pid "$udid" "$bundle")"
      if [[ -z "$p2" || "$p2" == "-" ]]; then
        alive=0
        break
      fi
      pid="$p2"
    fi
    sleep 2
    t=$((t + 2))
  done

  # Capture screenshot best-effort
  xcrun simctl io "$udid" screenshot "$cell/running.png" >/dev/null 2>&1 || true

  if [[ "$use_lldb" == "1" ]]; then
    lldb_disconnect "$pid" "$cell/lldb-disconnect.log" || true
  fi
  sleep 1
  stop_log_pid "$logpid"

  local failpat
  if failpat="$(scan_fail "$cell/console.log")"; then
    record "$platform" "$client" FAIL "console matched fail pattern: $failpat" "$hold" "$cell"
    return 1
  fi
  if [[ "$use_lldb" == "1" ]] && failpat="$(scan_fail "$cell/lldb-connect.log")"; then
    record "$platform" "$client" FAIL "lldb log matched fail pattern: $failpat" "$hold" "$cell"
    return 1
  fi
  if [[ "$alive" -eq 0 ]]; then
    record "$platform" "$client" FAIL "process died during ${hold}s hold" "$hold" "$cell"
    return 1
  fi

  # Final alive check
  local p3
  p3="$(apple_pid "$udid" "$bundle")"
  if [[ -z "$p3" || "$p3" == "-" ]]; then
    record "$platform" "$client" FAIL "process gone during hold" "$hold" "$cell"
    return 1
  fi

  record "$platform" "$client" PASS "alive ${hold}s after Start; no fail markers" "$hold" "$cell"
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  return 0
}

# --- Android cell ------------------------------------------------------------

run_android_cell() {
  local platform=android client="$1"
  local apk serial cell hold skip
  apk="$(default_app_for android)"
  serial="${WAWONA_ANDROID_SERIAL:-}"
  if [[ -z "$serial" ]]; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  cell="$OUT_ROOT/android/$client"
  mkdir -p "$cell"
  hold="$(bundled_client_hold_sec "$client")"
  [[ -n "${WAWONA_MATRIX_HOLD:-}" ]] && hold="$WAWONA_MATRIX_HOLD"

  skip="$(bundled_client_skip_reason android "$client")"
  if [[ -n "$skip" ]]; then
    record android "$client" SKIP "$skip" "$hold" "$cell"
    return 0
  fi
  if [[ -z "$serial" ]]; then
    record android "$client" SKIP "no adb device" "$hold" "$cell"
    return 0
  fi

  log "== android / $client  serial=$serial hold=${hold}s =="
  export ANDROID_SERIAL="$serial"

  if [[ -n "$apk" && -f "$apk" ]]; then
    adb -s "$serial" uninstall "$ANDROID_PKG" >/dev/null 2>&1 || true
    adb -s "$serial" install "$apk" >"$cell/install.log" 2>&1 || {
      record android "$client" FAIL "adb install failed" "$hold" "$cell"
      return 1
    }
  fi

  "$ROOT/scripts/agent-device-set-client-android.sh" "$client" "$serial" \
    >"$cell/prefs.log" 2>&1 || {
      record android "$client" FAIL "prefs set failed" "$hold" "$cell"
      return 1
    }

  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  adb -s "$serial" shell am force-stop "$ANDROID_PKG" >/dev/null 2>&1 || true

  if ! command -v agent-device >/dev/null; then
    record android "$client" FAIL "agent-device not on PATH" "$hold" "$cell"
    return 1
  fi

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"
  local sess="wawona-android-matrix-${client}"
  local ad_common=(--platform android --serial "$serial" --session "$sess")

  # Robust launch + Welcome + Start flow ported from agent-device-smoke.sh: the
  # Pixel launcher ANR / system dialogs and the Compose Welcome sheet otherwise
  # eat the Start tap and the cell fails with "Start control not pressed".
  dismiss_android_blockers() {
    adb -s "$serial" shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    agent-device alert dismiss "${ad_common[@]}" >/dev/null 2>&1 || true
    if agent-device is visible 'label="Wait"' "${ad_common[@]}" >/dev/null 2>&1; then
      agent-device press 'label="Wait"' "${ad_common[@]}" >/dev/null 2>&1 || true
    fi
    if agent-device is visible 'label="Close app"' "${ad_common[@]}" >/dev/null 2>&1; then
      agent-device press 'label="Close app"' "${ad_common[@]}" >/dev/null 2>&1 || true
    fi
  }
  android_press_id() {
    agent-device press "id=\"$1\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    android_uia_tap_id "$1" && return 0
    return 1
  }
  android_press_text() {
    android_uia_tap_text "$1" && return 0
    agent-device find "$1" press --first "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device press "label=\"$1\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device press "text=\"$1\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    return 1
  }
  android_machines_markers_present() {
    android_uia_has_id "wwn.machines.root" && return 0
    android_uia_has_text "Machine Configuration" && return 0
    android_uia_has_text "Default Machine" && return 0
    android_uia_has_text "All Machines" && return 0
    android_uia_has_text "Disconnected" && return 0
    return 1
  }
  android_dismiss_welcome() {
    android_machines_markers_present && return 0
    android_press_id "wwn.welcome.continue" || true
    android_press_text "Continue" || true
    agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
    android_tap_ref 540 1390 || true
    adb -s "$serial" shell input tap 540 1390 >/dev/null 2>&1 || true
    agent-device wait 2500 "${ad_common[@]}" || true
    dismiss_android_blockers
  }
  android_wait_machines_home() {
    local elapsed=0
    while (( elapsed < 30000 )); do
      android_machines_markers_present && return 0
      if (( elapsed >= 2500 )) && ! android_welcome_continue_visible; then
        return 0
      fi
      sleep 1
      elapsed=$((elapsed + 1000))
    done
    android_machines_markers_present && return 0
    android_welcome_continue_visible || return 0
    return 1
  }
  android_dismiss_modals() {
    if android_uia_has_text "Cancel" \
      || android_uia_has_text "Wawona Settings" \
      || android_uia_has_text "Add Machine Profile" \
      || android_uia_has_id "wwn.settings.root" \
      || android_uia_has_id "wwn.machines.editor"; then
      android_press_text "Cancel" || true
      android_press_id "wwn.settings.done" || android_press_text "Done" || true
      agent-device back "${ad_common[@]}" >/dev/null 2>&1 || true
      adb -s "$serial" shell input keyevent 4 >/dev/null 2>&1 || true
      agent-device wait 800 "${ad_common[@]}" || true
    fi
  }
  android_press_start() {
    android_press_id "wwn.machines.start" && return 0
    android_press_text "Start" && return 0
    android_tap_ref 227 1039 && return 0
    adb -s "$serial" shell input tap 227 1032 >/dev/null 2>&1 && return 0
    return 1
  }
  matrix_android_start_fail() {
    agent-device screenshot "$cell/start-fail.png" "${ad_common[@]}" || true
    android_uia_dump >"$cell/start-fail-ui.xml" 2>/dev/null || true
    agent-device snapshot -i --raw "${ad_common[@]}" >"$cell/start-fail-snapshot.txt" 2>&1 || true
    record android "$client" FAIL "Start control not pressed (see start-fail-ui.xml)" "$hold" "$cell"
    agent-device close "${ad_common[@]}" || true
  }

  agent-device open "$ANDROID_PKG" --relaunch "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 4000 "${ad_common[@]}" || true
  dismiss_android_blockers
  android_dismiss_welcome
  agent-device wait 2000 "${ad_common[@]}" || true
  dismiss_android_blockers
  if ! android_wait_machines_home; then
    matrix_android_start_fail
    return 1
  fi
  android_dismiss_modals
  dismiss_android_blockers
  if ! android_press_start; then
    matrix_android_start_fail
    return 1
  fi
  agent-device wait 6000 "${ad_common[@]}" || true
  dismiss_android_blockers

  adb -s "$serial" logcat -d >"$cell/logcat-pre.txt" 2>&1 || true
  local t=0
  while [[ "$t" -lt "$hold" ]]; do
    if ! adb -s "$serial" shell pidof "$ANDROID_PKG" >/dev/null 2>&1; then
      adb -s "$serial" logcat -d >"$cell/logcat.txt" 2>&1 || true
      record android "$client" FAIL "process died during hold" "$hold" "$cell"
      return 1
    fi
    sleep 2
    t=$((t + 2))
  done
  adb -s "$serial" logcat -d >"$cell/logcat.txt" 2>&1 || true
  agent-device screenshot "$cell/running.png" "${ad_common[@]}" || true

  local failpat
  if failpat="$(scan_fail "$cell/logcat.txt")"; then
    record android "$client" FAIL "logcat matched: $failpat" "$hold" "$cell"
    agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 || true
    agent-device close "${ad_common[@]}" || true
    return 1
  fi

  agent-device press 'id="wwn.machines.stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || agent-device press 'label="Stop"' "${ad_common[@]}" >/dev/null 2>&1 \
    || true
  agent-device close "${ad_common[@]}" || true
  record android "$client" PASS "alive ${hold}s after Start; no fail markers" "$hold" "$cell"
  return 0
}

# --- macOS cell --------------------------------------------------------------

run_macos_cell() {
  local client="$1"
  local app cell hold
  app="$(default_app_for macos)"
  cell="$OUT_ROOT/macos/$client"
  mkdir -p "$cell"
  hold="$(bundled_client_hold_sec "$client")"
  [[ -n "${WAWONA_MATRIX_HOLD:-}" ]] && hold="$WAWONA_MATRIX_HOLD"

  local skip
  skip="$(bundled_client_skip_reason macos "$client")"
  if [[ -n "$skip" ]]; then
    record macos "$client" SKIP "$skip" "$hold" "$cell"
    return 0
  fi

  if [[ -z "$app" || ! -d "$app" ]]; then
    for cand in "$ROOT/result-macos/Wawona.app" "$ROOT/dist/Wawona.app" "$ROOT/product-macos-app/Wawona.app"; do
      [[ -d "$cand" ]] && app="$cand" && break
    done
  fi
  if [[ -z "$app" || ! -d "$app" ]]; then
    record macos "$client" SKIP "no Wawona.app (set WAWONA_MACOS_APP)" "$hold" "$cell"
    return 0
  fi

  log "== macos / $client  app=$app hold=${hold}s =="
  pkill -x Wawona 2>/dev/null || true
  sleep 1

  # Prefs via defaults (host)
  local prefs_key payload
  prefs_key="$(bundled_client_prefs_key "$client")"
  payload="$(CLIENT="$client" PREFS_KEY="$prefs_key" python3 - <<'PY'
import json, os
c=os.environ["CLIENT"]; k=os.environ["PREFS_KEY"]
print(json.dumps([{
  "id": f"e2e-{c}-default",
  "name": "Default Machine",
  "type": "native",
  "sshHost":"","sshUser":"","sshPort":22,"sshPassword":"",
  "remoteCommand":"","launchers":[],"favorite":False,
  "runtimeOverrides":{"bundledAppID":c},
  "settingsOverrides":{"NativeClientId":c, k: True},
  "nativeLauncher":c,
}], separators=(",",":")))
PY
)"
  defaults write com.aspauldingcode.Wawona "wawona.machineProfiles.v1" -string "$payload"
  defaults write com.aspauldingcode.Wawona "wawona.activeMachineId.v1" -string "e2e-${client}-default"
  defaults write com.aspauldingcode.Wawona "$prefs_key" -bool YES
  defaults write com.aspauldingcode.Wawona hasSeenWelcome -bool YES

  # `open` on a GHA-unpacked artifact fails (Gatekeeper / LaunchServices 111) and
  # pgrep -x then finds nothing. Mirror niri-smoke-macos.sh: strip quarantine and
  # exec the binary directly so we own the pid. The GHA artifact unzip also drops
  # the +x bit (→ "Permission denied" on execve), so restore it first; the nix
  # code signature is intact and valid, so no ad-hoc re-sign is needed.
  xattr -cr "$app" 2>/dev/null || true
  chmod +x "$app/Contents/MacOS/Wawona" 2>/dev/null || true
  find "$app/Contents/MacOS" -type f -exec chmod +x {} + 2>/dev/null || true
  find "$app/Contents/Resources/bin" -type f -exec chmod +x {} + 2>/dev/null || true

  # Start the client the same way the Machines "Start" button does. The macOS
  # matrix runner has no agent-device and osascript AX clicks need TCC, so drive
  # the app's supported WAWONA_AUTO_CLIENT hook (main.m → launchBundledClientWithId).
  # LLDB connectProfile is retired here: on Release product builds the ObjC expr
  # parser rejects the injected message sends ("unknown return type" / "no known
  # method"), so every macOS cell went red on the harness, not the client. Keep
  # the old LLDB path behind WAWONA_MATRIX_USE_LLDB=1 for local debugging only.
  local use_lldb="${WAWONA_MATRIX_USE_LLDB:-0}"
  if [[ "$use_lldb" == "1" ]]; then
    "$app/Contents/MacOS/Wawona" >"$cell/app.log" 2>&1 &
  else
    WAWONA_AUTO_CLIENT="$client" "$app/Contents/MacOS/Wawona" >"$cell/app.log" 2>&1 &
  fi
  local pid=$!
  # Settle: wait for the process to be alive; fall back to name/path lookup if the
  # launcher re-execs into a differently-named helper.
  local settle=0
  while [[ "$settle" -lt "${WAWONA_MATRIX_LAUNCH_SETTLE_SEC:-8}" ]]; do
    kill -0 "$pid" 2>/dev/null && break
    sleep 1
    settle=$((settle + 1))
  done
  if ! kill -0 "$pid" 2>/dev/null; then
    pid="$(pgrep -x Wawona | head -1 || true)"
  fi
  if [[ -z "$pid" ]]; then
    pid="$(pgrep -f 'Wawona.app/Contents/MacOS/Wawona' | head -1 || true)"
  fi
  if [[ -z "$pid" ]]; then
    record macos "$client" FAIL "Wawona pid not found (see app.log)" "$hold" "$cell"
    return 1
  fi
  echo "$pid" >"$cell/pid.txt"

  if [[ "$use_lldb" == "1" ]]; then
    if ! lldb_connect "$pid" "$cell/lldb-connect.log"; then
      record macos "$client" FAIL "lldb connectProfile did not return ok=1" "$hold" "$cell"
      pkill -x Wawona 2>/dev/null || true
      return 1
    fi
  fi

  # Hold: the host must stay alive (a GPU client like gbm-es2-demo can crash it).
  local t=0
  while [[ "$t" -lt "$hold" ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      record macos "$client" FAIL "host process died during hold (crash?)" "$hold" "$cell"
      return 1
    fi
    sleep 2
    t=$((t + 2))
  done

  # Scan the real app.log (previously only the lldb log was scanned, so a real
  # client crash could PASS while the host stayed up).
  local failpat
  if failpat="$(scan_fail "$cell/app.log")"; then
    record macos "$client" FAIL "app.log matched fail pattern: $failpat" "$hold" "$cell"
    pkill -x Wawona 2>/dev/null || true
    return 1
  fi
  if [[ "$use_lldb" == "1" ]] && scan_fail "$cell/lldb-connect.log" >/dev/null; then
    record macos "$client" FAIL "fail marker in lldb log" "$hold" "$cell"
    pkill -x Wawona 2>/dev/null || true
    return 1
  fi
  # The client itself must not have exited/crashed during the hold even though the
  # host survived. NSTask clients log "<id> terminated (status N …)"; in-process
  # iland clients log "<id> exit rc=N". A nonzero exit here catches e.g.
  # weston-image quitting on missing-image usage.
  if grep -Eq "${client} (terminated \(status [1-9]| exit rc=[1-9]|exit code: [1-9])" \
      "$cell/app.log" 2>/dev/null; then
    local deathline
    deathline="$(grep -E "${client} (terminated \(status|exit rc=|exit code:)" "$cell/app.log" | tail -1)"
    record macos "$client" FAIL "client did not stay up: ${deathline}" "$hold" "$cell"
    pkill -x Wawona 2>/dev/null || true
    return 1
  fi
  record macos "$client" PASS "alive ${hold}s after WAWONA_AUTO_CLIENT start; no fail markers" "$hold" "$cell"
  pkill -x Wawona 2>/dev/null || true
  return 0
}

# --- platform dispatch -------------------------------------------------------

run_platform() {
  local platform="$1"
  local clients_csv="${WAWONA_MATRIX_CLIENTS:-}"
  local clients=()
  if [[ -n "$clients_csv" ]]; then
    IFS=',' read -r -a clients <<<"$clients_csv"
  else
    while IFS= read -r c; do
      clients+=("$c")
    done < <(bundled_clients_all)
  fi

  log "======== PLATFORM $platform (${#clients[@]} clients) ========"

  # Apple simulators: build/prepare the XCUITest runner ONCE up front ONLY when
  # the opt-in agent-device Start path is selected. The default path launches via
  # simctl + WAWONA_AUTO_CLIENT and needs no runner, so preparing it just burns
  # ~4 min timing out on cold CI (which is how weston-terminal used to fail).
  case "$platform" in
    ios | ipados | visionos)
      if [[ "${WAWONA_MATRIX_USE_AGENT_DEVICE:-0}" == "1" ]] \
        && command -v agent-device >/dev/null 2>&1; then
        local ad_plat="$platform" psim
        [[ "$platform" == "ipados" ]] && ad_plat=ios
        psim="$(default_sim_for "$platform")"
        log "prepare ios-runner (platform=$ad_plat device='$psim', one-time)"
        agent-device prepare ios-runner --platform "$ad_plat" --device "$psim" \
          >"$OUT_ROOT/${platform}-prepare-runner.log" 2>&1 ||
          log "WARN: prepare ios-runner failed (continuing; per-cell open retries)"
      fi
      ;;
  esac

  local c
  for c in "${clients[@]}"; do
    case "$platform" in
      ios|ipados|visionos|tvos|watchos) run_apple_cell "$platform" "$c" || true ;;
      android) run_android_cell "$c" || true ;;
      macos) run_macos_cell "$c" || true ;;
      *) log "WARN: unknown platform $platform"; return 1 ;;
    esac
  done
}

# --- summary -----------------------------------------------------------------

write_summary() {
  python3 - "$RESULTS_TSV" "$SUMMARY_MD" "$SUMMARY_JSON" <<'PY'
import csv, json, sys, collections
from pathlib import Path
tsv, md_path, json_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
rows = list(csv.DictReader(tsv.open(), delimiter="\t"))
counts = collections.Counter(r["status"] for r in rows)
fails = [r for r in rows if r["status"] == "FAIL"]
passes = [r for r in rows if r["status"] == "PASS"]
skips = [r for r in rows if r["status"] == "SKIP"]

lines = [
  "# Watch: bundled clients summary",
  "",
  f"- PASS: {counts.get('PASS', 0)}",
  f"- FAIL: {counts.get('FAIL', 0)}",
  f"- SKIP: {counts.get('SKIP', 0)}",
  "",
]
if fails:
  lines += ["## FAIL cells", ""]
  lines.append("| Platform | Client | Reason |")
  lines.append("|----------|--------|--------|")
  for r in fails:
    lines.append(f"| {r['platform']} | {r['client']} | {r['reason']} |")
  lines.append("")
  lines.append("MATRIX_FAIL platforms/clients: " + ", ".join(f"{r['platform']}/{r['client']}" for r in fails))
  lines.append("")
else:
  lines.append("MATRIX_FAIL platforms/clients: (none)")
  lines.append("")

lines += ["## All results", ""]
lines.append("| Platform | Client | Status | Reason |")
lines.append("|----------|--------|--------|--------|")
for r in rows:
  lines.append(f"| {r['platform']} | {r['client']} | {r['status']} | {r['reason']} |")

md_path.write_text("\n".join(lines) + "\n")
payload = {
  "counts": dict(counts),
  "fail": [f"{r['platform']}/{r['client']}" for r in fails],
  "pass": [f"{r['platform']}/{r['client']}" for r in passes],
  "skip": [f"{r['platform']}/{r['client']}" for r in skips],
  "rows": rows,
}
json_path.write_text(json.dumps(payload, indent=2) + "\n")
print(md_path.read_text())
PY
}

# --- main --------------------------------------------------------------------

chmod +x "$ROOT/scripts/agent-device-set-client-ios.sh" \
  "$ROOT/scripts/agent-device-set-client-android.sh" 2>/dev/null || true

ALL_PLATFORMS=(ios ipados visionos tvos watchos android macos)
PLATFORMS=()
if [[ "$#" -gt 0 ]]; then
  PLATFORMS=("$@")
else
  PLATFORMS=("${ALL_PLATFORMS[@]}")
fi

CLIENT_DESC="${WAWONA_MATRIX_CLIENTS:-}"
if [[ -z "$CLIENT_DESC" ]]; then
  CLIENT_DESC="ALL ($(bundled_clients_all | wc -l | tr -d ' ') clients)"
fi
log "Watch: bundled clients gate — $STAMP"
log "Output: $OUT_ROOT"
log "Platforms: ${PLATFORMS[*]}"
log "Clients: $CLIENT_DESC"

for p in "${PLATFORMS[@]}"; do
  run_platform "$p"
done

write_summary | tee -a "$LOG"

FAIL_N="$(awk -F'\t' 'NR>1 && $3=="FAIL"{c++} END{print c+0}' "$RESULTS_TSV")"
PASS_N="$(awk -F'\t' 'NR>1 && $3=="PASS"{c++} END{print c+0}' "$RESULTS_TSV")"
SKIP_N="$(awk -F'\t' 'NR>1 && $3=="SKIP"{c++} END{print c+0}' "$RESULTS_TSV")"

log "MATRIX_PASS count=$PASS_N"
log "MATRIX_SKIP count=$SKIP_N"
if [[ "$FAIL_N" -gt 0 ]]; then
  FAILS="$(awk -F'\t' 'NR>1 && $3=="FAIL"{printf "%s/%s,", $1, $2}' "$RESULTS_TSV" | sed 's/,$//')"
  log "MATRIX_FAIL count=$FAIL_N cells=$FAILS"
  exit 1
fi
if [[ "$STRICT" == "1" && "$PASS_N" -eq 0 ]]; then
  log "MATRIX_FAIL: STRICT=1 and zero PASS cells"
  exit 2
fi
log "MATRIX_OK"
exit 0
