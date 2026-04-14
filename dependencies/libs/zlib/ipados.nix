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
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  src = pkgs.fetchurl {
    url = "https://zlib.net/zlib-1.3.1.tar.gz";
    sha256 = "08yzf8xz0q7vxs8mnn74xmpxsrs6wy0aan55lpmpriysvyvv54ws";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zlib-ipados";
  inherit src;
  patches = [ ];

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [ ];
  buildInputs = [ ];
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Robust SDK detection for iPadOS Simulator
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
      # Robust SDK detection for iPadOS Device
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    ''}

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iPadOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    if [ -z "$MACOS_SDK_PATH" ]; then
      export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iPadOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
  '';
  configurePhase = ''
    runHook preConfigure
    # zlib uses configure script
    export CC="$IOS_CC"
    export CXX="$IOS_CXX"
    export CFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch arm64 -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    ./configure --prefix=$out --static
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    make
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install
    runHook postInstall
  '';
}
