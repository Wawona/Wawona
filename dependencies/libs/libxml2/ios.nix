{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  fetchSource = common.fetchSource;
  libxml2Source = {
    source = "gitlab-gnome";
    owner = "GNOME";
    repo = "libxml2";
    rev = "v2.14.0";
    sha256 = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };
  src = fetchSource libxml2Source;
  buildFlags =
    [ "--without-python" ]
    ++ lib.optionals (iosToolchain.isVisionOSToolchain or false) [
      "--disable-shared"
      "--enable-static"
    ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libxml2-ios";
  inherit src patches;
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
  ];
  buildInputs = [ ];
  # Keep everything in one shell: stdenv's runHook preConfigure can split work such
  # that visionOS Autoconf cache exports do not apply to ./configure.
  preConfigure = "true";
  configurePhase = ''
    runHook preConfigure

    unset DEVELOPER_DIR
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; }}

    if [ ! -f ./configure ]; then
      autoreconf -fi || autogen.sh || true
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"
    # visionOS: use a single clang `-target` that matches the XROS/XRSimulator SDK.
    if [[ "''${APPLE_SDK_NAME:-}" == xros ]] || [[ "''${APPLE_SDK_NAME:-}" == xrsimulator ]]; then
      # `-target arm64-apple-xros26.0(-simulator)?` already pins the OS; Apple's clang
      # rejects `-mvisionos(-simulator)?-version-min=*` together with that triple (unknown argument).
      export CFLAGS="-target $APPLE_LINKER_TARGET -isysroot $SDKROOT -fPIC"
      export CXXFLAGS="-target $APPLE_LINKER_TARGET -isysroot $SDKROOT -fPIC"
      export LDFLAGS="-target $APPLE_LINKER_TARGET -isysroot $SDKROOT"
    else
      export CFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"
      export CXXFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"
      export LDFLAGS="-arch $IOS_ARCH -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"
    fi

    echo "libxml2: SDK=$SDKROOT $APPLE_DEPLOYMENT_FLAG APPLE_SDK_NAME=''${APPLE_SDK_NAME:-}"

    unset SDKROOT
    ./configure --prefix=$out --host=arm-apple-darwin ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    }
    runHook postConfigure
  '';
  configureFlags = buildFlags;
}
