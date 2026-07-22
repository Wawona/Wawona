#!/usr/bin/env bash
# ISSUE-017: XcodeGen declares WawonaModel/UIContracts as platform=iOS, so Embed
# Frameworks may copy Debug-iphonesimulator products into the watch app even when
# Debug-watchsimulator slices exist. Replace embedded frameworks with the
# matching watch(OS) SDK products after Embed.
set -euo pipefail

case "${PLATFORM_NAME:-}" in
  watchsimulator|watchos) ;;
  *) exit 0 ;;
esac

APP_FW="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}/Frameworks"
SRC="${BUILD_DIR}/${CONFIGURATION}-${PLATFORM_NAME}"

if [[ ! -d "$APP_FW" ]]; then
  echo "note: watchos-fix-embedded-frameworks: no Frameworks dir yet ($APP_FW)"
  exit 0
fi

need_build=0
for fw in WawonaModel WawonaUIContracts; do
  if [[ ! -f "${SRC}/${fw}.framework/${fw}" ]]; then
    need_build=1
  fi
done

if [[ "$need_build" -eq 1 ]]; then
  echo "Building WawonaModel/UIContracts for ${PLATFORM_NAME}…"
  xcodebuild \
    -project "${PROJECT_FILE_PATH}" \
    -target WawonaModel \
    -target WawonaUIContracts \
    -sdk "${PLATFORM_NAME}" \
    -configuration "${CONFIGURATION}" \
    BUILD_DIR="${BUILD_DIR}" \
    OBJROOT="${OBJROOT}" \
    SYMROOT="${SYMROOT}" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
fi

for fw in WawonaModel WawonaUIContracts; do
  src_fw="${SRC}/${fw}.framework"
  dst_fw="${APP_FW}/${fw}.framework"
  if [[ ! -d "$src_fw" ]]; then
    echo "warning: missing ${src_fw}; leave embedded ${fw} as-is"
    continue
  fi
  rm -rf "$dst_fw"
  cp -R "$src_fw" "$dst_fw"
  echo "Embedded ${fw}.framework from ${CONFIGURATION}-${PLATFORM_NAME}"
done
