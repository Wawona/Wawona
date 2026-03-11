{
  lib,
  pkgs,
  common,
}:

let
  fetchSource = common.fetchSource;
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
  name = "expat-macos";
  inherit src patches;
  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    apple-sdk_26
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ -d expat ]; then
      cd expat
    fi
    MACOS_SDK = "/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
    if [ ! -d "$MACOS_SDK" ]; then
       MACOS_SDK=$(${pkgs.xcode-wrapper}/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
  '';
  cmakeFlags = buildFlags ++ [
    "-DCMAKE_OSX_SYSROOT=${pkgs.apple-sdk_26}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
  ];
}
