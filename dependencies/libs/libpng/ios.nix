# libpng cross-compiled for iOS (static). Required by weston's shared/image-loader.c
# (cairo-shared), which the toytoolkit (clients/window.c) and image-loading demo
# clients link against. Uses the CMake cross scaffold (mkIOSBuildEnv) like pcre2;
# zlib comes from the cross zlib-ios.
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
  platformInfo = import ../../toolchains/apple-mobile-platform.nix;
  cmakeToolchain = import ../../toolchains/apple-cmake-toolchain.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  zlib = buildModule.buildForIOS "zlib" { inherit simulator; };
  src = pkgs.libpng.src;
in
pkgs.stdenv.mkDerivation {
  name = "libpng-ios";
  inherit src;

  __noChroot = true;
  nativeBuildInputs = with buildPackages; [ cmake ];
  buildInputs = [ ];

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobile.minVersion; }}
    unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    ${cmakeToolchain { inherit iosToolchain simulator; }}
    unset SDKROOT
  '';
  cmakeFlags = [
    "-DCMAKE_TOOLCHAIN_FILE=ios-toolchain.cmake"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DPNG_SHARED=OFF"
    "-DPNG_STATIC=ON"
    "-DPNG_FRAMEWORK=OFF"
    "-DPNG_TESTS=OFF"
    "-DPNG_TOOLS=OFF"
    "-DPNG_EXECUTABLES=OFF"
    "-DPNG_ARM_NEON=off"
    "-DZLIB_INCLUDE_DIR=${zlib}/include"
    "-DZLIB_LIBRARY=${zlib}/lib/libz.a"
    "-DBUILD_SHARED_LIBS=OFF"
  ];
  postInstall = ''
    for pc in $out/lib/pkgconfig/*.pc; do
      [ -f "$pc" ] || continue
      sed -i -E 's|=\$\{exec_prefix\}/(/nix/store)|=\1|g; s|=\$\{prefix\}/(/nix/store)|=\1|g' "$pc"
      sed -i -E '/^Requires\.private:[[:space:]]*zlib[[:space:]]*$/d' "$pc"
    done
  '';
}
