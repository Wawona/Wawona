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

  preConfigure = ''
    # Robust SDK detection using xcrun (gold standard for modern macOS)
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 1: Command Line Tools path
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 2: Legacy system path
      MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 3: Custom script
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      # Fallback 4: Global xcode-select
      MACOS_SDK=$(/usr/bin/xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi

    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
    
    cmakeFlagsArray+=("-DCMAKE_OSX_ARCHITECTURES=arm64" "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0" "-DCMAKE_OSX_SYSROOT=$SDKROOT")
  '';

  # zstd has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DZSTD_BUILD_PROGRAMS=OFF"
    "-DZSTD_BUILD_SHARED=ON"
    "-DZSTD_BUILD_STATIC=ON"
  ];

}
