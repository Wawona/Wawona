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
      if [ -x ./autogen.sh ]; then
        autoreconf -fi || ./autogen.sh
      else
        autoreconf -fi
      fi
    fi
    [ -f ./configure ] || { echo "libxml2 configure script is missing"; exit 1; }
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="-fPIC"
    export CXXFLAGS="-fPIC"
    export LDFLAGS="-L${androidToolchain.androidNdkAbiLibDir}"
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
    make -j$NIX_BUILD_CORES libxml2.la || make libxml2.la
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install DESTDIR=$out || make install-data-am install-exec-am DESTDIR=$out
    if [ -d "$out/usr" ]; then
      if [ -d "$out/usr/lib" ]; then
        mkdir -p $out/lib
        cp -r $out/usr/lib/. $out/lib/
      fi
      if [ -d "$out/usr/lib/pkgconfig" ]; then
        mkdir -p $out/lib/pkgconfig
        cp -r $out/usr/lib/pkgconfig/. $out/lib/pkgconfig/
      fi
      if [ -d "$out/usr/share/pkgconfig" ]; then
        mkdir -p $out/lib/pkgconfig
        cp -r $out/usr/share/pkgconfig/. $out/lib/pkgconfig/
      fi
      if [ -d "$out/usr/include" ]; then
        mkdir -p $out/include
        cp -r $out/usr/include/. $out/include/
      fi
    fi
    if [ -d .libs ]; then
      mkdir -p $out/lib
      shopt -s nullglob
      for lib in .libs/*.a; do
        cp "$lib" $out/lib/
      done
      shopt -u nullglob
    fi
    [ -f "$out/lib/libxml2.a" ] || { echo "missing libxml2.a"; exit 1; }
    runHook postInstall
  '';
  NIX_CFLAGS_COMPILE = "-fPIC";
  NIX_CXXFLAGS_COMPILE = "-fPIC";
  __impureHostDeps = [ "/bin/sh" ];
}
