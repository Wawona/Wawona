# Fontconfig - Font configuration library
# https://www.freedesktop.org/wiki/Software/fontconfig/
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  freetype = if buildModule != null 
    then buildModule.buildForMacOS "freetype" {} 
    else pkgs.freetype;
  expat = if buildModule != null
    then buildModule.buildForMacOS "expat" {}
    else pkgs.expat;
in
pkgs.stdenv.mkDerivation rec {
  pname = "fontconfig";
  version = "2.15.0";

  src = pkgs.fetchurl {
    url = "https://www.freedesktop.org/software/fontconfig/release/fontconfig-${version}.tar.xz";
    sha256 = "sha256-Y6BljQ4G4PqIYQZFK1jvBPIfWCAuoCqUw53g0zNdfA4=";
  };

  nativeBuildInputs = with pkgs; [
    pkg-config
    meson
    ninja
    gperf
    python3
    gettext
  ];

  buildInputs = [
    freetype
    expat
    pkgs.libuuid
  ];

  MACOS_SDK = "/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
  preConfigure = ''
    # Fallback if preferred SDK path doesn't exist
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

  postInstall = ''
    # Create a minimal fonts.conf
    mkdir -p $out/etc/fonts
    cat > $out/etc/fonts/fonts.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>/System/Library/Fonts</dir>
  <dir>/Library/Fonts</dir>
  <dir>~/Library/Fonts</dir>
  <cachedir>/var/cache/fontconfig</cachedir>
  <cachedir>~/.cache/fontconfig</cachedir>
</fontconfig>
EOF
  '';

  meta = with lib; {
    description = "Library for configuring and customizing font access";
    homepage = "https://www.freedesktop.org/wiki/Software/fontconfig/";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

