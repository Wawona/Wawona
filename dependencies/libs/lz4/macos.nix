{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # lz4 source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "lz4";
    repo = "lz4";
    rev = "v1.10.0";
    sha256 = "sha256-/dG1n59SKBaEBg72pAWltAtVmJ2cXxlFFhP+klrkTos=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "lz4-macos";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];

  MACOS_SDK = "/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  preConfigure = ''
    MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';

  # lz4 has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=ON"
    "-DBUILD_STATIC_LIBS=ON"
    "-DCMAKE_OSX_ARCHITECTURES=arm64"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
    "-DCMAKE_OSX_SYSROOT=$SDKROOT"
  ];

}
