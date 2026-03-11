{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  fetchSource = common.fetchSource;
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  libxml2Source = {
    source = "gitlab-gnome";
    owner = "GNOME";
    repo = "libxml2";
    rev = "v2.14.0";
    sha256 = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };
  src = fetchSource libxml2Source;
  buildFlags = [ "--without-python" ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libxml2-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export XCODE_APP
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
        export SDKROOT="$DEVELOPER_DIR/Platforms/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.platform/Developer/SDKs/${if simulator then "iPhoneSimulator" else "iPhoneOS"}.sdk"
        export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
      fi
    fi
    if [ ! -f ./configure ]; then
      autoreconf -fi || autogen.sh || true
    fi
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
  '';
  configurePhase = ''
    runHook preConfigure
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    ./configure --prefix=$out --host=arm-apple-darwin ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    }
    runHook postConfigure
  '';
  configureFlags = buildFlags;
}
