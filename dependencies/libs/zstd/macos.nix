{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # zstd source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "v1.5.7";
    sha256 = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zstd-macos";
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

  # zstd has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DZSTD_BUILD_PROGRAMS=OFF"
    "-DZSTD_BUILD_SHARED=ON"
    "-DZSTD_BUILD_STATIC=ON"
    "-DCMAKE_OSX_ARCHITECTURES=arm64"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0"
    "-DCMAKE_OSX_SYSROOT=$SDKROOT"
  ];

}
