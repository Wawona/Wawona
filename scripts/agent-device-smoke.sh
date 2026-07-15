#!/usr/bin/env bash
# Wawona deterministic GUI smoke tests via agent-device (iOS simulator +
# Android emulator). Zero-AI: every flow is a recorded .ad/batch replay, so
# this is safe for CI runners and burns no model credits.
#
# Usage:
#   scripts/agent-device-smoke.sh ios       # iOS simulator lane
#   scripts/agent-device-smoke.sh android   # Android device/emulator lane
#   scripts/agent-device-smoke.sh fuzzel    # nested niri + fuzzel (issue #78)
#   scripts/agent-device-smoke.sh all       # ios + android + fuzzel (default)
#
# Env:
#   WAWONA_IOS_SIM         simulator name   (default: iPhone 17 Pro)
#   WAWONA_IOS_APP         path to Wawona.app to (re)install before testing
#   WAWONA_ANDROID_SERIAL  adb serial       (default: first "device" entry)
#   WAWONA_ANDROID_APK     path to Wawona.apk to (re)install before testing
#   WAWONA_MACOS_APP       path to macOS Wawona.app for fuzzel lane
#   WAWONA_SKIP_FUZZEL=1   skip nested niri+fuzzel lanes
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
LANE="${1:-all}"

mkdir -p "$ARTIFACTS"
cd "$ROOT"

if ! command -v agent-device >/dev/null; then
  echo "agent-device not found on PATH (nix profile or: npm install -g agent-device)" >&2
  exit 1
fi
echo "== agent-device $(agent-device --version) =="

# agent-device daemons keep a per-simulator runner lease after the CLI
# returns; a lease held by the `prepare` daemon blocks the daemons that
# `replay` spawns ("already owned by another agent-device daemon").
stop_agent_device_daemons() {
  pkill -f "agent-device/dist/src/internal/daemon.js" 2>/dev/null || true
  sleep 2
}

run_ios() {
  local sess=wawona-ios-smoke
  local ad_common=(--platform ios --device "$IOS_DEVICE" --session "$sess")

  echo "== iOS: boot simulator '$IOS_DEVICE' =="
  xcrun simctl bootstatus "$IOS_DEVICE" -b || xcrun simctl boot "$IOS_DEVICE" || true
  xcrun simctl bootstatus "$IOS_DEVICE"

  if [[ -n "${WAWONA_IOS_APP:-}" ]]; then
    echo "== iOS: install $WAWONA_IOS_APP =="
    # Nix-store bundles are read-only; stage a writable copy for simctl.
    STAGE="$(mktemp -d)/Wawona.app"
    cp -R "$WAWONA_IOS_APP" "$STAGE"
    chmod -R u+w "$STAGE"
    xcrun simctl uninstall "$IOS_DEVICE" com.aspauldingcode.Wawona 2>/dev/null || true
    xcrun simctl install "$IOS_DEVICE" "$STAGE"
  fi

  echo "== iOS: prepare XCTest runner (one-time per machine) =="
  # CI cold runners often exceed 5m for first XCTest runner connect.
  agent-device prepare ios-runner --platform ios --device "$IOS_DEVICE" \
    --timeout "${WAWONA_IOS_PREPARE_TIMEOUT_MS:-600000}"

  # Stop the prepare daemon so the smoke session can take the runner lease
  # (see `agent-device help workflow`).
  stop_agent_device_daemons

  echo "== iOS: single-session smoke (stable wwn.* ids) =="
  # Serial CLI keeps Welcome optional without failing the batch on missing Continue.
  agent-device open com.aspauldingcode.Wawona --relaunch "${ad_common[@]}"
  agent-device wait 2500 "${ad_common[@]}"
  agent-device snapshot -i "${ad_common[@]}" || true
  agent-device screenshot "$ARTIFACTS/ios-first-screen.png" "${ad_common[@]}"
  if agent-device is visible 'id="wwn.welcome.continue"' "${ad_common[@]}" >/dev/null 2>&1; then
    agent-device press 'id="wwn.welcome.continue"' "${ad_common[@]}"
    agent-device wait 1500 "${ad_common[@]}"
  elif agent-device is visible 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1; then
    agent-device press 'label="Continue"' "${ad_common[@]}"
    agent-device wait 1500 "${ad_common[@]}"
  fi
  agent-device wait 'id="wwn.machines.root"' 20000 "${ad_common[@]}" \
    || agent-device wait text "Machine Configuration" 20000 "${ad_common[@]}"
  agent-device is visible 'id="wwn.machines.root"' "${ad_common[@]}" \
    || agent-device is visible 'label="Machine Configuration"' "${ad_common[@]}"
  agent-device is visible 'id="wwn.machines.start"' "${ad_common[@]}" \
    || agent-device is visible 'label="Start"' "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/ios-machines-root.png" "${ad_common[@]}"
  agent-device press 'id="wwn.machines.settings"' "${ad_common[@]}" \
    || agent-device press 'label="Settings"' "${ad_common[@]}"
  agent-device wait 'id="wwn.settings.display"' 15000 "${ad_common[@]}" \
    || agent-device wait text Display 15000 "${ad_common[@]}"
  agent-device is visible 'id="wwn.settings.display"' "${ad_common[@]}" \
    || agent-device is visible 'label="Display"' "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/ios-settings-display.png" "${ad_common[@]}"
  agent-device press 'id="wwn.settings.done"' "${ad_common[@]}" \
    || agent-device press 'label="Done"' "${ad_common[@]}"
  agent-device wait 'id="wwn.machines.root"' 15000 "${ad_common[@]}"
  agent-device press 'id="wwn.machines.add"' "${ad_common[@]}" \
    || agent-device press 'label="Add Machine"' "${ad_common[@]}"
  agent-device wait 1200 "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/ios-add-machine-sheet.png" "${ad_common[@]}"
  # Dismiss add sheet (swipe/back) then Start a machine.
  agent-device press 'id="wwn.machines.root"' "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device back "${ad_common[@]}" >/dev/null 2>&1 || true
  agent-device wait 800 "${ad_common[@]}"
  agent-device press 'id="wwn.machines.start"' "${ad_common[@]}" \
    || agent-device press 'label="Start"' "${ad_common[@]}" \
    || {
      echo "FAIL: Start control not found (id=wwn.machines.start)" >&2
      agent-device snapshot -i --raw "${ad_common[@]}" || true
      exit 1
    }
  agent-device wait 10000 "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/ios-weston-session.png" "${ad_common[@]}"
  agent-device close "${ad_common[@]}"
}

