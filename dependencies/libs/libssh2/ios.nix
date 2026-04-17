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
  isVisionOS = iosToolchain.isVisionOSToolchain or false;
  isTVOS = iosToolchain.isTVOSToolchain or false;
  mobileMinVersion =
    if isVisionOS then "26.0"
    else if isTVOS then "17.0"
    else xcodeUtils.deploymentTarget;
  # libssh2 source
  src = pkgs.fetchFromGitHub {
    owner = "libssh2";
    repo = "libssh2";
    rev = "libssh2-1.11.1";
    sha256 = "sha256-yz97oqqN+NJTDL/HPJe3niFynbR8QXHuuiKr+uuKJtw=";
  };
  # Use OpenSSL instead of mbedTLS: mbedTLS bundled entropy source lacks iOS
  # support (NULL callback → crash in mbedtls_ctr_drbg_reseed_internal during
  # SSH handshake). OpenSSL uses SecRandomCopyBytes on iOS which works correctly.
  openssl-ios = buildModule.buildForIOS "openssl" { inherit simulator; };
in
pkgs.stdenv.mkDerivation {
  name = "libssh2-ios";
  inherit src;
  patches = [ ];
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkgs.python3
  ];
  postPatch = ''
    echo "=== Applying streamlocal patch to libssh2 ==="
    ${pkgs.bash}/bin/bash ${./patch-streamlocal.sh}
  '';
  buildInputs = [ openssl-ios ];
  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv {
      inherit simulator;
      minVersion = mobileMinVersion;
    }}
    unset MACOSX_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    
    cat > ios-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME ${if isVisionOS || isTVOS then "Darwin" else "iOS"})
set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
set(CMAKE_OSX_DEPLOYMENT_TARGET ${mobileMinVersion})
set(CMAKE_C_COMPILER "$XCODE_CLANG")
set(CMAKE_CXX_COMPILER "$XCODE_CLANGXX")
set(CMAKE_C_COMPILER_TARGET "$APPLE_LINKER_TARGET")
set(CMAKE_CXX_COMPILER_TARGET "$APPLE_LINKER_TARGET")
set(CMAKE_SYSROOT "$SDKROOT")
set(CMAKE_OSX_SYSROOT "$SDKROOT")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_C_FLAGS "${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT -fPIC" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"}")
set(CMAKE_CXX_FLAGS "${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT -fPIC" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"}")
set(CMAKE_ASM_FLAGS "${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"}")
set(CMAKE_EXE_LINKER_FLAGS "${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"}")
set(CMAKE_SHARED_LINKER_FLAGS "${if isVisionOS then "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT" else "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG"}")
set(BUILD_SHARED_LIBS OFF)
EOF

    # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
    unset SDKROOT
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DCRYPTO_BACKEND=OpenSSL"
    "-DENABLE_ZLIB_COMPRESSION=${if isVisionOS then "OFF" else "ON"}"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_EXAMPLES=OFF"
    "-DBUILD_TESTING=OFF"
    "-DOPENSSL_ROOT_DIR=${openssl-ios}"
    "-DOPENSSL_CRYPTO_LIBRARY=${openssl-ios}/lib/libcrypto.a"
    "-DOPENSSL_SSL_LIBRARY=${openssl-ios}/lib/libssl.a"
    "-DOPENSSL_INCLUDE_DIR=${openssl-ios}/include"
  ];
}
