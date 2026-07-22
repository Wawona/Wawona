#!/usr/bin/env bash
# Force Default Machine bundledAppID=<client> in the Apple Simulator defaults DB.
#
# Usage: scripts/agent-device-set-client-ios.sh <client-id> [simulator-name-or-udid]
# Env:   WAWONA_IOS_BUNDLE (default com.aspauldingcode.Wawona)
#        WAWONA_WATCH_BUNDLE for watchOS (default com.aspauldingcode.Wawona.watch)

set -euo pipefail

CLIENT="${1:?usage: $0 <client-id> [sim]}"
DEVICE="${2:-${WAWONA_IOS_SIM:-iPhone 17 Pro}}"
BUNDLE_ID="${WAWONA_IOS_BUNDLE:-com.aspauldingcode.Wawona}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/bundled-clients-catalog.sh
source "$ROOT/scripts/lib/bundled-clients-catalog.sh"

PREFS_KEY="$(bundled_client_prefs_key "$CLIENT")"
[[ -n "$PREFS_KEY" ]] || { echo "FAIL: unknown client '$CLIENT'" >&2; exit 1; }

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

# Prefer watch bundle when UDID looks like a watch (caller may set WAWONA_IOS_BUNDLE).
PAYLOAD="$(CLIENT="$CLIENT" PREFS_KEY="$PREFS_KEY" python3 - <<'PY'
import json, os
c = os.environ["CLIENT"]
k = os.environ["PREFS_KEY"]
print(json.dumps([{
  "id": f"e2e-{c}-default",
  "name": "Default Machine",
  "type": "native",
  "sshHost": "",
  "sshUser": "",
  "sshPort": 22,
  "sshPassword": "",
  "remoteCommand": "",
  "launchers": [],
  "favorite": False,
  "runtimeOverrides": {"bundledAppID": c},
  "settingsOverrides": {"NativeClientId": c, k: True},
  "nativeLauncher": c,
}], separators=(",", ":")))
PY
)"

xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.machineProfiles.v1" -string "$PAYLOAD"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.activeMachineId.v1" -string "e2e-${CLIENT}-default"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "$PREFS_KEY" -bool YES
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "hasSeenWelcome" -bool YES
xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" "wawona.pref.hasCompletedWelcome" -bool YES

echo "== iOS prefs: bundledAppID=${CLIENT} udid=${UDID} bundle=${BUNDLE_ID} =="
