# utf8proc - Unicode processing library
# https://github.com/JuliaStrings/utf8proc
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  utf8procSource = {
    source = "github";
    owner = "JuliaStrings";
    repo = "utf8proc";
    tag = "v2.9.0";
    sha256 = "sha256-Sgh8vTbclUV+lFZdR29PtNUy8F+9L/OAXk647B+l2mg=";
  };
  src = fetchSource utf8procSource;
in
pkgs.stdenv.mkDerivation {
  pname = "utf8proc";
  version = "2.9.0";
  inherit src;

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
  ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=ON"
    "-DUTF8PROC_ENABLE_TESTING=OFF"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
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

  meta = with lib; {
    description = "Clean C library for processing UTF-8 Unicode data";
    homepage = "https://github.com/JuliaStrings/utf8proc";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}

