{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
}:

let
  androidToolchain = import ../../toolchains/android.nix { inherit lib pkgs; };
  hostTag = if pkgs.stdenv.buildPlatform.isLinux then "linux-x86_64" else "darwin-x86_64";
  NDK_SYSROOT = "${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/${hostTag}/sysroot";
  NDK_LIB_PATH = "${NDK_SYSROOT}/usr/lib/aarch64-linux-android/${toString androidToolchain.androidNdkApiLevel}";
  src = pkgs.fetchFromGitHub {
    owner = "libssh2";
    repo = "libssh2";
    rev = "libssh2-1.11.1";
    sha256 = "sha256-yz97oqqN+NJTDL/HPJe3niFynbR8QXHuuiKr+uuKJtw=";
  };
  openssl-android = buildModule.buildForAndroid "openssl" { };
in
pkgs.stdenv.mkDerivation {
  name = "libssh2-android";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
    cmake
    pkgs.python3
  ];
  buildInputs = [ openssl-android ];
  postPatch = ''
    echo "=== Applying streamlocal patch to libssh2 ==="
    ${pkgs.bash}/bin/bash ${./patch-streamlocal.sh}
  '';
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
set(CMAKE_AR "${androidToolchain.androidAR}")
set(CMAKE_RANLIB "${androidToolchain.androidRANLIB}")
set(CMAKE_C_FLAGS "--target=${androidToolchain.androidTarget} -fPIC")
set(CMAKE_CXX_FLAGS "--target=${androidToolchain.androidTarget} -fPIC")
set(BUILD_SHARED_LIBS OFF)
EOF
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=android-toolchain.cmake"
    "-DCRYPTO_BACKEND=OpenSSL"
    "-DENABLE_ZLIB_COMPRESSION=ON"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DBUILD_EXAMPLES=OFF"
    "-DBUILD_TESTING=OFF"
    "-DOPENSSL_ROOT_DIR=${openssl-android}"
    "-DOPENSSL_CRYPTO_LIBRARY=${openssl-android}/lib/libcrypto.a"
    "-DOPENSSL_SSL_LIBRARY=${openssl-android}/lib/libssl.a"
    "-DOPENSSL_INCLUDE_DIR=${openssl-android}/include"
    "-DZLIB_INCLUDE_DIR=${NDK_SYSROOT}/usr/include"
    "-DZLIB_LIBRARY=${NDK_LIB_PATH}/libz.so"
  ];

  installPhase = ''
    runHook preInstall
    make install
    # Ensure pkg-config file exists
    mkdir -p $out/lib/pkgconfig
    if [ ! -f $out/lib/pkgconfig/libssh2.pc ]; then
      cat > $out/lib/pkgconfig/libssh2.pc <<PCEOF
prefix=$out
libdir=''${prefix}/lib
includedir=''${prefix}/include

Name: libssh2
Description: SSH2 library
Version: 1.11.1
Libs: -L''${libdir} -lssh2
Libs.private: -lssl -lcrypto -lz
Cflags: -I''${includedir}
PCEOF
    fi
    echo "libssh2-android install contents:"
    find $out -type f | head -30
    runHook postInstall
  '';
}
