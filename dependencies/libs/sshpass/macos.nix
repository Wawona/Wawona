{
  lib,
  pkgs,
  common,
}:

let
  # sshpass source - fetch from SourceForge mirror via GitHub
  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation {
  name = "sshpass-macos";
  version = "1.10";
  
  inherit src;
  
  # No patches needed for sshpass
  patches = [ ];
  
  nativeBuildInputs = with pkgs; [
    autoconf
    automake
  ];
  
  buildInputs = [ ];

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

  meta = with lib; {
    description = "Non-interactive SSH password authentication";
    homepage = "https://sourceforge.net/projects/sshpass/";
    license = licenses.gpl2Plus;
    platforms = platforms.darwin;
  };
}

