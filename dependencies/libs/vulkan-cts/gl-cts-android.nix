# OpenGL/GLES CTS for Android (builds glcts from VK-GL-CTS as standalone executable)
{
  lib,
  pkgs,
  stdenv ? pkgs.stdenv,
  buildPackages,
  androidSDK ? null,
  buildTargets ? "glcts-runner",
}:

let
  common = import ./common.nix { inherit pkgs; };
  androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs androidSDK; };
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
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
  '';

  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DDEQP_TARGET=android"
    "-DDE_OS=DE_OS_ANDROID"
    "-DDEQP_ANDROID_EXE=OFF"
    "-DDE_ANDROID_API=${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_ANDROID_API=${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    (lib.cmakeFeature "CMAKE_C_FLAGS" "--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}")
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}")
    "-DCMAKE_SHARED_LINKER_FLAGS=-L${androidToolchain.androidNdkAbiLibDir}"
    "-DCMAKE_MODULE_LINKER_FLAGS=-L${androidToolchain.androidNdkAbiLibDir}"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DDEQP_ANDROID_EXE=ON"
    "-DSELECTED_BUILD_TARGETS=${buildTargets}"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ];

  ninjaFlags = [ buildTargets ];

  postInstall = ''
    mkdir -p $out/bin $out/archive-dir
    [ -f external/openglcts/modules/glcts ] && cp -a external/openglcts/modules/glcts $out/bin/ || true
    [ -f external/openglcts/modules/cts-runner ] && cp -a external/openglcts/modules/cts-runner $out/bin/ || true
    for d in gl_cts gles2 gles3 gles31; do
      [ -d external/openglcts/modules/$d ] && cp -a external/openglcts/modules/$d $out/archive-dir/ || true
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
adb push "$DEQP_DIR/archive-dir/" /data/local/tmp/archive-dir/ 2>/dev/null || true

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
