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
  isVisionOS = iosToolchain.isVisionOSToolchain or false;
  isTVOS = iosToolchain.isTVOSToolchain or false;
  mobileMin = iosToolchain.deploymentTarget;
  platform =
    if isVisionOS then "visionos"
    else if isTVOS then "tvos"
    else "ios";
  sdkName =
    if isVisionOS then (if simulator then "xrsimulator" else "xros")
    else if isTVOS then (if simulator then "appletvsimulator" else "appletvos")
    else (if simulator then "iphonesimulator" else "iphoneos");
  fallbackPlatformDir =
    if isVisionOS then (if simulator then "XRSimulator" else "XROS")
    else if isTVOS then (if simulator then "AppleTVSimulator" else "AppleTVOS")
    else (if simulator then "iPhoneSimulator" else "iPhoneOS");
  targetFlag =
    if isVisionOS then
      "-target arm64-apple-xros${if simulator then "${mobileMin}-simulator" else mobileMin}"
    else if isTVOS then
      "-target arm64-apple-tvos${mobileMin}${if simulator then "-simulator" else ""}"
    else
      "";
  deploymentFlag =
    if isVisionOS then
      ""
    else if isTVOS then
      (if simulator then "-mtvos-simulator-version-min=${mobileMin}" else "-mtvos-version-min=${mobileMin}")
    else
      "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${mobileMin}";
  src = pkgs.fetchurl {
    url = "https://zlib.net/zlib-1.3.1.tar.gz";
    sha256 = "08yzf8xz0q7vxs8mnn74xmpxsrs6wy0aan55lpmpriysvyvv54ws";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zlib-ios";
  inherit src;
  patches = [ ];

  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [ ];
  buildInputs = [ ];
  preConfigure = ''
    # Strip Nix stdenv's DEVELOPER_DIR to bypass any store fallbacks
    unset DEVELOPER_DIR

    # Robust SDK detection for Apple mobile SDKs.
    IOS_SDK=$(xcrun --sdk ${sdkName} --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$IOS_SDK" ] && [ "${sdkName}" = "iphonesimulator" ]; then
      # Historical fallback helper for iOS simulator SDK lookup.
      IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
    fi
    if [ ! -d "$IOS_SDK" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
      IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/${fallbackPlatformDir}.platform/Developer/SDKs/${fallbackPlatformDir}.sdk"
    fi

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
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

    echo "Using SDK (${platform}): $IOS_SDK"
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
    export CFLAGS="-arch arm64 ${targetFlag} -isysroot $SDKROOT ${deploymentFlag} -fPIC"
    export CXXFLAGS="-arch arm64 ${targetFlag} -isysroot $SDKROOT ${deploymentFlag} -fPIC"
    export LDFLAGS="-arch arm64 ${targetFlag} -isysroot $SDKROOT ${deploymentFlag}"
    # Unset SDKROOT so it doesn't leak into host-side tool builds
    unset SDKROOT
    if ! ./configure --prefix=$out --static; then
      if [ -f config.log ]; then
        echo "===== zlib configure config.log ====="
        cat config.log
        echo "===== end config.log ====="
      fi
      exit 1
    fi
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
