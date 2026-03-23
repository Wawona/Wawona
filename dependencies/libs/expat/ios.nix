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
  expatSource = {
    source = "github";
    owner = "libexpat";
    repo = "libexpat";
    tag = "R_2_7_3";
    sha256 = "sha256-dDxnAJsj515vr9+j2Uqa9E+bB+teIBfsnrexppBtdXg=";
  };
  src = fetchSource expatSource;
  buildFlags = [ ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "expat-ios";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
        # Robust SDK detection
        if [ "$simulator" = "true" ]; then
          IOS_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)
          if [ ! -d "$IOS_SDK" ]; then
            IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || true
          fi
          if [ ! -d "$IOS_SDK" ]; then
            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
            IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
          fi
        else
          IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
          if [ ! -d "$IOS_SDK" ]; then
            XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
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
        if [ -d expat ]; then
          cd expat
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
        cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_C_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
    set(CMAKE_CXX_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0")
    set(CMAKE_SYSROOT "$SDKROOT")
    EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DEXPAT_SHARED_LIBS=OFF"
    "-DEXPAT_BUILD_TOOLS=OFF"
    "-DEXPAT_BUILD_TESTS=OFF"
  ]
  ++ buildFlags;
}
