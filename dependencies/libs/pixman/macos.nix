# pixman for macOS - low-level pixel manipulation library
# Used by Wayland compositors and terminals for rendering
{
  lib,
  pkgs,
  common,
  buildModule ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  # Use pixman source from nixpkgs
  src = pkgs.pixman.src;
in
pkgs.stdenv.mkDerivation {
  pname = "pixman";
  version = pkgs.pixman.version;
  inherit src;
  
  # We need to access /Applications/Xcode.app for the SDK and toolchain
  __noChroot = true;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    (python3.withPackages (ps: with ps; [
      setuptools
      pip
      packaging
      mako
      pyyaml
    ]))
  ];
  
  buildInputs = [ ];
  
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

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
    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"

    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
  '';
  
  mesonFlags = [
    # Disable auto features to prevent architecture-specific checks
    "-Dauto_features=disabled"
    # Disable optional features
    "-Dopenmp=disabled"
    "-Dgtk=disabled"
    "-Dlibpng=disabled"
    "-Dtests=disabled"
    "-Ddemos=disabled"
    # Disable all architecture-specific optimizations (use C fallbacks)
    # macOS aarch64 has different ASM syntax that pixman doesn't support
    "-Dloongson-mmi=disabled"
    "-Dvmx=disabled"
    "-Darm-simd=disabled"
    "-Dmips-dspr2=disabled"
    "-Dneon=disabled"
    "-Da64-neon=disabled"
    "-Dsse2=disabled"
    "-Dssse3=disabled"
  ];
  
  meta = with lib; {
    description = "Low-level library for pixel manipulation";
    homepage = "http://pixman.org/";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
