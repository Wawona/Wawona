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
  xcodeUtils = iosToolchain;
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
  name = "mbedtls-ipados";
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
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    
    cat > ipados-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
set(CMAKE_OSX_DEPLOYMENT_TARGET ${xcodeUtils.deploymentTarget})
set(CMAKE_C_COMPILER "$XCODE_CLANG")
set(CMAKE_CXX_COMPILER "$XCODE_CLANGXX")
set(CMAKE_C_COMPILER_TARGET "$APPLE_LINKER_TARGET")
set(CMAKE_CXX_COMPILER_TARGET "$APPLE_LINKER_TARGET")
set(CMAKE_SYSROOT "$SDKROOT")
set(CMAKE_OSX_SYSROOT "$SDKROOT")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC -Wno-unknown-warning-option -Wno-unterminated-string-initialization")
set(CMAKE_CXX_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC -Wno-unknown-warning-option -Wno-unterminated-string-initialization")
set(CMAKE_ASM_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
set(CMAKE_EXE_LINKER_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
set(CMAKE_SHARED_LINKER_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
set(BUILD_SHARED_LIBS OFF)
set(CMAKE_AR "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar")
set(CMAKE_RANLIB "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ranlib")
EOF

    # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
    unset SDKROOT
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ipados-toolchain.cmake"
    "-DENABLE_PROGRAMS=OFF"
    "-DENABLE_TESTING=OFF"
    "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"
    "-DUSE_STATIC_MBEDTLS_LIBRARY=ON"
    "-DMBEDTLS_FATAL_WARNINGS=OFF"
  ];
}
