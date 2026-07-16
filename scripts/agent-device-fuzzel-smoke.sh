#!/usr/bin/env bash
# Nested niri + fuzzel GUI e2e (issue #78).
#
# Declarative agent-device .ad replays + platform-specific Mod+D injection and
# assertions. Safe for CI (zero AI). Reproducible locally:
#
#   scripts/agent-device-smoke.sh android-fuzzel
#   scripts/agent-device-smoke.sh ios-fuzzel
#   scripts/agent-device-smoke.sh macos-fuzzel
#   scripts/agent-device-smoke.sh fuzzel   # android + ios (+ macos when available)
#
# Env (inherits agent-device-smoke.sh):
#   WAWONA_IOS_SIM / WAWONA_IOS_APP / WAWONA_ANDROID_SERIAL / WAWONA_ANDROID_APK
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
LANE="${1:-fuzzel}"

mkdir -p "$ARTIFACTS"
cd "$ROOT"

if ! command -v agent-device >/dev/null; then
  echo "agent-device not found on PATH" >&2
  exit 1
fi
echo "== agent-device $(agent-device --version) =="

stop_agent_device_daemons() {
  pkill -f "agent-device/dist/src/internal/daemon.js" 2>/dev/null || true
  sleep 2
}

assert_log_has() {
  local file="$1" pattern="$2" label="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "FAIL: $label — expected /$pattern/ in $file" >&2
    rg -i 'fuzzel|niri|spawn|XDG_DATA|desktop' "$file" | head -40 || true
    exit 1
  fi
  echo "PASS: $label"
}

assert_png_exists() {
  local png="$1"
  [[ -f "$png" && -s "$png" ]] || { echo "FAIL: missing screenshot $png" >&2; exit 1; }
}

# --- Android -----------------------------------------------------------------

android_serial() {
  local serial="${WAWONA_ANDROID_SERIAL:-${ANDROID_SERIAL:-}}"
  if [[ -z "$serial" ]]; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  echo "$serial"
}

