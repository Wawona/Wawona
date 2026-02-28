{
  lib,
  pkgs,
  buildPackages,
  buildModule,
  buildTargets ? "deqp-vk",
}:

let
  common = import ./common.nix { inherit pkgs; };
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  kosmickrisp = buildModule.buildForIOS "kosmickrisp" { };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "vulkan-cts-ios";
  version = common.version;

  src = common.src;
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;

  prePatch = common.prePatch + ''
    # vksCacheBuilder.cpp uses system() which is unavailable on iOS
    substituteInPlace external/vulkancts/vkscserver/vksCacheBuilder.cpp \
      --replace 'int returnValue     = system(command.c_str());' \
      'int returnValue;
#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
        returnValue = -1;  /* system() unavailable on iOS */
#else
        returnValue = system(command.c_str());
#endif'

    # tcuIOSPlatform.mm needs OpenGL ES headers for GL_RENDERBUFFER etc.
    substituteInPlace framework/platform/ios/tcuIOSPlatform.mm \
      --replace '#include "tcuIOSPlatform.hh"' \
      '#include "tcuIOSPlatform.hh"
#include <OpenGLES/ES2/gl.h>'

    # ContextFactory::createContext signature: add sharedContext param (3rd arg)
    substituteInPlace framework/platform/ios/tcuIOSPlatform.hh \
      --replace 'createContext(const glu::RenderConfig &config, const tcu::CommandLine &cmdLine) const' \
      'createContext(const glu::RenderConfig &config, const tcu::CommandLine &cmdLine, const glu::RenderContext *sharedContext) const'
    substituteInPlace framework/platform/ios/tcuIOSPlatform.mm \
      --replace 'const tcu::CommandLine &) const' \
      'const tcu::CommandLine &, const glu::RenderContext *) const'
  '';

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
  ];

  buildInputs = [
    kosmickrisp
    pkgs.vulkan-headers
    pkgs.vulkan-utility-libraries
    pkgs.zlib
    pkgs.libpng
    pkgs.libffi
  ];

  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$PATH:$DEVELOPER_DIR/usr/bin"
        
        # Determine if we should use Simulator or Device SDK. 
        # Default to Simulator for CTS unless specified otherwise.
        export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
        
        # Ensure it exists
        if [ ! -d "$SDKROOT" ]; then
           # Trigger the auto-provisioner
           SDKROOT=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk)
        fi
      fi
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""

    SIMULATOR_ARCH="arm64"
    if [ "$(uname -m)" = "x86_64" ]; then
      SIMULATOR_ARCH="x86_64"
    fi

    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi

    cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES $SIMULATOR_ARCH)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(CMAKE_OSX_SYSROOT "$SDKROOT")
    set(CMAKE_C_FLAGS "-mios-simulator-version-min=15.0 -DGLES_SILENCE_DEPRECATION")
    set(CMAKE_CXX_FLAGS "-mios-simulator-version-min=15.0 -DGLES_SILENCE_DEPRECATION")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    EOF
  '';

  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DDEQP_TARGET=ios"
    "-DDE_OS=DE_OS_IOS"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DSELECTED_BUILD_TARGETS=${buildTargets}"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ];

  postInstall = ''
    mkdir -p $out/Applications $out/bin $out/archive-dir
    if [ -d deqp.app ]; then
      cp -a deqp.app $out/Applications/
    else
      [ -f external/vulkancts/modules/vulkan/deqp-vk ] && cp -a external/vulkancts/modules/vulkan/deqp-vk $out/bin/ || true
      [ -d external/vulkancts/modules/vulkan/vulkan ] && cp -a external/vulkancts/modules/vulkan/vulkan $out/archive-dir/ || true
      [ -d external/vulkancts/modules/vulkan/vk-default ] && cp -a external/vulkancts/modules/vulkan/vk-default $out/ || true
    fi
  '';

  postFixup = ''
    mkdir -p $out/bin
    cat > $out/bin/vulkan-cts-ios-run <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
CTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$CTS_DIR/Applications/deqp.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: deqp.app not found at $APP_PATH"
  exit 1
fi

SIM_NAME="Vulkan CTS iOS Simulator"
DEV_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" | grep -v "unavailable" | awk '{print $NF}' | tail -1)
if [ -z "$RUNTIME" ]; then
  echo "Error: No iOS runtime found. Install Xcode and an iOS simulator runtime."
  exit 1
fi

SIM_UDID=$(xcrun simctl list devices 2>/dev/null | grep "$SIM_NAME" | grep -v "unavailable" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)
if [ -z "$SIM_UDID" ]; then
  echo "Creating simulator '$SIM_NAME'..."
  SIM_UDID=$(xcrun simctl create "$SIM_NAME" "$DEV_TYPE" "$RUNTIME")
fi

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || true
echo "Installing Vulkan CTS (deqp.app) to simulator..."
xcrun simctl install "$SIM_UDID" "$APP_PATH"
echo "Launching Vulkan CTS..."
xcrun simctl launch "$SIM_UDID" com.drawelements.deqp "$@"
SCRIPT
    chmod +x $out/bin/vulkan-cts-ios-run
  '';

  meta = {
    description = "Khronos Vulkan Conformance Tests (iOS)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
  };
})
