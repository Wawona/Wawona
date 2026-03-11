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
  # mbedtls source - fetch from GitHub with submodules
  src = pkgs.fetchFromGitHub {
    owner = "Mbed-TLS";
    repo = "mbedtls";
    rev = "v3.6.0";
    sha256 = "sha256-tCwAKoTvY8VCjcTPNwS3DeitflhpKHLr6ygHZDbR6wQ=";
    fetchSubmodules = true;
  };
in
pkgs.stdenv.mkDerivation {
  name = "mbedtls-ios";
  inherit src;
  patches = [ ];
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    cmake
    perl
  ];
  buildInputs = [ ];
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
    ''}

    export SDKROOT="$IOS_SDK"
    export IOS_SDK

    # Find the Developer dir associated with this SDK
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | grep -oP '.*?\.app/Contents/Developer')
    [ -z "$DEVELOPER_DIR" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    echo "Using iOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    if [ -n "''${SDKROOT:-}" ] && [ -d "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin" ]; then
      IOS_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      IOS_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    else
      IOS_CC="${buildPackages.clang}/bin/clang"
      IOS_CXX="${buildPackages.clang}/bin/clang++"
    fi
    
    IOS_ARCH="arm64"
    
    cat > ios-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
set(CMAKE_C_COMPILER "$IOS_CC")
set(CMAKE_CXX_COMPILER "$IOS_CXX")
set(CMAKE_SYSROOT "$SDKROOT")
set(CMAKE_OSX_SYSROOT "$SDKROOT")
set(CMAKE_C_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC")
set(CMAKE_CXX_FLAGS "-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -fPIC")
set(BUILD_SHARED_LIBS OFF)
set(CMAKE_AR "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar")
set(CMAKE_RANLIB "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib")
EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DENABLE_PROGRAMS=OFF"
    "-DENABLE_TESTING=OFF"
    "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"
    "-DUSE_STATIC_MBEDTLS_LIBRARY=ON"
  ];
}