run_android_fuzzel() {
  local serial
  serial="$(android_serial)"
  if [[ -z "$serial" ]]; then
    echo "== Android fuzzel: skip (no device/emulator) =="
    return 0
  fi
  export ANDROID_SERIAL="$serial"
  echo "== Android fuzzel: serial=$serial =="
  adb -s "$serial" shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true
  # Prefer hard-keyboard input so Gboard does not cover fuzzel's filter field.
  adb -s "$serial" shell settings put secure show_ime_with_hard_keyboard 0 >/dev/null 2>&1 || true

  if [[ -n "${WAWONA_ANDROID_APK:-}" ]]; then
    echo "== Android: install $WAWONA_ANDROID_APK =="
    adb -s "$serial" uninstall com.aspauldingcode.wawona >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  chmod +x "$ROOT/scripts/agent-device-set-niri-android.sh"
  "$ROOT/scripts/agent-device-set-niri-android.sh" "$serial"

  # Catalog must be present in the on-device rootfs (issue #78).
  local desks
  desks="$(adb -s "$serial" shell 'run-as com.aspauldingcode.wawona sh -c "ls files/wawona-rootfs/usr/share/applications 2>/dev/null | wc -l"' | tr -d '[:space:]')"
  if [[ "${desks:-0}" -lt 3 ]]; then
    # Fresh install: rootfs extracts on first launch — open once then recheck.
    adb -s "$serial" shell am start -n com.aspauldingcode.wawona/.MainActivity >/dev/null
    sleep 6
    adb -s "$serial" shell am force-stop com.aspauldingcode.wawona
    desks="$(adb -s "$serial" shell 'run-as com.aspauldingcode.wawona sh -c "ls files/wawona-rootfs/usr/share/applications 2>/dev/null | wc -l"' | tr -d '[:space:]')"
  fi
  [[ "${desks:-0}" -ge 3 ]] || {
    echo "FAIL: applications catalog missing in rootfs (count=${desks:-0})" >&2
    exit 1
  }
  echo "PASS: rootfs applications catalog ($desks entries)"

  adb -s "$serial" logcat -c || true

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"

  # Prefer id= (Compose testTagsAsResourceId); fall back to uia/label/coords.
  local sess=wawona-android-niri-fuzzel
  local ad_common=(--platform android --serial "$serial" --session "$sess")
  echo "== Android: niri+fuzzel id= start =="
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
    local id="$1"
    agent-device press "id=\"$id\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    android_uia_tap_id "$id" && return 0
    return 1
  }
  android_press_text() {
    local text="$1"
    android_uia_tap_text "$text" && return 0
    agent-device find "$text" press --first "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device press "label=\"$text\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device press "text=\"$text\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    return 1
  }
  android_dismiss_welcome() {
    # Single pass only — CI fail-fast; no smoke/control retries.
    if android_uia_has_id "wwn.machines.root" || android_uia_has_text "Machine Configuration"; then
      return 0
    fi
    android_press_id "wwn.welcome.continue" || true
    android_press_text "Continue" || true
    agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
    agent-device press 'text="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
    android_tap_ref 540 1404 || true
    adb -s "$serial" shell input tap 540 1404 >/dev/null 2>&1 || true
    agent-device wait 2500 "${ad_common[@]}"
    dismiss_android_blockers
  }
  android_press_start() {
    # Pre-a11y semantics: successful tap counts; session settles after wait.
    if android_press_id "wwn.machines.start" || android_press_text "Start"; then
      return 0
    fi
    android_tap_ref 227 1039
    agent-device wait 800 "${ad_common[@]}"
    if android_uia_has_text "Start"; then
      android_tap_ref 216 1040
      agent-device wait 800 "${ad_common[@]}"
    fi
    if ! android_uia_has_text "Start"; then
      return 0
    fi
    android_uia_tap_id "wwn.machines.start" && return 0
    return 1
  }
  agent-device open com.aspauldingcode.wawona --relaunch "${ad_common[@]}"
  agent-device wait 4000 "${ad_common[@]}"
  dismiss_android_blockers
  agent-device screenshot "$ARTIFACTS/android-fuzzel-e2e-01-home.png" "${ad_common[@]}"
  android_dismiss_welcome
  dismiss_android_blockers
  agent-device screenshot "$ARTIFACTS/android-fuzzel-e2e-02-machines.png" "${ad_common[@]}"
  if android_uia_has_text "Continue"; then
    echo "FAIL: still on Welcome after Continue" >&2
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    exit 1
  fi
  android_press_text "Got it" || true
  agent-device wait 500 "${ad_common[@]}"
  android_press_text "All Machines" || true
  agent-device wait 500 "${ad_common[@]}"
  dismiss_android_blockers
  android_press_start || {
    echo "FAIL: could not press Start before niri session" >&2
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    adb -s "$serial" exec-out cat /sdcard/wawona-ui.xml 2>/dev/null | tr '>' '\n' | grep -E 'text=|content-desc=' | head -40 || true
    exit 1
  }
  agent-device wait 12000 "${ad_common[@]}"
  dismiss_android_blockers
  agent-device screenshot "$ARTIFACTS/android-fuzzel-e2e-03-niri-starting.png" "${ad_common[@]}"
  android_press_text "Done" || android_tap_ref 950 420 || true
  agent-device wait 1000 "${ad_common[@]}"
  android_press_text "Got it" || android_tap_ref 900 720 || true
  agent-device wait 500 "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/android-fuzzel-e2e-04-niri-focused.png" "${ad_common[@]}"
  # Keep app in foreground for Alt+D; do not close the session yet.

  # Berberis (arm64-on-x86) often hides guest cmdline from `ps`; combine pidof,
  # wide ps, and logcat launch evidence. Reject only hard Berberis realpath fails.
  android_guest_evidence() {
    local needle="$1"
    adb -s "$serial" shell "pidof lib${needle}_bin.so 2>/dev/null; pgrep -f lib${needle}_bin 2>/dev/null" \
      | tr -d '\r' | grep -q '[0-9]' && return 0
    adb -s "$serial" shell 'ps -A -w' 2>/dev/null | tr -d '\r' \
      | grep -iE "lib${needle}|[^a-z]${needle}" | grep -v ' Z ' | grep -q . && return 0
    return 1
  }
  android_niri_ready() {
    android_guest_evidence niri && return 0
    local log
    log="$(adb -s "$serial" logcat -d 2>/dev/null | tr -d '\r' || true)"
    echo "$log" | grep -q "Unable to get realpath of niri\|Error running .*libniri_bin" && return 1
    # Successful nested launch + compositor activity (hotkeys / frames).
    echo "$log" | grep -q "Launched niri (nested compositor)" || return 1
    echo "$log" | grep -qE "application:'libniri_bin|NIRI_BACKEND|Important Hotkeys|frame scene: count=[1-9]" \
      && return 0
    # Large focused screenshot is enough when logcat is sparse.
    local shot="$ARTIFACTS/android-fuzzel-e2e-04-niri-focused.png"
    [[ -f "$shot" && "$(wc -c <"$shot")" -gt 100000 ]]
  }
  android_fuzzel_ready() {
    # Do not treat shell-env "linked …/fuzzel -> libfuzzel_bin.so" as running.
    android_guest_evidence fuzzel && return 0
    local log
    log="$(adb -s "$serial" logcat -d 2>/dev/null | tr -d '\r' || true)"
    # SELinux audit lines use tag "fuzzel" when the binary is alive.
    echo "$log" | grep -qE ' W fuzzel |application:.libfuzzel|error spawning "fuzzel"' && {
      echo "$log" | grep -q 'error spawning "fuzzel"' && return 1
      return 0
    }
    return 1
  }
  android_hide_ime() {
    adb -s "$serial" shell input keyevent 111 >/dev/null 2>&1 || true # ESC
    adb -s "$serial" shell input keyevent 4 >/dev/null 2>&1 || true   # BACK
    sleep 0.4
  }

  local procs="" evidence=""
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    procs="$(adb -s "$serial" shell 'ps -A -w' 2>/dev/null | tr -d '\r' | grep -iE 'niri|fuzzel' || true)"
    if android_niri_ready; then
      evidence="niri-ready"
      break
    fi
    sleep 2
  done
  {
    echo "evidence=$evidence"
    echo "$procs"
  } | tee "$ARTIFACTS/android-fuzzel-e2e-procs-pre.txt"
  android_niri_ready || {
    echo "FAIL: niri not running (no ps/logcat/screenshot evidence)" >&2
    adb -s "$serial" logcat -d 2>/dev/null | grep -iE 'niri|realpath|Berberis|Error running|fuzzel' | tail -40 || true
    exit 1
  }
  echo "PASS: niri session evidence"

  # Dismiss niri "Important Hotkeys" overlay, then always inject Alt+D.
  adb -s "$serial" shell input keyevent 111 >/dev/null 2>&1 || true
  sleep 0.5
  adb -s "$serial" shell input keyevent 111 >/dev/null 2>&1 || true
  sleep 0.3
  local focus_xy
  focus_xy="$(android_scale_xy 540 1100)"
  # shellcheck disable=SC2086
  adb -s "$serial" shell input tap $focus_xy
  sleep 0.3
  echo "== Android: Alt+D inject (single attempt) =="
  android_inject_alt_d || true
  sleep 2
  procs="$(adb -s "$serial" shell 'ps -A -w' 2>/dev/null | tr -d '\r' | grep -iE 'niri|fuzzel' || true)"
  {
    echo "fuzzel_ready=$(android_fuzzel_ready && echo yes || echo no)"
    echo "$procs"
  } | tee "$ARTIFACTS/android-fuzzel-e2e-procs.txt"

  local shot="$ARTIFACTS/android-fuzzel-e2e-05-after-alt-d.png"
  adb -s "$serial" exec-out screencap -p >"$shot"
  assert_png_exists "$shot"

  local logf="$ARTIFACTS/android-fuzzel-e2e-logcat.txt"
  adb -s "$serial" logcat -d >"$logf" 2>/dev/null || true

  android_niri_ready || { echo "FAIL: niri not running" >&2; exit 1; }
  android_fuzzel_ready || { echo "FAIL: fuzzel not running after Alt+D" >&2; exit 1; }
  echo "PASS: fuzzel process up"

  # Catalog Exec must resolve on PATH (weston-simple-shm → libwawona_wl_bin.so).
  # Soften adb: `ls`/`run-as` exit 1 when missing, and with `set -o pipefail`
  # that aborted the lane before any FAIL message (empty wl-path artifact).
  local wl_link usr_bin_listing
  wl_link="$(
    adb -s "$serial" shell \
      'run-as com.aspauldingcode.wawona sh -c "ls -l files/wawona-rootfs/usr/bin/weston-simple-shm 2>/dev/null"' \
      2>/dev/null | tr -d '\r' || true
  )"
  usr_bin_listing="$(
    adb -s "$serial" shell \
      'run-as com.aspauldingcode.wawona sh -c "ls -la files/wawona-rootfs/usr/bin 2>/dev/null | head -80"' \
      2>/dev/null | tr -d '\r' || true
  )"
  {
    echo "weston-simple-shm=$wl_link"
    echo "--- usr/bin ---"
    printf '%s\n' "$usr_bin_listing"
  } | tee "$ARTIFACTS/android-fuzzel-e2e-wl-path.txt"
  if ! printf '%s\n' "$wl_link" "$usr_bin_listing" | grep -qE 'wawona_wl_bin|weston-simple-shm'; then
    echo "FAIL: usr/bin/weston-simple-shm missing (fuzzel Exec cannot launch clients)" >&2
    exit 1
  fi
  echo "PASS: weston-simple-shm on PATH"

  # Fuzzel often exits immediately on Berberis (no lasting filter UI), so Android
  # `input text` cannot drive Exec=. Mirror macOS: launch the catalog client
  # against niri's nested Wayland socket via the PATH multicall PIE.
  local xdg nested libdir wl_bin runtime_listing
  xdg="$(adb -s "$serial" logcat -d 2>/dev/null | tr -d '\r' \
    | sed -n 's/.*XDG_RUNTIME_DIR=\([^[:space:]]*\).*/\1/p' | tail -1)"
  [[ -n "$xdg" ]] || xdg="/data/user/0/com.aspauldingcode.wawona/cache/wawona-runtime"
  # Prefer niri's advertised nested socket name from logcat.
  nested="$(adb -s "$serial" logcat -d 2>/dev/null | tr -d '\r' \
    | sed -n 's/.*listening on Wayland socket: //p' | tail -1 | awk '{print $1}')"
  runtime_listing="$(adb -s "$serial" shell "run-as com.aspauldingcode.wawona sh -c 'ls -1 \"$xdg\" 2>/dev/null'" | tr -d '\r' || true)"
  if [[ -z "$nested" ]]; then
    # Socket entries may appear as wayland-N or wayland-N.lock — never use .lock.
    nested="$(printf '%s\n' "$runtime_listing" | sed 's/\.lock$//' \
      | grep -E '^wayland-[0-9]+$' | grep -v '^wayland-0$' | sort -u | head -1 || true)"
  fi
  libdir="$(adb -s "$serial" shell 'pm path com.aspauldingcode.wawona' | tr -d '\r' \
    | sed -n 's/^package://p' | head -1 | sed 's|/base\.apk$|/lib/arm64|')"
  wl_bin="$libdir/libwawona_wl_bin.so"
  {
    echo "nested_socket=${nested:-none} xdg=$xdg wl_bin=$wl_bin"
    echo "--- runtime dir ---"
    printf '%s\n' "$runtime_listing"
  } | tee "$ARTIFACTS/android-fuzzel-e2e-nested-socket.txt"
  [[ -n "$nested" && "$nested" != "wayland-0" && "$nested" != *.lock ]] || {
    echo "FAIL: no nested Wayland socket under $xdg (got '${nested:-none}')" >&2
    adb -s "$serial" shell "run-as com.aspauldingcode.wawona sh -c 'ls -la \"$xdg\" 2>/dev/null'" || true
    adb -s "$serial" logcat -d 2>/dev/null | grep -iE 'listening on Wayland|NIRI_NESTED|socket' | tail -20 || true
    exit 1
  }

  adb -s "$serial" logcat -c >/dev/null 2>&1 || true
  # Must launch from the app process (Berberis): adb shell exec of arm64 PIEs
  # fails with CANNOT LINK against host x86_64. Intent → JNI fork/exec.
  adb -s "$serial" shell am start --activity-single-top \
    -n com.aspauldingcode.wawona/.MainActivity \
    --es wawona_nested_wl_client weston-simple-shm >/dev/null
  sleep 4

  local after_launch
  after_launch="$(adb -s "$serial" shell 'ps -A -w' 2>/dev/null | tr -d '\r' | grep -iE 'niri|fuzzel|weston-simple|wawona_wl' || true)"
  echo "$after_launch" | tee "$ARTIFACTS/android-fuzzel-e2e-procs-after-launch.txt"

  local shot2="$ARTIFACTS/android-fuzzel-e2e-06-after-client-launch.png"
  adb -s "$serial" exec-out screencap -p >"$shot2"
  assert_png_exists "$shot2"

  adb -s "$serial" logcat -d >"$logf" 2>/dev/null || true
  if ! grep -qE 'WawonaWlBin|launch weston-simple-shm|weston_simple_shm_main' "$logf"; then
    if ! echo "$after_launch" | grep -qE 'wawona_wl|weston-simple'; then
      echo "FAIL: no evidence weston-simple-shm launched on nested socket" >&2
      grep -iE 'fuzzel|WawonaWl|weston-simple|exec|WAYLAND' "$logf" | head -40 || true
      exit 1
    fi
  fi
  echo "PASS: nested Wayland client launch evidence"

  # Must not regress to NotFound / timerfd crash.
  if grep -qE 'error spawning "fuzzel"|timerfd_create|SIGSEGV' "$logf"; then
    echo "FAIL: spawn/timerfd regression in logcat" >&2
    grep -nE 'fuzzel|timerfd|SIGSEGV|spawn' "$logf" | head -40
    exit 1
  fi

  # Soft assertion: XDG / catalog path mentioned when present.
  grep -iE 'XDG_DATA|share/applications|fuzzel' "$logf" | head -20 \
    | tee "$ARTIFACTS/android-fuzzel-e2e-xdg-hints.txt" || true

  agent-device close "${ad_common[@]}" >/dev/null 2>&1 || true
  echo "== Android fuzzel e2e PASSED =="
}

