{
  lib,
  pkgs,
  stdenv ? pkgs.stdenv,
  buildPackages,
  androidSDK ? null,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs androidSDK; }),
  buildTargets ? "deqp",
}:

let
  common = import ./common.nix { inherit pkgs; };
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "vulkan-cts-android";
  version = common.version;

  src = common.src;

  prePatch = common.prePatch;

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
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC -Wno-deprecated-declarations ${androidToolchain.androidNdkCflags}"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC -Wno-deprecated-declarations ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
    cmakeFlagsArray+=(
      "-DCMAKE_C_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC -Wno-deprecated-declarations ${androidToolchain.androidNdkCflags}"
      "-DCMAKE_CXX_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC -Wno-deprecated-declarations ${androidToolchain.androidNdkCflags}"
    )
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
    "-DCMAKE_SHARED_LINKER_FLAGS=-L${androidToolchain.androidNdkAbiLibDir}"
    "-DCMAKE_MODULE_LINKER_FLAGS=-L${androidToolchain.androidNdkAbiLibDir}"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DSELECTED_BUILD_TARGETS=${buildTargets}"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ];

  # Only build the selected targets to avoid linking errors in unnecessary GL components
  ninjaFlags = [ buildTargets ];

  postInstall = ''
    mkdir -p $out/bin $out/archive-dir
    [ -f external/vulkancts/modules/vulkan/deqp-vk ] && cp -a external/vulkancts/modules/vulkan/deqp-vk $out/bin/ || true
    [ -d external/vulkancts/modules/vulkan/vulkan ] && cp -a external/vulkancts/modules/vulkan/vulkan $out/archive-dir/ || true
    [ -d external/vulkancts/modules/vulkan/vk-default ] && cp -a external/vulkancts/modules/vulkan/vk-default $out/ || true
  '';

  postFixup = ''
    mkdir -p $out/bin
    cat > $out/bin/vulkan-cts-android-run <<'SCRIPT'
    #!/usr/bin/env bash
    set -euo pipefail
    DEQP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

    echo "=== Vulkan CTS Android Runner ==="
    echo "Pushing deqp-vk to device..."
    adb push "$DEQP_DIR/bin/deqp-vk" /data/local/tmp/deqp-vk
    adb push "$DEQP_DIR/archive-dir/" /data/local/tmp/archive-dir/
    adb shell chmod +x /data/local/tmp/deqp-vk

    echo "Running deqp-vk on device..."
    adb shell "cd /data/local/tmp && ./deqp-vk --deqp-archive-dir=./archive-dir $*"
    SCRIPT
    chmod +x $out/bin/vulkan-cts-android-run
  '';

  meta = {
    description = "Khronos Vulkan Conformance Tests (Android)";
    homepage = "https://github.com/KhronosGroup/VK-GL-CTS";
    license = lib.licenses.asl20;
  };
})
