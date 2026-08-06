#!/usr/bin/env bash
# Build WawonaModel / WawonaUIContracts for the current watch SDK *before*
# Swift compiles the watch app. When Wawona-watchOS is archived as an embed
# of Wawona-iOS (destination generic/platform=iOS), Xcode often schedules the
# watch Sources phase without a watchOS Swift module for those frameworks
# ("unable to resolve module dependency: 'WawonaModel'"). Post-link
# watchos-fix-embedded-frameworks.sh is too late for compile.
#
# Critical: this runs inside a Wawona-watchOS script phase. Inherited env
# (PRODUCT_NAME=WawonaWatch, TARGET_NAME, EXECUTABLE_*, ENABLE_DEBUG_DYLIB, …)
# leaks into nested xcodebuild and turns framework targets into the watch
# app's debug dylib (undefined _main). Wipe product/target vars and isolate
# BUILD_DIR before invoking xcodebuild.
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  watchsimulator|watchos) ;;
  *) exit 0 ;;
esac

PROJECT="${PROJECT_FILE_PATH:?}"
CONFIGURATION="${CONFIGURATION:?}"
PLATFORM_NAME="${PLATFORM_NAME:?}"
BUILD_DIR="${BUILD_DIR:?}"
SRCROOT="${SRCROOT:?}"

# Preserve only what nested xcodebuild needs; drop watch-app product env.
clean_env=(
  env -i
  "HOME=${HOME:-/var/empty}"
  "PATH=${PATH}"
  "TMPDIR=${TMPDIR:-/tmp}"
  "USER=${USER:-}"
  "LOGNAME=${LOGNAME:-${USER:-}}"
  "SHELL=${SHELL:-/bin/bash}"
  "TERM=${TERM:-dumb}"
  "LANG=${LANG:-C}"
  "SRCROOT=${SRCROOT}"
  "PROJECT_FILE_PATH=${PROJECT}"
)
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  clean_env+=("DEVELOPER_DIR=${DEVELOPER_DIR}")
fi
if [[ -n "${SDKROOT:-}" ]]; then
  clean_env+=("SDKROOT=${SDKROOT}")
fi

platform_of() {
  otool -l "$1" 2>/dev/null \
    | awk '/LC_BUILD_VERSION/ { in_cmd = 1 } in_cmd && /platform/ { print $2; exit }'
}

want_platform=
case "$PLATFORM_NAME" in
  watchsimulator) want_platform=9 ;;
  watchos) want_platform=4 ;;
esac

swiftmodule_ready() {
  local fw="$1" candidate
  while IFS= read -r candidate; do
    if [[ "$(platform_of "${candidate}/${fw}")" == "$want_platform" ]] \
      && [[ -d "${candidate}/Modules/${fw}.swiftmodule" || -d "${candidate}/Modules" ]]; then
      return 0
    fi
  done < <(find "${BUILD_DIR}" -type d -name "${fw}.framework" 2>/dev/null)
  return 1
}

build_framework() {
  local fw="$1"
  local scratch="${DERIVED_FILE_DIR:-${TEMP_DIR:-${TMPDIR:-/tmp}}}/watchos-ensure-frameworks/${fw}"
  local isolated="${scratch}/BuildProducts"
  rm -rf "$scratch"
  mkdir -p "$isolated"

  echo "note: watchos-ensure-framework-modules: building ${fw} for ${PLATFORM_NAME}"
  local archs="arm64"
  local valid="arm64"
  if [[ "$PLATFORM_NAME" == "watchos" ]]; then
    # Match Wawona-watchOS ARCHS (ASC 90733 needs arm64_32 + arm64).
    archs="arm64_32 arm64"
    valid="arm64_32 arm64"
  fi
  "${clean_env[@]}" xcodebuild \
    -project "${PROJECT}" \
    -target "${fw}" \
    -sdk "${PLATFORM_NAME}" \
    -configuration "${CONFIGURATION}" \
    BUILD_DIR="${isolated}" \
    OBJROOT="${scratch}/Build/Intermediates.noindex" \
    SYMROOT="${isolated}" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="${archs}" \
    VALID_ARCHS="${valid}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    build

  # Copy watch-platform frameworks into the parent BUILD_DIR so the watch
  # Sources phase and embed phases can see them.
  local conf_dir
  conf_dir="$(find "${isolated}" -type d -name "${CONFIGURATION}-${PLATFORM_NAME}" | head -1)"
  if [[ -z "${conf_dir}" || ! -d "${conf_dir}/${fw}.framework" ]]; then
    echo "error: watchos-ensure-framework-modules: missing ${fw}.framework under ${isolated}" >&2
    return 1
  fi
  local dest_root="${BUILD_DIR}/${CONFIGURATION}-${PLATFORM_NAME}"
  mkdir -p "${dest_root}"
  rm -rf "${dest_root}/${fw}.framework"
  cp -R "${conf_dir}/${fw}.framework" "${dest_root}/"
  echo "note: watchos-ensure-framework-modules: installed ${dest_root}/${fw}.framework"
}

for fw in WawonaModel WawonaUIContracts; do
  if swiftmodule_ready "$fw"; then
    echo "note: watchos-ensure-framework-modules: ${fw} already built for ${PLATFORM_NAME}"
    continue
  fi
  build_framework "$fw"
done
