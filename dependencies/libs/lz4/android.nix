{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
}:

let
  # lz4 source - fetch from GitHub
  src = pkgs.fetchFromGitHub {
    owner = "lz4";
    repo = "lz4";
    rev = "v1.10.0";
    sha256 = "sha256-/dG1n59SKBaEBg72pAWltAtVmJ2cXxlFFhP+klrkTos=";
  };
in
pkgs.stdenv.mkDerivation {
  name = "lz4-android";
  inherit src;
  patches = [ ];
  nativeBuildInputs = with buildPackages; [
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

  buildPhase = ''
    runHook preBuild
    make -C lib \
      CC="$CC" \
      AR="$AR" \
      RANLIB="$RANLIB" \
      CFLAGS="$CFLAGS" \
      lib-release
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/include" "$out/lib/pkgconfig"
    cp lib/liblz4.a "$out/lib/"
    cp lib/lz4*.h "$out/include/"
    cat > "$out/lib/pkgconfig/liblz4.pc" <<EOF
prefix=$out
exec_prefix=\''${prefix}
libdir=\''${exec_prefix}/lib
includedir=\''${prefix}/include

Name: liblz4
Description: LZ4 compression library
Version: 1.10.0
Libs: -L\''${libdir} -llz4
Cflags: -I\''${includedir}
EOF
    runHook postInstall
  '';
}
