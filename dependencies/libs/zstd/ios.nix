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
    else iosToolchain.deploymentTarget;
  cmakeSystemName =
    if isVisionOS || isTVOS then "Darwin" else "iOS";
  # zstd source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "v1.5.7";
    sha256 = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "zstd-ios";
  inherit src;
  patches = [ ];
  
  # Allow access to Xcode SDKs and toolchain
  __noChroot = true;
  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];
  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; minVersion = mobileMinVersion; }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    cat > ios-toolchain.cmake <<EOF
    set(CMAKE_SYSTEM_NAME ${cmakeSystemName})
    set(CMAKE_OSX_ARCHITECTURES $IOS_ARCH)
    set(CMAKE_OSX_DEPLOYMENT_TARGET ${mobileMinVersion})
    set(CMAKE_C_COMPILER "$XCODE_CLANG")
    set(CMAKE_CXX_COMPILER "$XCODE_CLANGXX")
    set(CMAKE_SYSROOT "$SDKROOT")
    set(CMAKE_OSX_SYSROOT "$SDKROOT")
    set(CMAKE_C_FLAGS "$APPLE_DEPLOYMENT_FLAG")
    set(CMAKE_CXX_FLAGS "$APPLE_DEPLOYMENT_FLAG")
    set(BUILD_SHARED_LIBS OFF)
    EOF

    # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
    unset SDKROOT
  '';

  # zstd has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DZSTD_BUILD_PROGRAMS=OFF"
    "-DZSTD_BUILD_SHARED=OFF"
    "-DZSTD_BUILD_STATIC=ON"
  ];
}
