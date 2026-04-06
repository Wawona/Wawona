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
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
  };
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
  '';
  cmakeFlags = [
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
  ]
  ++ androidCmake.mkCrossFlags {
    abi = "arm64-v8a";
    useAndroidToolchainFile = true;
  }
  ++ [
    "-DEXPAT_SHARED_LIBS=OFF"
    "-DEXPAT_BUILD_TOOLS=OFF"
    "-DEXPAT_BUILD_EXAMPLES=OFF"
    "-DEXPAT_BUILD_TESTS=OFF"
  ]
  ++ buildFlags;
}
