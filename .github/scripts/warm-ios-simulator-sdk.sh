#!/usr/bin/env bash
# Host Xcode platform SDKs are the Apple SDK cache (not apple-sdks.nix /
# FlakeHub frameworks). Decide whether nix/xcodebuild may skip
# `xcodebuild -downloadPlatform …`.
#
# Usage: warm-ios-simulator-sdk.sh [platform ...]
#   platform: ios | ipados | tvos | watchos | visionos | all
#   default: ios  (product-build ios-sim / device-e2e)
#
# Gate is `xcrun --sdk TOKEN --show-sdk-path` (directory must exist), not
# merely `xcodebuild -showsdks` listing. When every required token resolves,
# sets WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1 so build-app.nix skips
# CDN `-downloadPlatform iOS` for every *simulator* SDK name.
#
# XcodeGen evaluates device Relay archives (iphoneos / appletvos / watchos /
# xros) even for simulator product slices. Warm those device packs whenever
# the caller asks for `all` or any tv/watch/vision platform.
#
# Bash 3.2-safe (macOS /bin/bash): no empty-array expansions under `set -u`.
set -euo pipefail

usage() {
  echo "Usage: $0 [ios|ipados|tvos|watchos|visionos|all]..." >&2
  exit 2
}

sdk_token_for() {
  case "$1" in
    ios|ipados) printf '%s\n' iphonesimulator ;;
    tvos) printf '%s\n' appletvsimulator ;;
    watchos) printf '%s\n' watchsimulator ;;
    visionos) printf '%s\n' xrsimulator ;;
    *) return 1 ;;
  esac
}

device_sdk_token_for() {
  case "$1" in
    ios|ipados) printf '%s\n' iphoneos ;;
    tvos) printf '%s\n' appletvos ;;
    watchos) printf '%s\n' watchos ;;
    visionos) printf '%s\n' xros ;;
    *) return 1 ;;
  esac
}

has_sdk_path() {
  local token="$1"
  local path
  path="$(xcrun --sdk "$token" --show-sdk-path 2>/dev/null || true)"
  [ -n "$path" ] && [ -d "$path" ]
}

set_skip() {
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1" >> "$GITHUB_ENV"
  else
    export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1
  fi
}

list_has() {
  local needle="$1"
  local item
  for item in $2; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

append_unique() {
  local cur="$1"
  local item="$2"
  if [ -z "$cur" ]; then
    printf '%s\n' "$item"
    return
  fi
  if list_has "$item" "$cur"; then
    printf '%s\n' "$cur"
    return
  fi
  printf '%s %s\n' "$cur" "$item"
}

PLATFORMS=""
if [ $# -eq 0 ]; then
  PLATFORMS="ios"
else
  for arg in "$@"; do
    case "$arg" in
      all)
        PLATFORMS="ios tvos watchos visionos"
        break
        ;;
      ios|ipados|tvos|watchos|visionos)
        PLATFORMS="$(append_unique "$PLATFORMS" "$arg")"
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "unknown platform: $arg" >&2
        usage
        ;;
    esac
  done
fi

SEEN_TOKENS=""
UNIQUE=""
for p in $PLATFORMS; do
  token="$(sdk_token_for "$p")"
  if list_has "$token" "$SEEN_TOKENS"; then
    continue
  fi
  SEEN_TOKENS="$(append_unique "$SEEN_TOKENS" "$token")"
  UNIQUE="$(append_unique "$UNIQUE" "$p")"
done
PLATFORMS="$UNIQUE"

NEED_DEVICE=0
case " $PLATFORMS " in
  *" tvos "*|*" watchos "*|*" visionos "*) NEED_DEVICE=1 ;;
esac

REQUIRED_TOKENS=""
for p in $PLATFORMS; do
  REQUIRED_TOKENS="$(append_unique "$REQUIRED_TOKENS" "$(sdk_token_for "$p")")"
  if [ "$NEED_DEVICE" -eq 1 ]; then
    REQUIRED_TOKENS="$(append_unique "$REQUIRED_TOKENS" "$(device_sdk_token_for "$p")")"
  fi
done
# Unified project.yml always evaluates the phone device Relay archive.
REQUIRED_TOKENS="$(append_unique "$REQUIRED_TOKENS" iphoneos)"

MISSING_TOKENS=""
for t in $REQUIRED_TOKENS; do
  if has_sdk_path "$t"; then
    echo "$t SDK path OK"
  else
    echo "$t SDK path MISSING"
    MISSING_TOKENS="$(append_unique "$MISSING_TOKENS" "$t")"
  fi
done

if [ -z "$MISSING_TOKENS" ]; then
  echo "all required Apple SDK path(s) present"
  set_skip
  exit 0
fi

echo "warming / downloading platforms for: $MISSING_TOKENS"
open -a Simulator >/dev/null 2>&1 || true

DOWNLOAD_PLATS=""
for t in $MISSING_TOKENS; do
  case "$t" in
    iphonesimulator|iphoneos) DOWNLOAD_PLATS="$(append_unique "$DOWNLOAD_PLATS" iOS)" ;;
    appletvsimulator|appletvos) DOWNLOAD_PLATS="$(append_unique "$DOWNLOAD_PLATS" tvOS)" ;;
    watchsimulator|watchos) DOWNLOAD_PLATS="$(append_unique "$DOWNLOAD_PLATS" watchOS)" ;;
    xrsimulator|xros) DOWNLOAD_PLATS="$(append_unique "$DOWNLOAD_PLATS" xrOS)" ;;
  esac
done

for plat in $DOWNLOAD_PLATS; do
  echo "Downloading Apple platform pack: $plat"
  xcodebuild -downloadPlatform "$plat" 2>&1 || \
    echo "::warning::xcodebuild -downloadPlatform $plat failed"
done

i=0
while [ "$i" -lt 15 ]; do
  i=$((i + 1))
  still=""
  for t in $MISSING_TOKENS; do
    if has_sdk_path "$t"; then
      echo "$t became visible"
    else
      still="$(append_unique "$still" "$t")"
    fi
  done
  MISSING_TOKENS="$still"
  if [ -z "$MISSING_TOKENS" ]; then
    break
  fi
  sleep 3
done

xcrun simctl list runtimes 2>/dev/null || true
xcodebuild -showsdks 2>/dev/null | grep -E 'simulator|OS' || true

MISSING_TOKENS=""
for t in $REQUIRED_TOKENS; do
  if ! has_sdk_path "$t"; then
    MISSING_TOKENS="$(append_unique "$MISSING_TOKENS" "$t")"
  fi
done

if [ -z "$MISSING_TOKENS" ]; then
  echo "all required Apple SDK path(s) present after warm"
  set_skip
  exit 0
fi

echo "::warning::Still missing SDK path(s): $MISSING_TOKENS"
echo "Leaving WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD unset so Nix may download."
exit 0
