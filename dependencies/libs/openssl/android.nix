{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain,
  ...
}:

let
  fetchSource = common.fetchSource;
in
pkgs.stdenv.mkDerivation {
  name = "openssl-android";
  src = pkgs.fetchurl {
    url = "https://www.openssl.org/source/openssl-3.3.1.tar.gz";
    sha256 = "sha256-d3zVlihMiDN1oqehG/XSeG/FQTJV76sgxQ1v/m0CC34=";
  };

  nativeBuildInputs = with buildPackages; [ perl ];
  buildInputs = [ ];

  configurePhase = ''
    runHook preConfigure
    patchShebangs .
    export CROSS_COMPILE=""
    export CC="${androidToolchain.androidCC}"
    export AR="${androidToolchain.androidAR}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export PATH="${buildPackages.stdenv.cc}/bin:$PATH"
    export ANDROID_NDK_ROOT="${androidToolchain.androidndkRoot}"
    # Note: hostTag is handled in toolchains/android.nix
    ${buildPackages.perl}/bin/perl ./Configure linux-aarch64 \
      no-shared no-dso no-tests no-apps no-docs \
      --prefix=$out --openssldir=$out/etc/ssl \
      CC="$CC"
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install_sw install_ssldirs
    runHook postInstall
  '';
}
