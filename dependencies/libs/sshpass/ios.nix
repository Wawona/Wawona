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
  # sshpass source - fetch from SourceForge mirror via GitHub
  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
in
pkgs.stdenv.mkDerivation {
  name = "sshpass-ios";
  version = "1.10";
  
  inherit src;
  
  # No patches needed for sshpass
  patches = [ ];
  
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
  ];
  
  buildInputs = [ ];

  preConfigure = ''
    # Robust SDK detection
    if [ "$simulator" = "true" ]; then
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
    else
      IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
      if [ ! -d "$IOS_SDK" ]; then
        # Fallback 1: Default location
        XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)
        IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
      fi
    fi

    if [ ! -d "$IOS_SDK" ]; then
      echo "ERROR: iOS SDK not found. Build cannot proceed." >&2
      exit 1
    fi
    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
    [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    # Determine architecture
    if [ "${if simulator then "true" else "false"}" = "true" ]; then
      SIMULATOR_ARCH="arm64"
      if [ "$(uname -m)" = "x86_64" ]; then
        SIMULATOR_ARCH="x86_64"
      fi
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=${iosToolchain.deploymentTarget} -fPIC"
      export CXXFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=${iosToolchain.deploymentTarget} -fPIC"
      export LDFLAGS="-arch $SIMULATOR_ARCH -isysroot $SDKROOT -mios-simulator-version-min=${iosToolchain.deploymentTarget}"
    else
      export CC="$IOS_CC"
      export CXX="$IOS_CXX"
      export CFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=${iosToolchain.deploymentTarget} -fPIC"
      export CXXFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=${iosToolchain.deploymentTarget} -fPIC"
      export LDFLAGS="-arch arm64 -isysroot $SDKROOT -miphoneos-version-min=${iosToolchain.deploymentTarget}"
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    export ac_cv_func_malloc_0_nonnull=yes
    export ac_cv_func_realloc_0_nonnull=yes
    ./configure --prefix=$out --host=arm-apple-darwin
    runHook postConfigure
  '';

  meta = with lib; {
    description = "Non-interactive SSH password authentication";
    homepage = "https://sourceforge.net/projects/sshpass/";
    license = licenses.gpl2Plus;
    platforms = platforms.darwin;
  };
}
