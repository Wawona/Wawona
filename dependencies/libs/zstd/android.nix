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
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
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
  '';

  # zstd has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DCMAKE_POLICY_DEFAULT_CMP0126=NEW"
    "-DCMAKE_MAKE_PROGRAM=${buildPackages.ninja}/bin/ninja"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_ASM_COMPILER=${androidToolchain.androidCC}"
    "-DZSTD_BUILD_PROGRAMS=OFF"
    "-DZSTD_BUILD_SHARED=ON"
    "-DZSTD_BUILD_STATIC=ON"
  ]
  ++ androidCmake.mkCrossFlags { abi = "arm64-v8a"; }
  ++ lib.optionals (!androidCmake.useWrappedCrossCmake) [
    "-DCMAKE_ANDROID_STL_TYPE=c++_static"
  ];

  # Patch CMakeLists.txt to fix CMake syntax issues
  postPatch = ''
    echo "=== Patching zstd CMakeLists.txt for Android ==="
    if [ -f "CMakeLists.txt" ]; then
      echo "Found CMakeLists.txt, applying patches"
      # Fix cmake_minimum_required version
      sed -i.bak 's/cmake_minimum_required(VERSION.*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt
      # Fix nested parentheses in if statement - CMake 3.5 doesn't support them
      sed -i.bak 's/(NOT ''${ANDROID_PLATFORM_LEVEL})/(NOT ANDROID_PLATFORM_LEVEL)/g' CMakeLists.txt
      sed -i.bak 's/''${ANDROID_PLATFORM_LEVEL}/ANDROID_PLATFORM_LEVEL/g' CMakeLists.txt
      # Remove extra parentheses around the if condition
      sed -i.bak 's/if((NOT/if(NOT/g' CMakeLists.txt
      echo "✓ Patched CMakeLists.txt"
    else
      echo "ERROR: CMakeLists.txt not found in zstd sourceRoot"
      exit 1
    fi
  '';
}