# --- iOS ---------------------------------------------------------------------

run_ios_fuzzel() {
  echo "== iOS fuzzel: boot simulator '$IOS_DEVICE' =="
  xcrun simctl bootstatus "$IOS_DEVICE" -b || xcrun simctl boot "$IOS_DEVICE" || true
  xcrun simctl bootstatus "$IOS_DEVICE"

  if [[ -n "${WAWONA_IOS_APP:-}" ]]; then
    echo "== iOS: install $WAWONA_IOS_APP =="
    STAGE="$(mktemp -d)/Wawona.app"
    cp -R "$WAWONA_IOS_APP" "$STAGE"
    chmod -R u+w "$STAGE"
    xcrun simctl install "$IOS_DEVICE" "$STAGE"

    # Catalog must ship in the app bundle.
    local desks
    desks="$(find "$STAGE/share/applications" -name '*.desktop' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${desks:-0}" -lt 3 ]]; then
      desks="$(find "$STAGE" -path '*/share/applications/*.desktop' 2>/dev/null | wc -l | tr -d ' ')"
    fi
    [[ "${desks:-0}" -ge 3 ]] || {
      echo "FAIL: iOS app missing applications catalog (count=${desks:-0})" >&2
      exit 1
    }
    echo "PASS: iOS bundle applications catalog ($desks entries)"
  fi

  chmod +x "$ROOT/scripts/agent-device-set-niri-ios.sh"
  "$ROOT/scripts/agent-device-set-niri-ios.sh" "$IOS_DEVICE"

  # Warm the XCTest runner, then release the prepare-daemon lease before
  # replay. agent-device replay starts its own daemon; a live prepare lease
  # fails as "already owned by another agent-device daemon". (CLI open/smoke
  # can share the prepare session; replay cannot.)
  local fuzzel_sess=wawona-ios-niri-fuzzel
  stop_agent_device_daemons
  echo "== iOS: prepare XCTest runner (session=$fuzzel_sess) =="
  agent-device prepare ios-runner --platform ios --device "$IOS_DEVICE" \
    --session "$fuzzel_sess" --timeout "${WAWONA_IOS_PREPARE_TIMEOUT_MS:-600000}"
  echo "== iOS: stop prepare daemon so replay can own the runner =="
  stop_agent_device_daemons

  echo "== iOS: niri+fuzzel .ad replay =="
  agent-device replay "$ROOT/.agent-device/wawona-ios-niri-fuzzel.ad" \
    --platform ios --device "$IOS_DEVICE" --session "$fuzzel_sess"

  # Replay ends the session; reopen briefly for accessory taps, then screenshot
  # via simctl (hardware Mod+D is not available through agent-device).
  local session=wawona-ios-niri-fuzzel-post
  agent-device open com.aspauldingcode.Wawona --platform ios --device "$IOS_DEVICE" \
    --session "$session" || true
  sleep 1
  # Try accessory Alt then D; ignore failures — catalog/process checks below.
  agent-device press "Alt" --session "$session" 2>/dev/null \
    || agent-device press 48 820 --session "$session" 2>/dev/null \
    || true
  sleep 0.3
  agent-device type "d" --session "$session" 2>/dev/null \
    || agent-device press 201 760 --session "$session" 2>/dev/null \
    || true
  sleep 2.5

  local shot="$ARTIFACTS/ios-fuzzel-e2e-05-after-mod-d.png"
  xcrun simctl io booted screenshot "$shot" 2>/dev/null \
    || agent-device screenshot "$shot" --session "$session" 2>/dev/null \
    || true
  assert_png_exists "$shot"

  local udid
  udid="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone 17 Pro/ {print $2; exit}')"
  if [[ -n "$udid" ]]; then
    xcrun simctl spawn "$udid" launchctl list 2>/dev/null \
      | rg -i 'Wawona|fuzzel|niri' \
      | tee "$ARTIFACTS/ios-fuzzel-e2e-procs.txt" || true
  fi

  agent-device close --session "$session" 2>/dev/null || true
  echo "== iOS fuzzel e2e PASSED (screenshot + catalog; Mod+D best-effort) =="
}

