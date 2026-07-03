#!/usr/bin/env bash
# Wawona smoke tests via agent-device (iOS simulator + Android device/emulator).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$ROOT/.agent-device/test-artifacts"
IOS_DEVICE="${WAWONA_IOS_SIM:-iPhone 17 Pro}"
ANDROID_SERIAL="${WAWONA_ANDROID_SERIAL:-}"

mkdir -p "$ARTIFACTS"

if ! command -v agent-device >/dev/null; then
  echo "agent-device not found on PATH (install via nix: dendritic.mobile.enable)" >&2
  exit 1
fi

echo "== agent-device $(agent-device --version) =="

echo "== iOS: prepare runner (one-time per machine; skip if already prepared) =="
agent-device prepare ios-runner --platform ios --device "$IOS_DEVICE" --session wawona-ios-smoke --timeout 240000 || true

echo "== iOS: batch smoke =="
agent-device batch --session wawona-ios-smoke --platform ios --device "$IOS_DEVICE" \
  --steps-file "$ROOT/.agent-device/wawona-ios-smoke-batch.json" --json

if [[ -n "$ANDROID_SERIAL" ]]; then
  echo "== Android: batch smoke (serial=$ANDROID_SERIAL) =="
  # Patch serial into batch file via env substitution would need jq; pass on CLI.
  agent-device batch --session wawona-android-smoke --platform android --serial "$ANDROID_SERIAL" \
    --steps-file "$ROOT/.agent-device/wawona-android-smoke-batch.json" --json
else
  SERIAL="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')"
  if [[ -n "$SERIAL" ]]; then
    echo "== Android: batch smoke (auto serial=$SERIAL) =="
    agent-device batch --session wawona-android-smoke --platform android --serial "$SERIAL" \
      --steps-file "$ROOT/.agent-device/wawona-android-smoke-batch.json" --json
  else
    echo "== Android: skip (no device/emulator; set WAWONA_ANDROID_SERIAL) =="
  fi
fi

echo "== done; artifacts in $ARTIFACTS =="
