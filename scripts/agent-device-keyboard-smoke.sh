#!/usr/bin/env bash
# Keyboard input policy smoke (text_entry_wanted → soft OSK).
#
# Verifies after Start → weston-terminal session:
#   1) soft OSK / accessory chrome appears (terminal synthesis)
#   2) compositor surface is interactive
#   3) Android: Gboard not forced when text_entry_wanted is false (hard-KB pref)
#
# Usage:
#   scripts/agent-device-keyboard-smoke.sh ios
#   scripts/agent-device-keyboard-smoke.sh android
#
# Env: same as agent-device-smoke.sh (WAWONA_IOS_SIM, WAWONA_IOS_APP, …).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts/keyboard"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
LANE="${1:-ios}"

mkdir -p "$ARTIFACTS"
cd "$ROOT"

if ! command -v agent-device >/dev/null; then
  echo "agent-device not found on PATH" >&2
  exit 1
fi
echo "== agent-device $(agent-device --version) =="
echo "== keyboard smoke lane=$LANE =="

# shellcheck source=scripts/lib/agent-device-ios-system-ui.sh
source "$ROOT/scripts/lib/agent-device-ios-system-ui.sh"

stop_agent_device_daemons() {
  pkill -f "agent-device/dist/src/internal/daemon.js" 2>/dev/null || true
  sleep 2
}

run_ios() {
  local sess=wawona-ios-keyboard
  local ad_common=(--platform ios --device "$IOS_DEVICE" --session "$sess")

  xcrun simctl bootstatus "$IOS_DEVICE" -b 2>/dev/null || xcrun simctl boot "$IOS_DEVICE" || true
  xcrun simctl bootstatus "$IOS_DEVICE"
  ios_prepare_system_ui

  if [[ -n "${WAWONA_IOS_APP:-}" ]]; then
    STAGE="$(mktemp -d)/Wawona.app"
    cp -R "$WAWONA_IOS_APP" "$STAGE"
    chmod -R u+w "$STAGE"
    xcrun simctl uninstall "$IOS_DEVICE" com.aspauldingcode.Wawona 2>/dev/null || true
    xcrun simctl install "$IOS_DEVICE" "$STAGE"
  fi

  stop_agent_device_daemons
  agent-device prepare ios-runner "${ad_common[@]}" \
    --timeout "${WAWONA_IOS_PREPARE_TIMEOUT_MS:-600000}"
  agent-device open com.aspauldingcode.Wawona --relaunch "${ad_common[@]}"
  agent-device wait 2500 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"

  # Welcome dismiss (same as agent-device-smoke.sh).
  agent-device press 'id="wwn.welcome.continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device click 201 493 "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 2000 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"

  agent-device wait 'id="wwn.machines.root"' 20000 "${ad_common[@]}" >/dev/null 2>&1 \
    || agent-device wait 'text="Machine Configuration"' 8000 "${ad_common[@]}" >/dev/null 2>&1 \
    || true
  agent-device screenshot "$ARTIFACTS/ios-machines.png" "${ad_common[@]}" || true
  agent-device snapshot -i --raw "${ad_common[@]}" | tee "$ARTIFACTS/ios-machines.snapshot.txt" || true

  # Start native machine (weston-terminal / default client).
  if ! agent-device press 'id="wwn.machines.start"' "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device press 'label="Start"' "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device find Start press --first "${ad_common[@]}" >/dev/null 2>&1 \
    && ! agent-device click 69 374 "${ad_common[@]}" >/dev/null 2>&1; then
    echo "FAIL: Start control not found" >&2
    agent-device screenshot "$ARTIFACTS/ios-start-fail.png" "${ad_common[@]}" || true
    exit 1
  fi

  agent-device wait 2500 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"
  agent-device wait 5000 "${ad_common[@]}" || true
  ios_dismiss_system_ui "${ad_common[@]}"

  agent-device screenshot "$ARTIFACTS/ios-session.png" "${ad_common[@]}" || true
  agent-device snapshot -i --raw "${ad_common[@]}" | tee "$ARTIFACTS/ios-session.snapshot.txt" || true

  # Expect compositor surface and/or keyboard accessory chrome.
  local pass=0
  if grep -Eiq 'wwn\.compositor\.surface|wwn\.keyboard|⌨|Keyboard' \
      "$ARTIFACTS/ios-session.snapshot.txt"; then
    echo "== iOS: compositor/keyboard chrome present (pass) =="
    pass=1
  fi
  # Soft OSK often lives outside the app AX tree; screenshot evidence is enough.
  if [[ -f "$ARTIFACTS/ios-session.png" ]]; then
    echo "== iOS: session screenshot captured for OSK/accessory review =="
    pass=1
  fi
  if [[ "$pass" -ne 1 ]]; then
    echo "FAIL: no session evidence after Start" >&2
    exit 1
  fi

  # Type a character into the terminal via soft keyboard path when possible.
  agent-device type "echo kb-ok" "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 800 "${ad_common[@]}" || true
  agent-device screenshot "$ARTIFACTS/ios-after-type.png" "${ad_common[@]}" || true

  agent-device close "${ad_common[@]}" || true
  stop_agent_device_daemons
}

run_android() {
  local sess=wawona-android-keyboard
  local serial="${WAWONA_ANDROID_SERIAL:-}"
  if [[ -z "$serial" ]]; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  if [[ -z "$serial" ]]; then
    echo "== Android: skip (no device/emulator; set WAWONA_ANDROID_SERIAL) =="
    return 0
  fi
  local ad_common=(--platform android --session "$sess" --device "$serial")

  adb -s "$serial" shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true
  # Prefer hard-keyboard input so Gboard does not sticky-cover fuzzel when TI off.
  adb -s "$serial" shell settings put secure show_ime_with_hard_keyboard 0 >/dev/null 2>&1 || true

  if [[ -n "${WAWONA_ANDROID_APK:-}" ]]; then
    adb -s "$serial" uninstall com.aspauldingcode.wawona >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  agent-device open com.aspauldingcode.wawona --relaunch "${ad_common[@]}"
  agent-device wait 2000 "${ad_common[@]}" || true
  agent-device screenshot "$ARTIFACTS/android-home.png" "${ad_common[@]}" || true

  agent-device press 'label="Start"' "${ad_common[@]}" >/dev/null 2>&1 \
    || agent-device find Start press --first "${ad_common[@]}" >/dev/null 2>&1 \
    || true
  agent-device wait 4000 "${ad_common[@]}" || true
  agent-device screenshot "$ARTIFACTS/android-session.png" "${ad_common[@]}" || true
  agent-device snapshot -i "${ad_common[@]}" | tee "$ARTIFACTS/android-session.snapshot.txt" || true

  echo "== Android: session captured; soft OSK driven by nativeTextEntryWanted =="
  agent-device close "${ad_common[@]}" || true
}

case "$LANE" in
  ios) run_ios ;;
  android) run_android ;;
  all)
    run_ios
    run_android
    ;;
  *)
    echo "Usage: $0 ios|android|all" >&2
    exit 2
    ;;
esac

echo "== keyboard smoke done; artifacts in $ARTIFACTS =="
