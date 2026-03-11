{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation {
  name = "openssl-ios";
  src = pkgs.fetchurl {
    url = "https://www.openssl.org/source/openssl-3.3.1.tar.gz";
    sha256 = "sha256-d3zVlihMiDN1oqehG/XSeG/FQTJV76sgxQ1v/m0CC34=";
  };

  nativeBuildInputs = with buildPackages; [ perl ];
  buildInputs = [ ];

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;

  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    ${if simulator then ''
      # Ensure the iOS Simulator SDK is downloaded if missing and get its path.
      IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || {
        echo "Error: Failed to ensure iOS Simulator SDK."
        exit 1
      }
    '' else ''
      # For device, find the latest iPhoneOS SDK path.
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode) || {
        echo "Error: Xcode not found."
        exit 1
      }
      IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      export MACOS_SDK_PATH="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    ''}

    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    if [ -z "$MACOS_SDK_PATH" ]; then
      export MACOS_SDK_PATH="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    fi
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"

    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    export CC="$IOS_CC"
    export CFLAGS="-arch arm64 -target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC"
    export LDFLAGS="-arch arm64 -target arm64-apple-ios26.0${if simulator then "-simulator" else ""} -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    ./Configure ${if simulator then "iossimulator-xcrun" else "ios64-cross"} no-shared no-dso --prefix=$out --openssldir=$out/etc/ssl
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install_sw install_ssldirs
    runHook postInstall
  '';
}
