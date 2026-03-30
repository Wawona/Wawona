{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
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
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
    # Multi-word -D values must live in cmakeFlagsArray; stdenv splits cmakeFlags on spaces.
    _ANDROID_LINK_FLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
    cmakeFlagsArray+=(
      "-DCMAKE_C_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
      "-DCMAKE_CXX_FLAGS:STRING=--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
      "-DCMAKE_EXE_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
      "-DCMAKE_SHARED_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
      "-DCMAKE_MODULE_LINKER_FLAGS:STRING=$_ANDROID_LINK_FLAGS"
    )
  '';
  cmakeFlags = [
    "-DCMAKE_SYSTEM_NAME=Android"
    "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a"
    "-DCMAKE_ANDROID_NDK=${androidToolchain.androidndkRoot}"
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
    "-DCMAKE_ANDROID_PLATFORM=android-${toString androidToolchain.androidNdkApiLevel}"
    "-DEXPAT_SHARED_LIBS=OFF"
    "-DEXPAT_BUILD_TOOLS=OFF"
    "-DEXPAT_BUILD_EXAMPLES=OFF"
    "-DEXPAT_BUILD_TESTS=OFF"
  ]
  ++ buildFlags;
}
