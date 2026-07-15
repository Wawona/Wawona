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
  echo "== iOS: boot simulator '$IOS_DEVICE' =="
  xcrun simctl bootstatus "$IOS_DEVICE" -b || xcrun simctl boot "$IOS_DEVICE" || true
  xcrun simctl bootstatus "$IOS_DEVICE"

  if [[ -n "${WAWONA_IOS_APP:-}" ]]; then
    echo "== iOS: install $WAWONA_IOS_APP =="
    # Nix-store bundles are read-only; stage a writable copy for simctl.
    STAGE="$(mktemp -d)/Wawona.app"
    cp -R "$WAWONA_IOS_APP" "$STAGE"
    chmod -R u+w "$STAGE"
    xcrun simctl install "$IOS_DEVICE" "$STAGE"
  fi

  echo "== iOS: prepare XCTest runner (one-time per machine) =="
  agent-device prepare ios-runner --platform ios --device "$IOS_DEVICE" --timeout 300000

  # Each replay below starts its own daemon. Stop the prepare daemon first so
  # its runner lease doesn't block them (see `agent-device help workflow`).
  stop_agent_device_daemons

  echo "== iOS: launch smoke replay =="
  agent-device replay "$ROOT/.agent-device/wawona-ios-smoke.ad"

  echo "== iOS: machines-lane replay =="
  agent-device replay "$ROOT/.agent-device/wawona-ios-machines.ad"
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

  if [[ -n "${WAWONA_ANDROID_APK:-}" ]]; then
    echo "== Android: install $WAWONA_ANDROID_APK =="
    # Fresh install: dev builds are signed with rotating debug keys, so an
    # upgrade install can fail with INSTALL_FAILED_UPDATE_INCOMPATIBLE.
    adb -s "$serial" uninstall com.aspauldingcode.wawona >/dev/null 2>&1 || true
    adb -s "$serial" install "$WAWONA_ANDROID_APK"
  fi

  # shellcheck source=scripts/lib/android-ad-scale.sh
  source "$ROOT/scripts/lib/android-ad-scale.sh"

  echo "== Android: launch smoke batch =="
  agent-device batch --session wawona-android-smoke --platform android --serial "$serial" \
    --steps-file "$ROOT/.agent-device/wawona-android-smoke-batch.json" --json

  echo "== Android: machines-lane (label-driven) =="
  local sess=wawona-android-machines
  local ad_common=(--platform android --serial "$serial" --session "$sess")
  dismiss_android_blockers() {
    adb -s "$serial" shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
    agent-device alert dismiss "${ad_common[@]}" >/dev/null 2>&1 || true
    # ANR sheets expose Wait / Close app; prefer Wait so the app can recover.
    if agent-device is visible 'label="Wait"' "${ad_common[@]}" >/dev/null 2>&1; then
      agent-device press 'label="Wait"' "${ad_common[@]}" >/dev/null 2>&1 || true
    fi
    if agent-device is visible 'label="Close app"' "${ad_common[@]}" >/dev/null 2>&1; then
      agent-device press 'label="Close app"' "${ad_common[@]}" >/dev/null 2>&1 || true
    fi
  }
  # Compose a11y is sparse on CI (agent-device interactive snapshot often empty).
  # Prefer uiautomator text bounds → find/label → known reference taps.
  android_press_text() {
    local text="$1"
    android_uia_tap_text "$text" && return 0
    agent-device find "$text" press --first "${ad_common[@]}" >/dev/null 2>&1 && return 0
    agent-device press "label=\"$text\"" "${ad_common[@]}" >/dev/null 2>&1 && return 0
    return 1
  }
  android_dismiss_welcome() {
    if android_press_text "Continue"; then
      agent-device wait 2000 "${ad_common[@]}"
      return 0
    fi
    # Centered Continue on welcome (1080x2424 recording coords).
    android_tap_ref 540 1404
    agent-device wait 2000 "${ad_common[@]}"
    if android_uia_has_text "Continue"; then
      android_tap_ref 540 1450
      agent-device wait 2000 "${ad_common[@]}"
    fi
  }
  android_press_start() {
    if android_press_text "Start"; then
      return 0
    fi
    # Machine Configuration Start (bottom-left of card in recordings).
    android_tap_ref 227 1039
    agent-device wait 800 "${ad_common[@]}"
    if android_uia_has_text "Start"; then
      android_tap_ref 216 1040
      agent-device wait 800 "${ad_common[@]}"
    fi
    # Success if Start is gone (session starting) or Stop/session chrome appears.
    if ! android_uia_has_text "Start"; then
      return 0
    fi
    return 1
  }
  agent-device open com.aspauldingcode.wawona --relaunch "${ad_common[@]}"
  agent-device wait 4000 "${ad_common[@]}"
  dismiss_android_blockers
  agent-device screenshot "$ARTIFACTS/android-first-screen.png" "${ad_common[@]}"
  android_dismiss_welcome
  dismiss_android_blockers
  agent-device screenshot "$ARTIFACTS/android-machines-root.png" "${ad_common[@]}"
  if android_uia_has_text "Continue"; then
    echo "FAIL: still on Welcome after Continue" >&2
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    exit 1
  fi
  android_press_text "Got it" || true
  agent-device wait 500 "${ad_common[@]}"
  if android_press_text "Add Machine"; then
    agent-device wait 1500 "${ad_common[@]}"
    agent-device screenshot "$ARTIFACTS/android-add-machine-sheet.png" "${ad_common[@]}"
    agent-device back "${ad_common[@]}"
    agent-device wait 1000 "${ad_common[@]}"
  fi
  dismiss_android_blockers
  android_press_start || {
    echo "FAIL: could not press Start on machines screen" >&2
    agent-device snapshot -i --raw "${ad_common[@]}" || true
    adb -s "$serial" exec-out cat /sdcard/wawona-ui.xml 2>/dev/null | tr '>' '\n' | grep -E 'text=|content-desc=' | head -40 || true
    exit 1
  }
  agent-device wait 10000 "${ad_common[@]}"
  dismiss_android_blockers
  android_find_press "Got it" || true
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
