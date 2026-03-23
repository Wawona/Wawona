# FreeType - Font rendering library
# https://freetype.org/
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  fetchSource = common.fetchSource;
  freetypeSource = {
    source = "savannah";
    project = "freetype";
    repo = "freetype2";
    tag = "VER-2-13-2";
    sha256 = "sha256-EpkcTlXFBt1/m3ZZM+Yv0r4uBtQhUF15UKEy5PG7SE0=";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "freetype";
  version = "2.13.2";

  src = pkgs.fetchurl {
    url = "https://download.savannah.gnu.org/releases/freetype/freetype-${version}.tar.xz";
    sha256 = "sha256-EpkcTlXFBt1/m3ZZM+Yv0r4uBtQhUF15UKEy5PG7SE0=";
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    meson
    ninja
  ];

  mesonFlags = [
    "-Dharfbuzz=disabled"
    "-Dbrotli=disabled"
  ];

  buildInputs = with pkgs; [
    zlib
    bzip2
    libpng
  ];

  MACOS_SDK = "/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
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
    
    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    unset DEVELOPER_DIR
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"

    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';

  __noChroot = true;

  meta = with lib; {
    description = "A font rendering library";
    homepage = "https://freetype.org/";
    license = licenses.ftl;
    platforms = platforms.darwin;
  };
}

