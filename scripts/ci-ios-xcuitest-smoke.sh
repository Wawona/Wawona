#!/usr/bin/env bash
# Gate: products iOS runtime smoke (Apple platform tools only).
#
# Installs the product simulator .app with simctl, launches it, asserts the
# process stays alive, and captures a screenshot. Optional XCUITest pass when
# WAWONA_IOS_XCUITEST=1 (builds UITest runner via xcodegen; slower).
#
# Does NOT use agent-device CLI. Agent-device stays for local/lab/vphone.
#
#   WAWONA_IOS_APP=result-ios/Wawona.app ./scripts/ci-ios-xcuitest-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${WAWONA_IOS_APP:?set WAWONA_IOS_APP to Wawona.app}"
BUNDLE_ID="${WAWONA_IOS_BUNDLE_ID:-com.aspauldingcode.Wawona}"
SIM_NAME="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
OUT_DIR="${WAWONA_SMOKE_OUT:-.agent-device/test-artifacts/ci-ios-runtime}"
mkdir -p "$OUT_DIR"

if [[ ! -d "$APP" ]]; then
  echo "FAIL: app missing at $APP" >&2
  exit 1
fi

echo "== iOS runtime smoke (simctl) =="
echo "app=$APP sim=$SIM_NAME bundle=$BUNDLE_ID"

if ! xcrun simctl list devices available | grep -q "$SIM_NAME ("; then
  echo "Creating simulator '$SIM_NAME'"
  DEVTYPE=$(xcrun simctl list devicetypes | grep -F "$SIM_NAME (" | sed -E 's/.*\((com[^)]*)\).*/\1/' | head -1)
  RUNTIME=$(xcrun simctl list runtimes | grep -E "^iOS" | tail -1 | sed -E 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9._-]+).*/\1/')
  xcrun simctl create "$SIM_NAME" "$DEVTYPE" "$RUNTIME"
fi

UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | grep -oE '[A-F0-9-]{36}' | head -1)
[[ -n "$UDID" ]] || { echo "FAIL: no UDID for $SIM_NAME" >&2; exit 1; }

xcrun simctl bootstatus "$UDID" -b || xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID"

xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
# Launch once; --console-pty keeps a session we can screenshot against.
set +e
xcrun simctl launch "$UDID" "$BUNDLE_ID" >"$OUT_DIR/launch.out" 2>"$OUT_DIR/launch.err"
launch_rc=$?
set -e
if [[ "$launch_rc" -ne 0 ]]; then
  echo "FAIL: simctl launch rc=$launch_rc" >&2
  cat "$OUT_DIR/launch.out" "$OUT_DIR/launch.err" || true
  exit 1
fi

alive=0
for _ in $(seq 1 60); do
  if xcrun simctl spawn "$UDID" launchctl print "ui/$(id -u)/$BUNDLE_ID" 2>/dev/null \
    | grep -Eqi 'state = running|pid = [1-9]'; then
    alive=1
    break
  fi
  if xcrun simctl spawn "$UDID" ps -ax 2>/dev/null | grep -F "Wawona.app/Wawona" | grep -vq grep; then
    alive=1
    break
  fi
  sleep 1
done

xcrun simctl io "$UDID" screenshot "$OUT_DIR/launch.png" || true

if [[ "$alive" -ne 1 ]]; then
  echo "FAIL: Wawona did not stay running after simctl launch" >&2
  cat "$OUT_DIR/launch.out" "$OUT_DIR/launch.err" || true
  exit 1
fi
echo "PASS: simctl install + launch (process alive)"

if [[ "${WAWONA_IOS_XCUITEST:-0}" == "1" ]]; then
  echo "== XCUITest (optional; WAWONA_IOS_XCUITEST=1) =="
  nix run ".#xcodegen-ios"
  xcodebuild test \
    -project Wawona.xcodeproj \
    -scheme Wawona-iOS \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing:Wawona-iOSUITests \
    -resultBundlePath "$OUT_DIR/WawonaUITests.xcresult" \
    | tee "$OUT_DIR/xcodebuild-test.log"
fi

{
  echo "# iOS runtime smoke"
  echo ""
  echo "**PASS:** simctl install + launch (Apple platform tools)."
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "PASS: iOS runtime smoke"
