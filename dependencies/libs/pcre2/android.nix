# pcre2 cross-compiled for Android (static). Hard dependency of glib (pcre2-8),
# required by the pango/harfbuzz half of the weston toytoolkit stack. Uses the
# CMake cross scaffold (android-cmake.nix) like expat.
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
  src = pkgs.pcre2.src;
  androidCmake = import ../../toolchains/android-cmake.nix {
    inherit lib pkgs androidToolchain;
  };
in
pkgs.stdenv.mkDerivation {
  name = "pcre2-android";
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
    "-DPCRE2_BUILD_PCRE2_8=ON"
    "-DPCRE2_BUILD_PCRE2_16=OFF"
    "-DPCRE2_BUILD_PCRE2_32=OFF"
    "-DPCRE2_BUILD_TESTS=OFF"
    "-DPCRE2_BUILD_PCRE2GREP=OFF"
    "-DBUILD_SHARED_LIBS=OFF"
  ];

  # pcre2's CMake emits ${exec_prefix}//abs/path in its .pc files; normalise the
  # doubled slash so nixpkgs' pkg-config path validator accepts them.
  postInstall = ''
    for pc in $out/lib/pkgconfig/*.pc; do
      [ -f "$pc" ] || continue
      sed -i -E 's|=\$\{exec_prefix\}/(/nix/store)|=\1|g; s|=\$\{prefix\}/(/nix/store)|=\1|g' "$pc"
    done
  '';
}
