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
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
  };
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
    "-DSELECTED_BUILD_TARGETS=${buildTargets}"
    (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_SHADERC" "${common.sources.shaderc-src}")
  ]
  ++ androidCmake.mkCrossFlags { abi = "arm64-v8a"; }
  ++ lib.optionals androidCmake.useWrappedCrossCmake [
    # CMake won't auto-discover Android system GL libs in Linux cross mode.
    (androidCmake.cmakeLibFlag { variable = "ANDROID"; libName = "android"; })
    (androidCmake.cmakeLibFlag { variable = "EGL"; libName = "EGL"; })
    (androidCmake.cmakeLibFlag { variable = "GLES1"; libName = "GLESv1_CM"; })
    (androidCmake.cmakeLibFlag { variable = "GLES2"; libName = "GLESv2"; })
    (androidCmake.cmakeLibFlag { variable = "GLES3"; libName = "GLESv3"; })
    (androidCmake.cmakeLibFlag { variable = "LOG"; libName = "log"; })
    (androidCmake.cmakeLibFlag { variable = "ZLIB"; libName = "z"; })
    (androidCmake.cmakeExactFlag { variable = "ZLIB_INCLUDE_DIR"; value = "${androidToolchain.androidNdkSysroot}/usr/include"; })
  ];

  # Only build the selected targets to avoid linking errors in unnecessary GL components
  ninjaFlags = [ buildTargets ];

  postInstall = ''
    mkdir -p $out/bin $out/archive-dir
    deqp_bin=""
    for candidate in \
      $out/bin/deqp-vk \
      $out/bin/deqp \
      $out/bin/deqp-vksc \
      $out/bin/executor \
      external/vulkancts/modules/vulkan/deqp-vk \
      external/vulkancts/modules/vulkan/deqp \
      external/vulkancts/modules/vulkan/deqp-vksc \
      executor/executor \
      build/external/vulkancts/modules/vulkan/deqp-vk \
      build/external/vulkancts/modules/vulkan/deqp \
      build/external/vulkancts/modules/vulkan/deqp-vksc \
      build/executor/executor
    do
      if [ -f "$candidate" ]; then
        deqp_bin="$candidate"
        break
      fi
    done
    if [ -z "$deqp_bin" ]; then
      deqp_bin="$(find . -type f \( -path "*/modules/vulkan/deqp-vk" -o -path "*/modules/vulkan/deqp" -o -path "*/modules/vulkan/deqp-vksc" -o -path "*/executor/executor" \) | sort | head -n1)"
    fi
    if [ -z "$deqp_bin" ]; then
      echo "warning: missing deqp-vk/deqp/deqp-vksc/executor; skipping binary install"
    else
      if [ "$deqp_bin" != "$out/bin/deqp-vk" ]; then
        cp -a "$deqp_bin" "$out/bin/deqp-vk"
      fi
    fi
    [ -d external/vulkancts/modules/vulkan/vulkan ] || { echo "missing vulkan archive-dir"; exit 1; }
    cp -a external/vulkancts/modules/vulkan/vulkan $out/archive-dir/
    [ -d external/vulkancts/modules/vulkan/vk-default ] || { echo "missing vk-default"; exit 1; }
    cp -a external/vulkancts/modules/vulkan/vk-default $out/
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
