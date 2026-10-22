#!/usr/bin/env bash
# Build WawonaModel / WawonaUIContracts for the current watch SDK *before*
# Swift compiles the watch app. When Wawona-watchOS is archived as an embed
# of Wawona-iOS (destination generic/platform=iOS), Xcode often schedules the
# watch Sources phase without a watchOS Swift module for those frameworks
# ("unable to resolve module dependency: 'WawonaModel'"). Post-link
# watchos-fix-embedded-frameworks.sh is too late for compile.
#
# Critical: this runs inside a Wawona-watchOS script phase. Inherited env
# (PRODUCT_NAME=Wawona, TARGET_NAME, EXECUTABLE_*, ENABLE_DEBUG_DYLIB, …)
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

# A leftover watch framework from an older DerivedData still has the right
# LC_BUILD_VERSION. Treat it as missing when Sources/<fw> is newer, or the
# watch app compiles against a module that never exported later types.
sources_newer_than() {
  local fw="$1" stamp="$2"
  local src="${SRCROOT}/Sources/${fw}"
  [[ -d "$src" && -n "$stamp" && -f "$stamp" ]] || return 1
  local newer
  newer="$(find "$src" -name '*.swift' -newer "$stamp" -print -quit)"
  [[ -n "$newer" ]]
}

swiftmodule_ready() {
  local fw="$1" candidate stamp
  while IFS= read -r candidate; do
    if [[ "$(platform_of "${candidate}/${fw}")" != "$want_platform" ]]; then
      continue
    fi
    stamp="$(find "${candidate}/Modules/${fw}.swiftmodule" -type f -name '*.swiftmodule' -print -quit 2>/dev/null || true)"
    [[ -n "$stamp" ]] || continue
    if sources_newer_than "$fw" "$stamp"; then
      echo "note: watchos-ensure-framework-modules: ${fw} swiftmodule older than Sources/${fw}"
      continue
    fi
    return 0
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

  merge_into_configuration_build_dir "$fw" "${conf_dir}/${fw}.framework" "${dest_root}"
}

# Xcode's FRAMEWORK_SEARCH_PATHS/-F for *this* compile step resolves through
# $(BUILT_PRODUCTS_DIR), i.e. CONFIGURATION_BUILD_DIR. Not the plain
# ${BUILD_DIR}/${CONFIGURATION}-${PLATFORM_NAME} split above. Those two are
# the same path in a normal interactive Xcode build. build-app.nix sets
# SYMROOT so each platform keeps its own directory. If a caller still forces
# one CONFIGURATION_BUILD_DIR, that path differs from BUILD_DIR and swiftc
# looks there. Installing only under BUILD_DIR is then invisible, and the
# watch app's
# `import WawonaModel` fails with "could not find module ... for target
# arm64-apple-watchos-simulator" even though the framework was built.
# When the directories differ, copy only this platform's swiftmodule slice
# into the shared framework. Never rm -rf it, or the earlier platform's
# slice is destroyed.
merge_into_configuration_build_dir() {
  local fw="$1" src_framework="$2" dest_root="$3"
  local cbd="${CONFIGURATION_BUILD_DIR:-}"
  [[ -n "$cbd" && "$cbd" != "$dest_root" ]] || return 0

  local dst_framework="${cbd}/${fw}.framework"
  if [[ ! -d "$dst_framework" ]]; then
    mkdir -p "$cbd"
    cp -R "$src_framework" "$dst_framework"
    echo "note: watchos-ensure-framework-modules: seeded ${dst_framework} (CONFIGURATION_BUILD_DIR)"
    return 0
  fi

  local src_swiftmodule="${src_framework}/Modules/${fw}.swiftmodule"
  local dst_swiftmodule="${dst_framework}/Modules/${fw}.swiftmodule"
  if [[ -d "$src_swiftmodule" ]]; then
    mkdir -p "$dst_swiftmodule"
    cp -R "${src_swiftmodule}/." "${dst_swiftmodule}/"
    echo "note: watchos-ensure-framework-modules: merged ${PLATFORM_NAME} swiftmodule into ${dst_swiftmodule}"
  fi
  # Headers are platform-agnostic Swift-generated interfaces; harmless to
  # union in case the destination's copy predates a header-only change.
  if [[ -d "${src_framework}/Headers" ]]; then
    mkdir -p "${dst_framework}/Headers"
    cp -Rn "${src_framework}/Headers/." "${dst_framework}/Headers/" 2>/dev/null || true
  fi
}

for fw in WawonaModel WawonaUIContracts; do
  if swiftmodule_ready "$fw"; then
    echo "note: watchos-ensure-framework-modules: ${fw} already built for ${PLATFORM_NAME}"
    continue
  fi
  build_framework "$fw"
done
