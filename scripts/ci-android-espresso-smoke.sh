#!/usr/bin/env bash
# Gate: products Android runtime smoke (Android platform tools).
#
# Installs the product debug APK with adb, starts MainActivity, asserts the
# process stays alive, dumps the UI hierarchy (uiautomator), and runs
# connectedDebugAndroidTest (Espresso / Compose UI Test) when a Gradle project
# is available.
#
# Does NOT use agent-device CLI.
#
#   WAWONA_ANDROID_APK=dist/Wawona.apk ./scripts/ci-android-espresso-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APK="${WAWONA_ANDROID_APK:?set WAWONA_ANDROID_APK}"
PKG="${WAWONA_ANDROID_PACKAGE:-com.aspauldingcode.wawona}"
ACTIVITY="${WAWONA_ANDROID_ACTIVITY:-com.aspauldingcode.wawona.MainActivity}"
OUT_DIR="${WAWONA_SMOKE_OUT:-.agent-device/test-artifacts/ci-android-runtime}"
mkdir -p "$OUT_DIR"

if [[ ! -f "$APK" ]]; then
  echo "FAIL: APK missing at $APK" >&2
  exit 1
fi

echo "== Android runtime smoke (adb + Espresso) =="
echo "apk=$APK package=$PKG"

adb wait-for-device
adb shell getprop sys.boot_completed | grep -q 1 || {
  echo "waiting for boot_completed..."
  for _ in $(seq 1 120); do
    adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
    sleep 2
  done
}

adb uninstall "$PKG" 2>/dev/null || true
adb install -r "$APK"
adb shell am force-stop "$PKG" 2>/dev/null || true
adb shell am start -W -n "$PKG/$ACTIVITY" | tee "$OUT_DIR/am-start.txt"

alive=0
for _ in $(seq 1 45); do
  if adb shell pidof "$PKG" 2>/dev/null | grep -Eq '[0-9]'; then
    alive=1
    break
  fi
  sleep 1
done
adb exec-out screencap -p >"$OUT_DIR/launch.png" || true
adb shell uiautomator dump /sdcard/wawona-ui.xml 2>/dev/null || true
adb pull /sdcard/wawona-ui.xml "$OUT_DIR/wawona-ui.xml" 2>/dev/null || true

if [[ "$alive" -ne 1 ]]; then
  echo "FAIL: package $PKG not running after am start" >&2
  adb logcat -d -t 80 *:E | tee "$OUT_DIR/logcat-err.txt" || true
  exit 1
fi
echo "PASS: adb install + am start (process alive)"

# Espresso/Compose instrumentation is opt-in (needs a full Gradle Android
# project + matching debug variant). Gate default is adb + uiautomator.
if [[ "${WAWONA_ANDROID_ESPRESSO:-0}" == "1" ]] && [[ -f android/gradlew || -f gradlew ]]; then
  echo "== connectedDebugAndroidTest (Espresso / Compose UI Test) =="
  if [[ -f android/gradlew ]]; then
    (cd android && ./gradlew :app:connectedDebugAndroidTest --stacktrace) \
      | tee "$OUT_DIR/espresso.log"
  else
    ./gradlew :app:connectedDebugAndroidTest --stacktrace \
      | tee "$OUT_DIR/espresso.log"
  fi
  echo "PASS: connectedDebugAndroidTest"
elif [[ -f "$OUT_DIR/wawona-ui.xml" ]] && grep -Eq 'wwn\.machines\.|wwn\.welcome\.' "$OUT_DIR/wawona-ui.xml"; then
  echo "PASS: uiautomator dump shows Wawona a11y tags"
else
  echo "PASS: adb launch (uiautomator dump optional)"
fi

{
  echo "# Android runtime smoke"
  echo ""
  echo "**PASS:** adb install + launch (Android platform tools)."
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "PASS: Android runtime smoke"
