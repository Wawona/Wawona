# OpenGL/GLES CTS for Android (builds glcts from VK-GL-CTS as standalone executable)
{
  lib,
  pkgs,
  stdenv ? pkgs.stdenv,
  buildPackages,
  androidSDK ? null,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs androidSDK; }),
  buildTargets ? "glcts-runner",
}:

let
  common = import ./common.nix { inherit pkgs; };
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
  };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "gl-cts-android";
  version = common.version;

  src = common.src;

  prePatch = common.prePatch;

  # No postPatch needed for symlink, it causes errors with undefined $build

  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
    python3
    makeWrapper
  ];

  buildInputs = with pkgs; [
    vulkan-headers
    vulkan-utility-libraries
    zlib
    libpng
  ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
  '';

  cmakeFlags = [
    "-DDEQP_TARGET=android"
    "-DDE_OS=DE_OS_ANDROID"
    "-DDEQP_ANDROID_EXE=OFF"
    "-DDE_ANDROID_API=${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
    "-DCMAKE_C_FLAGS=-fPIC"
    "-DCMAKE_CXX_FLAGS=-fPIC"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DDEQP_ANDROID_EXE=ON"
    "-DSELECTED_BUILD_TARGETS=${buildTargets}"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ]
  ++ androidCmake.mkCrossFlags { abi = "arm64-v8a"; }
  ++ lib.optionals androidCmake.useWrappedCrossCmake [
    (androidCmake.cmakeLibFlag { variable = "ANDROID"; libName = "android"; })
    (androidCmake.cmakeLibFlag { variable = "EGL"; libName = "EGL"; })
    (androidCmake.cmakeLibFlag { variable = "GLES1"; libName = "GLESv1_CM"; })
    (androidCmake.cmakeLibFlag { variable = "GLES2"; libName = "GLESv2"; })
    (androidCmake.cmakeLibFlag { variable = "GLES3"; libName = "GLESv3"; })
    (androidCmake.cmakeLibFlag { variable = "LOG"; libName = "log"; })
    (androidCmake.cmakeLibFlag { variable = "ZLIB"; libName = "z"; })
    (androidCmake.cmakeExactFlag { variable = "ZLIB_INCLUDE_DIR"; value = "${androidToolchain.androidNdkSysroot}/usr/include"; })
  ];

  ninjaFlags = [ buildTargets ];

  postInstall = ''
    mkdir -p $out/bin $out/archive-dir
    [ -f external/openglcts/modules/glcts ] || { echo "missing glcts"; exit 1; }
    cp -a external/openglcts/modules/glcts $out/bin/
    [ -f external/openglcts/modules/cts-runner ] || { echo "missing cts-runner"; exit 1; }
    cp -a external/openglcts/modules/cts-runner $out/bin/
    for d in gl_cts gles2 gles3 gles31; do
      [ -d external/openglcts/modules/$d ] || { echo "missing $d"; exit 1; }
      cp -a external/openglcts/modules/$d $out/archive-dir/
    done
  '';

  postFixup = ''
    mkdir -p $out/bin
    cat > $out/bin/gl-cts-android-run <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DEQP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== GL CTS Android Runner ==="
echo "Pushing GL CTS binaries to device..."
[ -f "$DEQP_DIR/bin/glcts" ] && adb push "$DEQP_DIR/bin/glcts" /data/local/tmp/glcts && adb shell chmod +x /data/local/tmp/glcts
[ -f "$DEQP_DIR/bin/cts-runner" ] && adb push "$DEQP_DIR/bin/cts-runner" /data/local/tmp/cts-runner && adb shell chmod +x /data/local/tmp/cts-runner
adb push "$DEQP_DIR/archive-dir/" /data/local/tmp/archive-dir/

echo "Running GL CTS on device..."
if [ -f "$DEQP_DIR/bin/glcts" ]; then
  adb shell "cd /data/local/tmp && ./glcts --deqp-archive-dir=./archive-dir $*"
else
  adb shell "cd /data/local/tmp && ./cts-runner --deqp-archive-dir=./archive-dir $*"
fi
SCRIPT
    chmod +x $out/bin/gl-cts-android-run
  '';

  meta = {
    description = "Khronos OpenGL/GLES Conformance Tests (Android)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
  };
})
