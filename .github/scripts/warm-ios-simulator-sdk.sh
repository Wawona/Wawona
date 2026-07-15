#!/usr/bin/env bash
# Decide whether nix/xcodebuild may skip `xcodebuild -downloadPlatform iOS`.
# Prefer SDK presence (fast, no Simulator.app) over runtime visibility after warm.
set -euo pipefail

has_iphonesimulator_sdk() {
  xcodebuild -showsdks 2>/dev/null | grep -q 'iphonesimulator'
}

has_ios_runtime() {
  xcrun simctl list runtimes 2>/dev/null | grep -q 'iOS'
}

# Fast path: SDK already on the runner image.
if has_iphonesimulator_sdk; then
  echo "iphonesimulator SDK present"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1" >> "$GITHUB_ENV"
  else
    export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1
  fi
  # Best-effort warm so simctl devices work; do not block skip on this.
  open -a Simulator >/dev/null 2>&1 || true
  exit 0
fi

echo "iphonesimulator SDK not listed yet; warming CoreSimulator..."
open -a Simulator || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if has_ios_runtime || has_iphonesimulator_sdk; then
    break
  fi
  sleep 2
done

xcrun simctl list runtimes 2>/dev/null || true
xcodebuild -showsdks 2>/dev/null | grep -i simulator || true

if has_iphonesimulator_sdk || has_ios_runtime; then
  echo "iOS Simulator SDK/runtime available; skipping platform download in Nix builds"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1" >> "$GITHUB_ENV"
  else
    export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1
  fi
  exit 0
fi

echo "::warning::No iphonesimulator SDK or iOS runtime visible; Nix may run xcodebuild -downloadPlatform iOS"
exit 0
