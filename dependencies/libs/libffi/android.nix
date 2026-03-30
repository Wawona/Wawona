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
  libffiSource = {
    source = "github";
    owner = "libffi";
    repo = "libffi";
    tag = "v3.5.2";
    sha256 = "sha256-tvNdhpUnOvWoC5bpezUJv+EScnowhURI7XEtYF/EnQw=";
  };
  src = fetchSource libffiSource;
  buildFlags = [
    "--disable-docs"
    "--disable-shared"
    "--enable-static"
  ];
  patches = [ ];
in
pkgs.stdenv.mkDerivation {
  name = "libffi-android";
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
    export CC="${androidToolchain.androidCC}"
    export CXX="${androidToolchain.androidCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    export CFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export CXXFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -fPIC ${androidToolchain.androidNdkCflags}"
    export LDFLAGS="--target=${androidToolchain.androidTarget} --sysroot=${androidToolchain.androidNdkSysroot} -L${androidToolchain.androidNdkAbiLibDir}"
  '';
  configurePhase = ''
    runHook preConfigure
    ./configure --prefix=$out --host=aarch64-linux-android ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    }
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install
    # Ensure library files are in the right place
    if [ -d "$out/lib" ]; then
      echo "Library files installed to $out/lib:"
      ls -la "$out/lib/" || true
      fi
    # Also check .libs directory as fallback
    if [ -d .libs ] && [ ! -f "$out/lib/libffi.a" ]; then
      mkdir -p $out/lib
      find .libs -name "*.a" -exec cp {} $out/lib/ \;
      echo "Copied libraries from .libs:"
      ls -la "$out/lib/" || true
    fi
    runHook postInstall
  '';
  CC = "${androidToolchain.androidCC} --target=${androidToolchain.androidTarget}";
  CXX = "${androidToolchain.androidCXX} --target=${androidToolchain.androidTarget}";
  NIX_CFLAGS_COMPILE = "-fPIC";
  NIX_CXXFLAGS_COMPILE = "-fPIC";
  __impureHostDeps = [ "/bin/sh" ];
}
