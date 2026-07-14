#!/usr/bin/env bash
# Force Default Machine bundledAppID=niri in the iOS Simulator defaults DB.
#
# Writes the shared `wawona.machineProfiles.v1` key in a shape both
# WWNMachineProfileStore (ObjC) and MachineProfileStore (Swift) can load.
#
# Usage: scripts/agent-device-set-niri-ios.sh [simulator-name-or-udid]
set -euo pipefail

BUNDLE_ID=com.aspauldingcode.Wawona
DEVICE="${1:-${WAWONA_IOS_SIM:-iPhone 17 Pro}}"

UDID="$DEVICE"
if ! [[ "$DEVICE" =~ ^[0-9A-Fa-f-]{20,}$ ]]; then
  UDID="$(xcrun simctl list devices booted 2>/dev/null | awk -F '[()]' -v n="$DEVICE" '
    index($0, n) { print $2; exit }
  ')"
  if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl list devices available 2>/dev/null | awk -F '[()]' -v n="$DEVICE" '
      index($0, n) && /(Shutdown|Booted)/ { print $2; exit }
    ')"
  fi
fi
[[ -n "$UDID" ]] || { echo "FAIL: could not resolve simulator for '$DEVICE'" >&2; exit 1; }

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

PAYLOAD='[{"id":"e2e-niri-default","name":"Default Machine","type":"native","sshHost":"","sshUser":"","sshPort":22,"sshPassword":"","remoteCommand":"","launchers":[],"favorite":false,"runtimeOverrides":{"bundledAppID":"niri"},"settingsOverrides":{"NativeClientId":"niri","NiriEnabled":true},"nativeLauncher":"niri"}]'

# String form hits the legacy loader in both stores.
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.machineProfiles.v1" -string "$PAYLOAD"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.activeMachineId.v1" -string "e2e-niri-default"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "NiriEnabled" -bool YES
# Welcome gates (ObjC prefs + Swift preferences).
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "hasSeenWelcome" -bool YES
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.pref.hasCompletedWelcome" -bool YES

echo "== iOS prefs: bundledAppID=niri ($UDID) =="
