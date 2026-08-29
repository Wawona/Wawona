#!/usr/bin/env bash
# Host Xcode platform SDKs are the Apple SDK cache (not apple-sdks.nix /
# FlakeHub frameworks). Decide whether nix/xcodebuild may skip
# `xcodebuild -downloadPlatform …`.
#
# Usage: warm-ios-simulator-sdk.sh [platform ...]
#   platform: ios | ipados | tvos | watchos | visionos | all
#   default: ios  (product-build ios-sim / device-e2e)
#
# When a requested simulator SDK is present, sets
# WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1. wwn-toolchain build-app.nix
# currently runs `-downloadPlatform iOS` for *any* SDK whose name ends in
# "simulator" (including watchsimulator / appletvsimulator / xrsimulator).
# The skip flag is what stops that CDN hit on apple-family lanes.
#
# Bash 3.2-safe (macOS /bin/bash): no empty-array expansions under `set -u`.
set -euo pipefail

usage() {
  echo "Usage: $0 [ios|ipados|tvos|watchos|visionos|all]..." >&2
  exit 2
}

# platform -> xcodebuild -showsdks token
sdk_token_for() {
  case "$1" in
    ios|ipados) printf '%s\n' iphonesimulator ;;
    tvos) printf '%s\n' appletvsimulator ;;
    watchos) printf '%s\n' watchsimulator ;;
    visionos) printf '%s\n' xrsimulator ;;
    *) return 1 ;;
  esac
}

# platform -> simctl list runtimes grep (ERE). Anchor the display name so
# 'iOS' cannot match a later token; visionOS also lists SimRuntime.xrOS-*.
runtime_ere_for() {
  case "$1" in
    ios|ipados) printf '%s\n' '^iOS ' ;;
    tvos) printf '%s\n' '^tvOS ' ;;
    watchos) printf '%s\n' '^watchOS ' ;;
    visionos) printf '%s\n' '^visionOS |xrOS' ;;
    *) return 1 ;;
  esac
}

has_sdk() {
  local token="$1"
  xcodebuild -showsdks 2>/dev/null | grep -q -- "$token"
}

has_runtime() {
  local ere="$1"
  xcrun simctl list runtimes 2>/dev/null | grep -E -q -- "$ere"
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
  # $1 = current list (may be empty), $2 = item → print new list
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

# Dedup by SDK token (ios + ipados share iphonesimulator).
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

MISSING=""
PRESENT=""
for p in $PLATFORMS; do
  token="$(sdk_token_for "$p")"
  ere="$(runtime_ere_for "$p")"
  if has_sdk "$token"; then
    echo "$token SDK present"
    PRESENT="$(append_unique "$PRESENT" "$p")"
  elif has_runtime "$ere"; then
    echo "$p runtime present (SDK listing may lag)"
    PRESENT="$(append_unique "$PRESENT" "$p")"
  else
    MISSING="$(append_unique "$MISSING" "$p")"
  fi
done

if [ -z "$MISSING" ]; then
  echo "requested simulator SDK(s) present"
  set_skip
  exit 0
fi

echo "simulator SDK not listed yet for: $MISSING; warming CoreSimulator..."
open -a Simulator >/dev/null 2>&1 || true
i=0
while [ "$i" -lt 10 ]; do
  i=$((i + 1))
  still_missing=""
  for p in $MISSING; do
    token="$(sdk_token_for "$p")"
    ere="$(runtime_ere_for "$p")"
    if has_sdk "$token" || has_runtime "$ere"; then
      echo "$p became visible"
      PRESENT="$(append_unique "$PRESENT" "$p")"
    else
      still_missing="$(append_unique "$still_missing" "$p")"
    fi
  done
  MISSING="$still_missing"
  if [ -z "$MISSING" ]; then
    break
  fi
  sleep 2
done

xcrun simctl list runtimes 2>/dev/null || true
xcodebuild -showsdks 2>/dev/null | grep -i simulator || true

if [ -n "$PRESENT" ]; then
  echo "simulator SDK/runtime available for: $PRESENT; skipping platform download in Nix builds"
  set_skip
  if [ -n "$MISSING" ]; then
    echo "::warning::Still missing simulator SDK/runtime for: $MISSING"
  fi
  exit 0
fi

echo "::warning::No requested simulator SDK or runtime visible ($PLATFORMS); Nix may run xcodebuild -downloadPlatform iOS"
exit 0
