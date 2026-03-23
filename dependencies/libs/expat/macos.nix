{
  lib,
  pkgs,
  common,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
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
  __noChroot = true;
  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ -d expat ]; then
      cd expat
    fi
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

    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    # This is critical for targeting futuristic macOS versions where Nix stubs
    # might not have the correct symbols (like ___error, _open, etc.)
    unset DEVELOPER_DIR
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export CXXFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CXXFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
    
    cmakeFlagsArray+=("-DCMAKE_OSX_SYSROOT=$SDKROOT" "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0" "-DEXPAT_BUILD_TESTS=OFF" "-DEXPAT_BUILD_EXAMPLES=OFF")
  '';
  cmakeFlags = buildFlags;
}
