# libxkbcommon for macOS - keyboard handling library
# https://github.com/xkbcommon/libxkbcommon
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  xkbcommonSource = {
    source = "github";
    owner = "xkbcommon";
    repo = "libxkbcommon";
    tag = "xkbcommon-1.7.0";
    sha256 = "sha256-m01ZpfEV2BTYPS5dsyYIt6h69VDd1a2j4AtJDXvn1I0=";
  };
  src = fetchSource xkbcommonSource;
  
  # Get libxml2 from buildModule if available
  libxml2 = if buildModule != null 
    then buildModule.buildForMacOS "libxml2" {} 
    else pkgs.libxml2;
in
pkgs.stdenv.mkDerivation {
  pname = "xkbcommon";
  version = "1.7.0";
  inherit src;
  
  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    python3
    bison
  ];
  
  buildInputs = [
    libxml2
    pkgs.xkeyboard_config
  ];
  
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
  
  mesonFlags = [
    "-Denable-docs=false"
    "-Denable-tools=false"
    "-Denable-x11=false"
    "-Denable-wayland=false"
    "-Dxkb-config-root=${pkgs.xkeyboard_config}/share/X11/xkb"
    "-Dx-locale-root=${pkgs.xorg.libX11}/share/X11/locale"
  ];
  
  meta = with lib; {
    description = "Library to handle keyboard descriptions";
    homepage = "https://xkbcommon.org/";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
