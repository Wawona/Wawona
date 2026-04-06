{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain,
  ...
}:

pkgs.stdenv.mkDerivation {
  name = "sshpass-android";
  src = pkgs.fetchurl {
    url = "https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz";
    sha256 = "sha256-rREGwgPLtWGFyjutjGzK/KO0BkaWGU2oefgcjXvf7to=";
  };

  nativeBuildInputs = with buildPackages; [ ];
  buildInputs = [ ];

  preConfigure = ''
    export CC="${androidToolchain.androidCC}"
    export AR="${androidToolchain.androidAR}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export STRIP="${androidToolchain.androidSTRIP}"
  '';

  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out \
      ac_cv_func_malloc_0_nonnull=yes \
      ac_cv_func_realloc_0_nonnull=yes
    runHook postConfigure
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp sshpass $out/bin/
    chmod +x $out/bin/sshpass
    runHook postInstall
  '';
}
