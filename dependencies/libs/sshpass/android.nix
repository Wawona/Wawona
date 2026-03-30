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
  hostTag = if pkgs.stdenv.buildPlatform.isLinux then "linux-x86_64" else "darwin-x86_64";
  NDK_SYSROOT = "${androidToolchain.androidndkRoot}/toolchains/llvm/prebuilt/${hostTag}/sysroot";
in
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
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -fPIC ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${NDK_SYSROOT} -L${androidToolchain.androidNdkAbiLibDir} -static"
  '';

  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --host=aarch64-linux-android \
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
