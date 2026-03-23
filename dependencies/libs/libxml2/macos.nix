{
  lib,
  pkgs,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  autoreconfHook,
  zlib,
  libiconv,
  icu,
}:
let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
stdenv.mkDerivation rec {
  pname = "libxml2";
  version = "2.14.0";

  outputs = [
    "bin"
    "dev"
    "out"
  ]
  ++ lib.optional (stdenv.hostPlatform.isStatic && !stdenv.hostPlatform.isDarwin) "static"
  ++ lib.optionals pythonSupport [ "py" ];
  
  outputMan = "bin";

  src = fetchFromGitHub {
    owner = "GNOME";
    repo = "libxml2";
    rev = "v${version}";
    hash = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };

  # Configuration options
  pythonSupport = false; 
  icuSupport = false;
  zlibSupport = true;
  enableShared = !stdenv.hostPlatform.isStatic;
  enableStatic = !enableShared;

  strictDeps = true;
  __noChroot = true;

  nativeBuildInputs = [
    pkg-config
    autoreconfHook
  ];

  buildInputs = lib.optionals zlibSupport [ zlib ];

  propagatedBuildInputs = lib.optionals (stdenv.hostPlatform.isDarwin) [
    libiconv
  ];

  configureFlags = [
    "--exec-prefix=${placeholder "dev"}"
    (lib.enableFeature enableStatic "static")
    (lib.enableFeature enableShared "shared")
    (lib.withFeature icuSupport "icu")
    (lib.withFeature pythonSupport "python")
    (lib.withFeature false "http") 
    (lib.withFeature zlibSupport "zlib")
    (lib.withFeature false "docs")
  ];

  enableParallelBuilding = true;

  doCheck = (stdenv.hostPlatform == stdenv.buildPlatform) && stdenv.hostPlatform.libc != "musl";
  
  preCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
    export DYLD_LIBRARY_PATH="$PWD/.libs:$DYLD_LIBRARY_PATH"
  '';

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

    export CC="${pkgs.clang}/bin/clang"
    export CXX="${pkgs.clang}/bin/clang++"
    # export NIX_CFLAGS_COMPILE=""
    # export NIX_LDFLAGS=""
    # Include libiconv and zlib paths since we clear NIX_* flags
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS -I${libiconv}/include -I${zlib.dev}/include"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS -L${libiconv}/lib -L${zlib}/lib"
  '';

  postFixup = ''
    moveToOutput bin/xml2-config "$dev"
    moveToOutput lib/xml2Conf.sh "$dev"
  ''
  + lib.optionalString (enableStatic && enableShared) ''
    moveToOutput lib/libxml2.a "$static"
  '';

  meta = {
    homepage = "https://gitlab.gnome.org/GNOME/libxml2";
    description = "XML parsing library for C";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
