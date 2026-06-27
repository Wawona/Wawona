# libpng cross-compiled for Android (static). Required by weston's
# shared/image-loader.c (cairo-shared). Uses the CMake cross scaffold; zlib comes
# from the NDK sysroot (Bionic ships libz).
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  src = pkgs.libpng.src;
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
  };
in
pkgs.stdenv.mkDerivation {
  name = "libpng-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    cmake
    pkg-config
  ];
  buildInputs = [ ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
  '';

  cmakeFlags = [
    "-DCMAKE_C_COMPILER=${androidToolchain.androidCC}"
    "-DCMAKE_CXX_COMPILER=${androidToolchain.androidCXX}"
  ]
  ++ androidCmake.mkCrossFlags {
    abi = "arm64-v8a";
    useAndroidToolchainFile = true;
  }
  ++ [
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DPNG_SHARED=OFF"
    "-DPNG_STATIC=ON"
    "-DPNG_FRAMEWORK=OFF"
    "-DPNG_TESTS=OFF"
    "-DPNG_TOOLS=OFF"
    "-DPNG_EXECUTABLES=OFF"
    "-DPNG_ARM_NEON=off"
    # CMake's Android FIND_ROOT_PATH mode hides the NDK sysroot zlib; point at it.
    "-DZLIB_INCLUDE_DIR=${androidToolchain.androidNdkSysroot}/usr/include"
    "-DZLIB_LIBRARY=${androidCmake.androidLib "z"}"
    "-DBUILD_SHARED_LIBS=OFF"
  ];

  postInstall = ''
    for pc in $out/lib/pkgconfig/*.pc; do
      [ -f "$pc" ] || continue
      sed -i -E 's|=\$\{exec_prefix\}/(/nix/store)|=\1|g; s|=\$\{prefix\}/(/nix/store)|=\1|g' "$pc"
    done
  '';
}
