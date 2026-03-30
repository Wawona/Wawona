{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain, # androidToolchain passed from caller
  ...
}:

let
  # androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs; }; # Removed as androidToolchain is now a direct argument
  src = pkgs.fetchFromGitHub {
    owner = "Mbed-TLS";
    repo = "mbedtls";
    rev = "v3.6.0";
    sha256 = "sha256-tCwAKoTvY8VCjcTPNwS3DeitflhpKHLr6ygHZDbR6wQ=";
    fetchSubmodules = true;
  };
in
pkgs.stdenv.mkDerivation {
  name = "mbedtls-android";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    perl
  ];
  buildInputs = [ ];
  preConfigure = ''
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""

    cat > android-toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_SYSTEM_VERSION ${toString androidToolchain.androidNdkApiLevel})
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)
set(CMAKE_ANDROID_NDK "${androidToolchain.androidndkRoot}")
set(CMAKE_C_COMPILER "${androidToolchain.androidCC}")
set(CMAKE_CXX_COMPILER "${androidToolchain.androidCXX}")
set(CMAKE_C_FLAGS "--target=${androidToolchain.androidTarget} -fPIC ${androidToolchain.androidNdkCflags}")
set(CMAKE_CXX_FLAGS "--target=${androidToolchain.androidTarget} -fPIC ${androidToolchain.androidNdkCflags}")
set(BUILD_SHARED_LIBS OFF)
EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=android-toolchain.cmake"
    "-DENABLE_PROGRAMS=OFF"
    "-DENABLE_TESTING=OFF"
    "-DUSE_SHARED_MBEDTLS_LIBRARY=OFF"
    "-DUSE_STATIC_MBEDTLS_LIBRARY=ON"
  ];
}
