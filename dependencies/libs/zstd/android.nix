{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
}:

let
  # zstd source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "v1.5.7";
    sha256 = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zstd-android";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [ ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"

    # Set sysroot for API level
    HOST_TAG="${if pkgs.stdenv.buildPlatform.isLinux then "linux-x86_64" else "darwin-x86_64"}"
    NDK_SYSROOT="${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=$NDK_SYSROOT -fPIC"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=$NDK_SYSROOT -fPIC"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=$NDK_SYSROOT"
  '';

  # zstd has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DCMAKE_POLICY_DEFAULT_CMP0126=NEW"
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_MAKE_PROGRAM=${buildPackages.ninja}/bin/ninja"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_ANDROID_PLATFORM=android-${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_ANDROID_STL_TYPE=c++_static"
    "-DZSTD_BUILD_PROGRAMS=OFF"
    "-DZSTD_BUILD_SHARED=ON"
    "-DZSTD_BUILD_STATIC=ON"
  ];

  # Patch CMakeLists.txt to fix CMake syntax issues
  postPatch = ''
    echo "=== Patching zstd CMakeLists.txt for Android ==="
    if [ -f "CMakeLists.txt" ]; then
      echo "Found CMakeLists.txt, applying patches"
      # Fix cmake_minimum_required version
      sed -i.bak 's/cmake_minimum_required(VERSION.*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt || true
      # Fix nested parentheses in if statement - CMake 3.5 doesn't support them
      sed -i.bak 's/(NOT ''${ANDROID_PLATFORM_LEVEL})/(NOT ANDROID_PLATFORM_LEVEL)/g' CMakeLists.txt || true
      sed -i.bak 's/''${ANDROID_PLATFORM_LEVEL}/ANDROID_PLATFORM_LEVEL/g' CMakeLists.txt || true
      # Remove extra parentheses around the if condition
      sed -i.bak 's/if((NOT/if(NOT/g' CMakeLists.txt || true
      echo "✓ Patched CMakeLists.txt"
    else
      echo "Warning: CMakeLists.txt not found"
    fi
  '';
}
