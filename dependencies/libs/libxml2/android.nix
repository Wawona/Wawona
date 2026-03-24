{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  androidToolchain ? null,
  ...
}:

let
  androidToolchainEffective = if androidToolchain != null then androidToolchain else import ../../toolchains/android.nix { inherit lib pkgs; };
  androidToolchain = androidToolchainEffective;
  fetchSource = common.fetchSource;
  # androidToolchain passed from caller
  libxml2Source = {
    source = "gitlab-gnome";
    owner = "GNOME";
    repo = "libxml2";
    rev = "v2.14.0";
    sha256 = "sha256-SFDNj4QPPqZUGLx4lfaUzHn0G/HhvWWXWCFoekD9lYM=";
  };
  src = fetchSource libxml2Source;
  buildFlags = [
    "--without-python"
    "--without-python"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libxml2-android";
  inherit src patches;
  nativeBuildInputs = with buildPackages; [
    autoconf
    automake
    libtool
    pkg-config
    texinfo
  ];
  buildInputs = [ ];
  preConfigure = ''
    if [ ! -f ./configure ]; then
      autoreconf -fi || autogen.sh || true
    fi
    export CC="${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}"
    export CXX="${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="-fPIC"
    export CXXFLAGS="-fPIC"
  '';
  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=/usr --host=${androidToolchain.androidTarget} \
      --enable-static --disable-shared \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES libxml2.la || make libxml2.la || true
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install DESTDIR=$out || make install-data-am install-exec-am DESTDIR=$out || true
    if [ -d "$out/usr" ]; then
      if [ -d "$out/usr/lib" ]; then
        mkdir -p $out/lib
        cp -r $out/usr/lib/* $out/lib/ 2>/dev/null || true
      fi
      if [ -d "$out/usr/lib/pkgconfig" ]; then
        mkdir -p $out/lib/pkgconfig
        cp -r $out/usr/lib/pkgconfig/* $out/lib/pkgconfig/ || true
      fi
      if [ -d "$out/usr/share/pkgconfig" ]; then
        mkdir -p $out/lib/pkgconfig
        cp -r $out/usr/share/pkgconfig/* $out/lib/pkgconfig/ || true
      fi
      if [ -d "$out/usr/include" ]; then
        mkdir -p $out/include
        cp -r $out/usr/include/* $out/include/ || true
      fi
    fi
    if [ -d .libs ]; then
      mkdir -p $out/lib
      for lib in .libs/*.a; do
        if [ -f "$lib" ]; then
          libname=$(basename "$lib" .a)
          cp "$lib" $out/lib/ || true
          if [ ! -f "$out/lib/''${libname}.so" ] && [ -f "$lib" ]; then
            cp "$lib" "$out/lib/''${libname}.so" || true
          fi
        fi
      done
    fi
    runHook postInstall
  '';
  CC = "${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}";
  CXX = "${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}";
  NIX_CFLAGS_COMPILE = "-fPIC";
  NIX_CXXFLAGS_COMPILE = "-fPIC";
  __impureHostDeps = [ "/bin/sh" ];
}