run_android() {
  local serial="${WAWONA_ANDROID_SERIAL:-}"
  if [[ -z "$serial" ]]; then
    serial="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  fi
  if [[ -z "$serial" ]]; then
    echo "== Android: skip (no device/emulator; set WAWONA_ANDROID_SERIAL) =="
    return 0
  fi
  export ANDROID_SERIAL="$serial"
  echo "== Android: serial=$serial =="
  # Suppress immersive-mode "Got it" coach mark (blocks compositor input).
  adb -s "$serial" shell settings put secure immersive_mode_confirmations confirmed >/dev/null 2>&1 || true

  if [[ -n "${WAWONA_ANDROID_APK:-}" ]]; then
    echo "== Android: install $WAWONA_ANDROID_APK =="
    # Fresh install: dev builds are signed with rotating debug keys, so an
    # upgrade install can fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.
    adb -s "$serial" uninstall com.aspauldingcode.wawona >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"

  echo "== Android: single-session smoke (stable wwn.* ids) =="
  local sess=wawona-android-smoke
  local ad_common=(--platform android --serial "$serial" --session "$sess")
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
  # Prefer id= (Compose testTagsAsResourceId). Fall back to label / uia / coords.
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
    local attempt
    for attempt in 1 2 3 4 5; do
      # Only treat Welcome as gone when Machines is positively visible.
      # (uiautomator dump failure must NOT skip Continue — that left CI stuck
      # on the welcome screen with identical first/machines screenshots.)
      if android_uia_has_id "wwn.machines.root" || android_uia_has_text "Machine Configuration"; then
        return 0
      fi
      android_press_id "wwn.welcome.continue" || true
      android_press_text "Continue" || true
      agent-device press 'label="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
      agent-device press 'text="Continue"' "${ad_common[@]}" >/dev/null 2>&1 || true
      # Centered Continue on 1080x2400 / 1080x2424 welcome (pixel_7 CI).
      android_tap_ref 540 1404 || true
      android_tap_ref 540 1450 || true
      adb -s "$serial" shell input tap 540 1404 >/dev/null 2>&1 || true
      agent-device wait 2500 "${ad_common[@]}"
      dismiss_android_blockers
    done
  }
  android_press_start() {
    # Match pre-a11y gate: a successful tap is enough here. Session chrome is
    # observed after the following wait; requiring Start to disappear made CI
    # fail when Compose still showed Start during CONNECTING / slow launch.
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
    # Last resort: id bounds tap (agent-device press is a no-op on Compose).
    android_uia_tap_id "wwn.machines.start" && return 0
    return 1
  }
  android_wait_machines_home() {
    # Prefer UiAutomator: agent-device id=/text waits often miss Compose nodes on CI.
    android_uia_wait id "wwn.machines.root" 25000 && return 0
    android_uia_wait text "Machine Configuration" 5000 && return 0
    agent-device wait 'id="wwn.machines.root"' 5000 "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device wait 'text="Machine Configuration"' 5000 "${ad_common[@]}" >/dev/null 2>&1 && return 0
    return 1
  }

  agent-device open com.aspauldingcode.wawona --relaunch "${ad_common[@]}"
  agent-device wait 4000 "${ad_common[@]}"
  dismiss_android_blockers
  agent-device snapshot -i "${ad_common[@]}" || true
  agent-device screenshot "$ARTIFACTS/android-first-screen.png" "${ad_common[@]}"
  android_dismiss_welcome
  dismiss_android_blockers
  if ! android_wait_machines_home; then
    echo "FAIL: machines home not reached after Welcome" >&2
    agent-device screenshot "$ARTIFACTS/android-machines-root.png" "${ad_common[@]}" || true
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    adb -s "$serial" exec-out cat /sdcard/wawona-ui.xml 2>/dev/null | tr '>' '\n' | grep -E 'text=|content-desc=|resource-id=' | head -60 || true
    exit 1
  fi
  agent-device screenshot "$ARTIFACTS/android-machines-root.png" "${ad_common[@]}"
  if android_uia_has_text "Continue"; then
    echo "FAIL: still on Welcome after Continue" >&2
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    exit 1
  fi
  android_press_text "Got it" || true
  agent-device wait 500 "${ad_common[@]}"

  android_dismiss_modals() {
    # Settings / Add Machine sheets leave a Material3 scrim that eats Start taps
    # while the Machines card (and text="Start") stays visible underneath.
    local i
    for i in 1 2 3 4 5; do
      if android_uia_has_text "Cancel" \
        || android_uia_has_text "Wawona Settings" \
        || android_uia_has_text "Add Machine Profile" \
        || android_uia_has_id "wwn.settings.root" \
        || android_uia_has_id "wwn.machines.editor"; then
        android_press_text "Cancel" || true
        android_press_id "wwn.settings.done" || android_press_text "Done" || true
        agent-device back "${ad_common[@]}" >/dev/null 2>&1 || true
        adb -s "$serial" shell input keyevent 4 >/dev/null 2>&1 || true
        agent-device wait 800 "${ad_common[@]}"
        continue
      fi
      return 0
    done
  }

  # Match fuzzel lane: Start while Machines is unobstructed. Opening Settings/Add
  # before Start left a modal scrim that swallowed taps (Start still visible).
  android_dismiss_modals
  dismiss_android_blockers
  android_press_start || {
    echo "FAIL: could not press Start (id=wwn.machines.start)" >&2
    agent-device screenshot "$ARTIFACTS/android-start-fail.png" "${ad_common[@]}" || true
    android_uia_dump >"$ARTIFACTS/android-start-fail-ui.xml" 2>/dev/null || true
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    grep -E 'text=|content-desc=|resource-id=' "$ARTIFACTS/android-start-fail-ui.xml" 2>/dev/null | head -80 || true
    adb -s "$serial" logcat -d -t 80 2>/dev/null | grep -Ei 'wawona|native runtime|Failed to launch|CONNECT' | tail -40 || true
    exit 1
  }
  agent-device wait 10000 "${ad_common[@]}"
  dismiss_android_blockers
  android_press_text "Got it" || android_tap_ref 900 720 || true
  agent-device wait 500 "${ad_common[@]}"
  agent-device screenshot "$ARTIFACTS/android-weston-session.png" "${ad_common[@]}"
  agent-device close "${ad_common[@]}"
}

run_fuzzel() {
  if [[ "${WAWONA_SKIP_FUZZEL:-}" == "1" ]]; then
    echo "== fuzzel: skipped (WAWONA_SKIP_FUZZEL=1) =="
    return 0
  fi
  chmod +x "$ROOT/scripts/agent-device-fuzzel-smoke.sh"
  # Platform-filtered entry: CI jobs pass android-fuzzel / ios-fuzzel.
  "$ROOT/scripts/agent-device-fuzzel-smoke.sh" "${WAWONA_FUZZEL_LANE:-fuzzel}"
}

case "$LANE" in
  ios) run_ios ;;
  android) run_android ;;
  fuzzel|android-fuzzel|ios-fuzzel|macos-fuzzel)
    chmod +x "$ROOT/scripts/agent-device-fuzzel-smoke.sh"
    "$ROOT/scripts/agent-device-fuzzel-smoke.sh" "$LANE"
    ;;
  all)
    run_ios
    run_android
    run_fuzzel
    ;;
  *)
    echo "usage: $0 [ios|android|fuzzel|android-fuzzel|ios-fuzzel|macos-fuzzel|all]" >&2
    exit 2
    ;;
esac

echo "== done; artifacts in $ARTIFACTS =="
