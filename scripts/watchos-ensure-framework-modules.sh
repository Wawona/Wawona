#!/usr/bin/env bash
# Build WawonaModel / WawonaUIContracts for the current watch SDK *before*
# Swift compiles the watch app. When Wawona-watchOS is archived as an embed
# of Wawona-iOS (destination generic/platform=iOS), Xcode often schedules the
# watch Sources phase without a watchOS Swift module for those frameworks
# ("unable to resolve module dependency: 'WawonaModel'"). Post-link
# watchos-fix-embedded-frameworks.sh is too late for compile.
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  watchsimulator|watchos) ;;
  *) exit 0 ;;
esac

PROJECT="${PROJECT_FILE_PATH:?}"
CONFIGURATION="${CONFIGURATION:?}"
PLATFORM_NAME="${PLATFORM_NAME:?}"
BUILD_DIR="${BUILD_DIR:?}"

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
  rm -rf "$scratch"
  mkdir -p "$scratch"

  echo "note: watchos-ensure-framework-modules: building ${fw} for ${PLATFORM_NAME}"
  xcodebuild \
    -project "${PROJECT}" \
    -target "${fw}" \
    -sdk "${PLATFORM_NAME}" \
    -configuration "${CONFIGURATION}" \
    BUILD_DIR="${BUILD_DIR}" \
    OBJROOT="${scratch}/Build/Intermediates.noindex" \
    SYMROOT="${BUILD_DIR}" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS=arm64 \
    VALID_ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
}

for fw in WawonaModel WawonaUIContracts; do
  if swiftmodule_ready "$fw"; then
    echo "note: watchos-ensure-framework-modules: ${fw} already built for ${PLATFORM_NAME}"
    continue
  fi
  build_framework "$fw"
done
