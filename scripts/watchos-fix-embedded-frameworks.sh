#!/usr/bin/env bash
# ISSUE-017: XcodeGen declares WawonaModel/UIContracts as platform=iOS, so Embed
# Frameworks may copy Debug-iphonesimulator products into the watch app even when
# Debug-watchsimulator slices exist. Replace embedded frameworks with the
# matching watch(OS) SDK products after Embed.
#
# WatchOS keeps embed=false (see xcodegen.nix) so Xcode never runs Embed
# Frameworks / codeSign=true for these two. This script is the only copy into
# WawonaWatch.app/Frameworks, and therefore the only place that can re-sign
# them. Device installd rejects unsigned nested frameworks (0xe800801c).
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  # LC_BUILD_VERSION platform codes.
  watchsimulator) want_platform=9 ;;
  watchos) want_platform=4 ;;
  *) exit 0 ;;
esac

APP_FW="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}/Frameworks"

# WawonaModel/WawonaUIContracts are embed=false, link=false dependencies (see
# xcodegen.nix dependencies comment) — Xcode's own Embed Frameworks phase
# never runs for them, so this script is the *only* thing that creates
# Frameworks/ and copies them in; do not early-exit just because it is
# missing.
mkdir -p "$APP_FW"

platform_of() {
  otool -l "$1" 2>/dev/null \
    | awk '/LC_BUILD_VERSION/ { in_cmd = 1 } in_cmd && /platform/ { print $2; exit }'
}

# Match on the Mach-O platform rather than on a guessed products directory:
# the outer build already emits watch slices, just not always where
# "${BUILD_DIR}/${CONFIGURATION}-${PLATFORM_NAME}" would suggest.
find_framework() {
  local fw="$1" candidate
  while IFS= read -r candidate; do
    if [[ "$(platform_of "${candidate}/${fw}")" == "$want_platform" ]]; then
      echo "$candidate"
      return 0
    fi
  done < <(find "${BUILD_DIR}" -type d -name "${fw}.framework" 2>/dev/null)
  return 1
}

build_framework() {
  local fw="$1"
  # Runs as a script phase of the outer build, which holds a lock on the
  # XCBuildData/build.db under its OBJROOT, so the nested build needs a private
  # root. One target per invocation and a single arch: batching them, or
  # lipo-ing two arches, makes the preview/debug dylibs collide on one output
  # path. (-derivedDataPath is unusable here: it requires -scheme.)
  local scratch="${DERIVED_FILE_DIR:-${TEMP_DIR:-${TMPDIR:-/tmp}}}/watchos-embedded-frameworks/${fw}"
  rm -rf "$scratch"
  mkdir -p "$scratch"

  echo "note: rebuilding ${fw} for ${PLATFORM_NAME} in ${scratch}"
  xcodebuild \
    -project "${PROJECT_FILE_PATH}" \
    -target "${fw}" \
    -sdk "${PLATFORM_NAME}" \
    -configuration "${CONFIGURATION}" \
    BUILD_DIR="${scratch}/Build/Products" \
    OBJROOT="${scratch}/Build/Intermediates.noindex" \
    SYMROOT="${scratch}/Build/Products" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS=arm64 \
    VALID_ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

  echo "${scratch}/Build/Products/${CONFIGURATION}-${PLATFORM_NAME}/${fw}.framework"
}

# Framework targets build with CODE_SIGNING_ALLOWED=NO (IPA CI must not apply
# a Manual PROVISIONING_PROFILE_SPECIFIER to them). iOS/tvOS/visionOS re-sign
# on Xcode's Embed Frameworks phase; watchOS has to do it here.
sign_embedded_framework() {
  local fw_path="$1"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ]; then
    return 0
  fi
  local identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [ -z "$identity" ]; then
    identity="${CODE_SIGN_IDENTITY:-}"
  fi
  if [ -z "$identity" ]; then
    echo "error: cannot sign ${fw_path}: no EXPANDED_CODE_SIGN_IDENTITY" >&2
    exit 1
  fi
  chmod -R u+w "$fw_path"
  /usr/bin/codesign --force --timestamp=none --sign "$identity" "$fw_path"
  echo "Signed ${fw_path} with ${identity}"
}

for fw in WawonaModel WawonaUIContracts; do
  if ! src_fw="$(find_framework "$fw")"; then
    src_fw="$(build_framework "$fw" | tail -1)"
  fi

  if [[ ! -d "$src_fw" ]]; then
    echo "error: no ${PLATFORM_NAME} build of ${fw}.framework found under ${BUILD_DIR}" >&2
    exit 1
  fi

  dst_fw="${APP_FW}/${fw}.framework"
  rm -rf "$dst_fw"
  cp -R "$src_fw" "$dst_fw"
  sign_embedded_framework "$dst_fw"
  echo "Embedded ${fw}.framework for ${PLATFORM_NAME} from ${src_fw}"
done
