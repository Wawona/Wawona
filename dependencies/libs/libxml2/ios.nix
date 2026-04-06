{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
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
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iOS Simulator
      IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: via ensureIosSimSDK script
        IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
      fi
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 2: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
      fi
    '' else ''
      # Robust SDK detection for iOS Device
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    # Use sed instead of grep -oP for macOS compatibility
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"
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
