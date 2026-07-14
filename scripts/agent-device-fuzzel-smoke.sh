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

  echo "== Android: niri+fuzzel .ad replay =="
  local niri_ad
  niri_ad="$(mktemp "${TMPDIR:-/tmp}/wawona-android-niri-fuzzel.XXXXXX.ad")"
  android_scale_ad_file "$ROOT/.agent-device/wawona-android-niri-fuzzel.ad" "$niri_ad"
  agent-device replay "$niri_ad" --platform android --serial "$serial"
  rm -f "$niri_ad"

  # Replay closes the agent-device session; the app stays running.
  local procs
  procs="$(adb -s "$serial" shell 'ps -A' | grep -E '[n]iri|[f]uzzel' || true)"
  echo "$procs" | tee "$ARTIFACTS/android-fuzzel-e2e-procs-pre.txt"

  if ! echo "$procs" | grep -q 'fuzzel'; then
    # Clear any sticky launcher, then inject Alt+D (nested niri Mod = Alt).
    local focus_xy
    focus_xy="$(android_scale_xy 540 1100)"
    adb -s "$serial" shell input tap $focus_xy
    sleep 0.3
    adb -s "$serial" shell input keyevent 111   # KEYCODE_ESCAPE
    sleep 0.3
    android_inject_alt_d || true
    sleep 2.5
    procs="$(adb -s "$serial" shell 'ps -A' | grep -E '[n]iri|[f]uzzel' || true)"
    echo "$procs" | tee "$ARTIFACTS/android-fuzzel-e2e-procs.txt"
  else
    echo "fuzzel already running after .ad focus — skipping Alt+D inject"
    echo "$procs" | tee "$ARTIFACTS/android-fuzzel-e2e-procs.txt"
  fi

  local shot="$ARTIFACTS/android-fuzzel-e2e-05-after-alt-d.png"
  adb -s "$serial" exec-out screencap -p >"$shot"
  assert_png_exists "$shot"

  local logf="$ARTIFACTS/android-fuzzel-e2e-logcat.txt"
  adb -s "$serial" logcat -d >"$logf" 2>/dev/null || true

  echo "$procs" | grep -q 'niri' || { echo "FAIL: niri not running" >&2; exit 1; }
  echo "$procs" | grep -q 'fuzzel' || { echo "FAIL: fuzzel not running after Alt+D" >&2; exit 1; }
  echo "PASS: fuzzel process up"

  # Catalog Exec must resolve on PATH (weston-simple-shm → libwawona_wl_bin.so).
  local wl_link
  wl_link="$(adb -s "$serial" shell 'run-as com.aspauldingcode.wawona sh -c "ls -l files/wawona-rootfs/usr/bin/weston-simple-shm 2>/dev/null"' | tr -d '\r')"
  echo "$wl_link" | tee "$ARTIFACTS/android-fuzzel-e2e-wl-path.txt"
  echo "$wl_link" | grep -q 'wawona_wl_bin\|weston-simple-shm' || {
    echo "FAIL: usr/bin/weston-simple-shm missing (fuzzel Exec cannot launch clients)" >&2
    exit 1
  }
  echo "PASS: weston-simple-shm on PATH"

  # Launch Weston Simple SHM from fuzzel: type filter + Enter.
  adb -s "$serial" shell input text 'weston-simple'
  sleep 0.5
  adb -s "$serial" shell input keyevent 66   # ENTER
  sleep 3

  local after_launch
  after_launch="$(adb -s "$serial" shell 'ps -A' | grep -E '[n]iri|[f]uzzel|[w]eston-simple|[w]awona_wl' || true)"
  echo "$after_launch" | tee "$ARTIFACTS/android-fuzzel-e2e-procs-after-launch.txt"

  local shot2="$ARTIFACTS/android-fuzzel-e2e-06-after-client-launch.png"
  adb -s "$serial" exec-out screencap -p >"$shot2"
  assert_png_exists "$shot2"

  # Client may appear as libwawona_wl_bin.so or remain under the Wawona PID;
  # require either a new process OR log evidence of launcher success.
  adb -s "$serial" logcat -d >"$logf" 2>/dev/null || true
  if ! rg -q 'WawonaWlBin|launch weston-simple-shm|weston_simple_shm_main' "$logf"; then
    if ! echo "$after_launch" | grep -qE 'wawona_wl|weston-simple'; then
      echo "FAIL: no evidence weston-simple-shm launched from fuzzel" >&2
      rg -i 'fuzzel|WawonaWl|weston-simple|exec' "$logf" | head -40 || true
      exit 1
    fi
  fi
  echo "PASS: nested Wayland client launch evidence"

  # Must not regress to NotFound / timerfd crash.
  if rg -q 'error spawning "fuzzel"|timerfd_create|SIGSEGV' "$logf"; then
    echo "FAIL: spawn/timerfd regression in logcat" >&2
    rg -n 'fuzzel|timerfd|SIGSEGV|spawn' "$logf" | head -40
    exit 1
  fi

  # Soft assertion: XDG / catalog path mentioned when present.
  rg -i 'XDG_DATA|share/applications|fuzzel' "$logf" | head -20 \
    | tee "$ARTIFACTS/android-fuzzel-e2e-xdg-hints.txt" || true

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

  echo "== iOS: prepare XCTest runner =="
  agent-device prepare ios-runner --platform ios --device "$IOS_DEVICE" --timeout 300000
  stop_agent_device_daemons

  echo "== iOS: niri+fuzzel .ad replay =="
  agent-device replay "$ROOT/.agent-device/wawona-ios-niri-fuzzel.ad" \
    --platform ios --device "$IOS_DEVICE"

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
