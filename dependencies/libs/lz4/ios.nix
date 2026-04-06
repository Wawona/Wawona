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
  # lz4 source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "lz4";
    repo = "lz4";
    rev = "v1.10.0";
    sha256 = "sha256-/dG1n59SKBaEBg72pAWltAtVmJ2cXxlFFhP+klrkTos=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "lz4-ios";
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
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    cat > ios-toolchain.cmake <<EOF
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
    set(CMAKE_C_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
    set(CMAKE_CXX_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
    set(CMAKE_ASM_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
    set(CMAKE_EXE_LINKER_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
    set(CMAKE_SHARED_LINKER_FLAGS "-arch $IOS_ARCH -target $APPLE_LINKER_TARGET -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG")
    set(BUILD_SHARED_LIBS OFF)
    EOF

    # Unset SDKROOT so it doesn't leak into host-side tool builds during cmake checks
    unset SDKROOT
  '';

  # lz4 has CMakeLists.txt in build/cmake subdirectory
  sourceRoot = "source/build/cmake";

  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_STATIC_LIBS=ON"
    "-DBUILD_PROGRAMS=OFF"
  ];

  # Remove broken symlinks that CMake creates for iOS
  postInstall = ''
    rm -f $out/bin/lz4cat $out/bin/unlz4 || true
  '';
}
