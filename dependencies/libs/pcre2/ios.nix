# pcre2 cross-compiled for iOS (static). Hard dependency of glib (pcre2-8), which
# is required by the pango/harfbuzz half of the weston toytoolkit stack.
# Uses the CMake cross scaffold (mkIOSBuildEnv) like mbedtls.
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
  src = pkgs.pcre2.src;
in
pkgs.stdenv.mkDerivation {
  name = "pcre2-ios";
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
    "-DPCRE2_BUILD_PCRE2_8=ON"
    "-DPCRE2_BUILD_PCRE2_16=OFF"
    "-DPCRE2_BUILD_PCRE2_32=OFF"
    "-DPCRE2_BUILD_TESTS=OFF"
    "-DPCRE2_BUILD_PCRE2GREP=OFF"
    "-DBUILD_SHARED_LIBS=OFF"
  ];
  postInstall = ''
    for pc in $out/lib/pkgconfig/*.pc; do
      [ -f "$pc" ] || continue
      sed -i -E 's|=\$\{exec_prefix\}/(/nix/store)|=\1|g; s|=\$\{prefix\}/(/nix/store)|=\1|g' "$pc"
    done
  '';
}
