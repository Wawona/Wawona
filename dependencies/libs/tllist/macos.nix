# tllist - Header-only typed linked list library (used by foot terminal)
# https://codeberg.org/dnkl/tllist
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  tllistSource = {
    source = "codeberg";
    owner = "dnkl";
    repo = "tllist";
    tag = "1.1.0";
    sha256 = "sha256-4WW0jGavdFO3LX9wtMPzz3Z1APCPgUQOktpmwAM0SQw=";
  };
  src = fetchSource tllistSource;
in
pkgs.stdenv.mkDerivation {
  pname = "tllist";
  version = "1.1.0";
  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
  ];

  __noChroot = true;

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
    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""
  '';

  # tllist is header-only, no special meson flags needed
  mesonFlags = [];

  meta = with lib; {
    description = "Typed linked list C header file only library";
    homepage = "https://codeberg.org/dnkl/tllist";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

