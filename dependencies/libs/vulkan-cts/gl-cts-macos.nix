# OpenGL/GLES CTS for macOS (builds glcts + cts-runner from VK-GL-CTS)
{
  lib,
  pkgs,
}:

let
  common = import ./common.nix { inherit pkgs; };
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "gl-cts-macos";
  version = common.version;

  src = common.src;

  prePatch = common.prePatch;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    python3
    makeWrapper
  ];

  buildInputs = with pkgs; [
    libffi
    libpng
    zlib
  ];

  preConfigure = ''
    # Robust SDK detection using xcrun (gold standard for modern macOS)
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 1: Command Line Tools path
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 2: Legacy system path
      MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 3: Custom script
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 4: Global xcode-select
      MACOS_SDK=$(/usr/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi

    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"
  '';

  cmakeFlags = [
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DDEQP_TARGET=osx"
    "-DSELECTED_BUILD_TARGETS=${common.glTargets}"
    "-DCMAKE_OSX_SYSROOT=\${SDKROOT}"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
    (lib.cmakeFeature "DGLSLANG_INSTALL_DIR" "${pkgs.glslang}")
    (lib.cmakeFeature "DSPIRV_HEADERS_INSTALL_DIR" "${pkgs.spirv-headers}")
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ];

  postInstall = ''
    mkdir -p $out/bin $out/archive-dir
    [ -f external/openglcts/modules/glcts ] && cp -a external/openglcts/modules/glcts $out/bin/ || true
    [ -f external/openglcts/modules/cts-runner ] && cp -a external/openglcts/modules/cts-runner $out/bin/ || true
    for d in gl_cts gles2 gles3 gles31; do
      [ -d external/openglcts/modules/$d ] && cp -a external/openglcts/modules/$d $out/archive-dir/ || true
    done
  '';

  meta = {
    description = "Khronos OpenGL/GLES Conformance Tests (macOS)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
  };
})
