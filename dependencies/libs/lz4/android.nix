{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? null,
}:

let
  androidToolchainEffective = if androidToolchain != null then androidToolchain else import ../../toolchains/android.nix { inherit lib pkgs; };
  androidToolchain = androidToolchainEffective;
  # lz4 source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "lz4";
    repo = "lz4";
    rev = "v1.10.0";
    sha256 = "sha256-/dG1n59SKBaEBg72pAWltAtVmJ2cXxlFFhP+klrkTos=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "lz4-android";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export LDFLAGS="--target=${androidToolchain.androidTarget}"
  '';

  # lz4 has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_ANDROID_PLATFORM=android-${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_ANDROID_STL_TYPE=c++_static"
    "-DBUILD_SHARED_LIBS=ON"
    "-DBUILD_STATIC_LIBS=ON"
  ];
}