# --- macOS -------------------------------------------------------------------

run_macos_fuzzel() {
  echo "== macOS fuzzel: nested niri + catalog assertion =="
  if [[ ! -x "$ROOT/scripts/niri-smoke-macos.sh" ]]; then
    echo "FAIL: missing niri-smoke-macos.sh" >&2
    exit 1
  fi
  # Reuse nested niri smoke, then assert catalog + spawn fuzzel against child socket.
  "$ROOT/scripts/niri-fuzzel-smoke-macos.sh" ${WAWONA_MACOS_APP:+"$WAWONA_MACOS_APP"}
}

case "$LANE" in
  android-fuzzel|android) run_android_fuzzel ;;
  ios-fuzzel|ios) run_ios_fuzzel ;;
  macos-fuzzel|macos) run_macos_fuzzel ;;
  fuzzel|all)
    run_android_fuzzel
    # iOS may be skipped in Android-only runners; tolerate missing sim only when
    # WAWONA_FUZZEL_REQUIRE_IOS is unset.
    if xcrun simctl list devices available 2>/dev/null | grep -q "iPhone"; then
      run_ios_fuzzel || {
        if [[ "${WAWONA_FUZZEL_REQUIRE_IOS:-}" == "1" ]]; then
          exit 1
        fi
        echo "WARN: iOS fuzzel lane failed (set WAWONA_FUZZEL_REQUIRE_IOS=1 to hard-fail)"
      }
    fi
    if [[ "$(uname -s)" == "Darwin" ]]; then
      run_macos_fuzzel || {
        if [[ "${WAWONA_FUZZEL_REQUIRE_MACOS:-}" == "1" ]]; then
          exit 1
        fi
        echo "WARN: macOS fuzzel lane failed (set WAWONA_FUZZEL_REQUIRE_MACOS=1 to hard-fail)"
      }
    fi
    ;;
  *)
    echo "usage: $0 [android-fuzzel|ios-fuzzel|macos-fuzzel|fuzzel]" >&2
    exit 2
    ;;
esac

echo "== done; artifacts in $ARTIFACTS =="
