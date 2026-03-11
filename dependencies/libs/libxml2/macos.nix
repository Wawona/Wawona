{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  autoreconfHook,
  zlib,
  libiconv,
  icu,
}:

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

  preConfigure = ''
    MACOS_SDK="/System/Library/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    export SDKROOT="$MACOS_SDK"
    export MACOSX_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 -fPIC $CFLAGS"
    export LDFLAGS="-isysroot $SDKROOT -mmacosx-version-min=26.0 $LDFLAGS"
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
