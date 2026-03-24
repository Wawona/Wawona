{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? null,
  ...
}:

let
  androidToolchainEffective = if androidToolchain != null then androidToolchain else import ../../toolchains/android.nix { inherit lib pkgs; };
  androidToolchain = androidToolchainEffective;
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  expatSource = {
    source = "github";
    owner = "libexpat";
    repo = "libexpat";
    tag = "R_2_7_3";
    sha256 = "sha256-dDxnAJsj515vr9+j2Uqa9E+bB+teIBfsnrexppBtdXg=";
  };
  src = fetchSource expatSource;
  buildFlags = [ ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "expat-android";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ -d expat ]; then
      cd expat
    fi
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
    export LDFLAGS="--target=${androidToolchain.androidTarget}"
  '';
  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_ANDROID_PLATFORM=android-${toString androidToolchain.androidNdkApiLevel}"
    "-DCMAKE_C_FLAGS=--target=${androidToolchain.androidTarget}"
    "-DCMAKE_CXX_FLAGS=--target=${androidToolchain.androidTarget}"
    "-DEXPAT_SHARED_LIBS=OFF"
    "-DEXPAT_BUILD_TOOLS=OFF"
    "-DEXPAT_BUILD_EXAMPLES=OFF"
    "-DEXPAT_BUILD_TESTS=OFF"
  ]
  ++ buildFlags;
}
