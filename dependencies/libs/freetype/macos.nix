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
    # Fallback if preferred SDK path doesn't exist
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""
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

