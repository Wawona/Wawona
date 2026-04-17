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
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
        # Robust SDK detection
        if ${if simulator then "true" else "false"}; then
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
        IOS_ARCH="${if simulator then pkgs.stdenv.hostPlatform.darwinArch else "arm64"}"
        IOS_TARGET="${if simulator then "${pkgs.stdenv.hostPlatform.darwinArch}-apple-ios${iosToolchain.deploymentTarget}-simulator" else "arm64-apple-ios${iosToolchain.deploymentTarget}"}"
        cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
    set(CMAKE_OSX_DEPLOYMENT_TARGET ${iosToolchain.deploymentTarget})
    set(CMAKE_C_COMPILER "$IOS_CC")
    set(CMAKE_CXX_COMPILER "$IOS_CXX")
    set(CMAKE_C_COMPILER_TARGET "$IOS_TARGET")
    set(CMAKE_CXX_COMPILER_TARGET "$IOS_TARGET")
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
    set(CMAKE_C_FLAGS "-arch $IOS_ARCH -target $IOS_TARGET -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}")
    set(CMAKE_CXX_FLAGS "-arch $IOS_ARCH -target $IOS_TARGET -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}")
    set(CMAKE_ASM_FLAGS "-arch $IOS_ARCH -target $IOS_TARGET -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}")
    set(CMAKE_EXE_LINKER_FLAGS "-arch $IOS_ARCH -target $IOS_TARGET -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}")
    set(CMAKE_SHARED_LINKER_FLAGS "-arch $IOS_ARCH -target $IOS_TARGET -isysroot $SDKROOT -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=${iosToolchain.deploymentTarget}")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(CMAKE_OSX_SYSROOT "$SDKROOT")
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
