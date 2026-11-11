#!/usr/bin/env bash
# Tip Apple-simulator Wawona for agent-device / local dogfood.
# Same HEAD + product-path stamp contract as ensure-tip-wawona-macos.sh.
#
# Usage:
#   eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh tvOS)"
#   eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh visionOS)"
#   eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh iOS)"
#   eval "$(scripts/appium/ensure-tip-wawona-apple-sim.sh watchOS)"
#
# Exports: WAWONA_APP_PATH, WAWONA_SIM_UDID, WAWONA_TIP_PLATFORM
#
# Env:
#   WAWONA_TEST_REBUILD=1     force xcodebuild even if stamp matches
#   WAWONA_TIP_SKIP_BUILD=1   reuse tip only when stamp+binary ok (lab);
#                             forbidden when proving a UI fix you just edited
#   WAWONA_SIM_UDID           destination id (else first booted matching sim)
#   WAWONA_ALLOW_STALE_TEST_APP=1  lab escape only (never Gate / UI proof)
set -euo pipefail

PLATFORM="${1:-}"
if [[ -z "$PLATFORM" ]]; then
  echo "usage: ensure-tip-wawona-apple-sim.sh <tvOS|visionOS|iOS|watchOS>" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/require-tip-wawona-app.sh"

export PATH="${HOME}/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

case "$PLATFORM" in
  tvOS)
    SCHEME="Wawona-tvOS"
    TIP_ROOT="${WAWONA_TIP_ROOT:-/tmp/wawona-tvos-tip}"
    SDK_DIR="Debug-appletvsimulator"
    DEST_PLATFORM="tvOS Simulator"
    ;;
  visionOS)
    SCHEME="Wawona-visionOS"
    TIP_ROOT="${WAWONA_TIP_ROOT:-/tmp/wawona-visionos-tip}"
    SDK_DIR="Debug-xrsimulator"
    DEST_PLATFORM="visionOS Simulator"
    ;;
  iOS)
    SCHEME="Wawona-iOS"
    TIP_ROOT="${WAWONA_TIP_ROOT:-/tmp/wawona-ios-tip}"
    SDK_DIR="Debug-iphonesimulator"
    DEST_PLATFORM="iOS Simulator"
    ;;
  watchOS)
    SCHEME="Wawona-watchOS"
    TIP_ROOT="${WAWONA_TIP_ROOT:-/tmp/wawona-watchos-tip}"
    SDK_DIR="Debug-watchsimulator"
    DEST_PLATFORM="watchOS Simulator"
    ;;
  *)
    echo "FAIL: unknown platform '$PLATFORM' (tvOS|visionOS|iOS|watchOS)" >&2
    exit 2
    ;;
esac

DD="${TIP_ROOT}/DerivedData"
APP="${TIP_ROOT}/DerivedData/Build/Products/${SDK_DIR}/Wawona.app"
STAMP="${TIP_ROOT}/git-HEAD"

resolve_udid() {
  if [[ -n "${WAWONA_SIM_UDID:-}" ]]; then
    echo "$WAWONA_SIM_UDID"
    return 0
  fi
  # Prefer already-booted matching runtime.
  local line
  line="$(xcrun simctl list devices booted 2>/dev/null | grep -E "$DEST_PLATFORM|Apple TV|Apple Vision|iPhone|Apple Watch" | head -1 || true)"
  if [[ -n "$line" ]]; then
    echo "$line" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
    return 0
  fi
  case "$PLATFORM" in
    tvOS) xcrun simctl list devices available | grep -E 'Apple TV' | grep -v unavailable | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' ;;
    visionOS) xcrun simctl list devices available | grep -E 'Apple Vision' | grep -v unavailable | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' ;;
    iOS) xcrun simctl list devices available | grep -E 'iPhone' | grep -v unavailable | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' ;;
    watchOS) xcrun simctl list devices available | grep -E 'Apple Watch' | grep -v unavailable | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' ;;
  esac
}

cd "$ROOT"
HEAD="$(git rev-parse HEAD)"
UDID="$(resolve_udid)"
if [[ -z "$UDID" ]]; then
  echo "FAIL: no $DEST_PLATFORM UDID (set WAWONA_SIM_UDID)" >&2
  exit 2
fi

need_build=0
if [[ "${WAWONA_TIP_SKIP_BUILD:-0}" == "1" ]]; then
  if [[ ! -d "$APP" ]]; then
    echo "ensure-tip-apple-sim: SKIP_BUILD=1 but app missing at $APP; building" >&2
    need_build=1
  else
    if ! wawona_tip_stamp_is_fresh "$TIP_ROOT"; then
      echo "FAIL: WAWONA_TIP_SKIP_BUILD=1 but tip stamp stale for $PLATFORM ($TIP_ROOT/git-HEAD)" >&2
      echo "Rebuild (unset WAWONA_TIP_SKIP_BUILD) before UI proof. See wawona-test-tip-app." >&2
      exit 2
    fi
    echo "ensure-tip-apple-sim: SKIP_BUILD=1; stamp fresh for $PLATFORM" >&2
  fi
else
  if [[ "${WAWONA_TEST_REBUILD:-0}" == "1" ]]; then
    need_build=1
  fi
  if [[ ! -d "$APP" ]]; then
    need_build=1
  fi
  if [[ "$need_build" -eq 0 ]] && ! wawona_tip_stamp_is_fresh "$TIP_ROOT"; then
    need_build=1
  fi
fi

if [[ "$need_build" -eq 1 ]]; then
  echo "ensure-tip-apple-sim: building $SCHEME for $HEAD (udid=$UDID)" >&2
  mkdir -p "$TIP_ROOT" "$DD"
  _sdk="${SDK_DIR#Debug-}"
  if ! (cd "$ROOT" && cargo xtask deps get "$_sdk") >&2; then
    echo "FAIL: cargo xtask deps get $_sdk" >&2
    exit 2
  fi
  xcodebuild \
    -project "$ROOT/Wawona.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DD" \
    -destination "platform=${DEST_PLATFORM},id=${UDID}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build >&2
  if [[ ! -d "$APP" ]]; then
    # Some schemes nest under a different Products layout; resolve once.
    found="$(find "$DD/Build/Products" -name 'Wawona.app' -type d 2>/dev/null | head -1 || true)"
    if [[ -n "$found" ]]; then
      APP="$found"
    fi
  fi
  if [[ ! -d "$APP" ]]; then
    echo "FAIL: tip app missing after build: expected under $DD/Build/Products/${SDK_DIR}" >&2
    exit 2
  fi
  wawona_tip_write_stamp "$TIP_ROOT" "$ROOT"
fi

wawona_refuse_stale_app_path "$APP"
wawona_require_tip_fresh_for_proof "$TIP_ROOT" "$ROOT" || exit 2

export WAWONA_APP_PATH="$APP"
export WAWONA_SIM_UDID="$UDID"
export WAWONA_TIP_PLATFORM="$PLATFORM"
export WAWONA_TIP_ROOT="$TIP_ROOT"

printf 'export WAWONA_APP_PATH=%q\n' "$WAWONA_APP_PATH"
printf 'export WAWONA_SIM_UDID=%q\n' "$WAWONA_SIM_UDID"
printf 'export WAWONA_TIP_PLATFORM=%q\n' "$WAWONA_TIP_PLATFORM"
printf 'export WAWONA_TIP_ROOT=%q\n' "$WAWONA_TIP_ROOT"
echo "ensure-tip-apple-sim: ok platform=$PLATFORM app=$WAWONA_APP_PATH head=$HEAD udid=$UDID" >&2
