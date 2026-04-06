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
  # Keep a libffi-local compiler shim that emulates GCC multi-directory probes.
  # Autotools/libtool may call these flags and fail hard when invoked against
  # plain clang binaries.
  libffiCC = pkgs.writeShellScript "libffi-android-cc" ''
    for arg in "$@"; do
      case "$arg" in
        -print-multi-os-directory|-print-multi-directory)
          echo "."
          exit 0
          ;;
      esac
    done
    exec "${androidToolchain.androidCC}" "$@"
  '';
  libffiCXX = pkgs.writeShellScript "libffi-android-cxx" ''
    for arg in "$@"; do
      case "$arg" in
        -print-multi-os-directory|-print-multi-directory)
          echo "."
          exit 0
          ;;
      esac
    done
    exec "${androidToolchain.androidCXX}" "$@"
  '';
  selectedCC = libffiCC;
  selectedCXX = libffiCXX;
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
      if [ -x ./autogen.sh ]; then
        autoreconf -fi || ./autogen.sh
      else
        autoreconf -fi
      fi
    fi
    [ -f ./configure ] || { echo "libffi configure script is missing"; exit 1; }
    export CC="${selectedCC}"
    export CXX="${selectedCXX}"
    export AR="${androidToolchain.androidAR}"
    export STRIP="${androidToolchain.androidSTRIP}"
    export RANLIB="${androidToolchain.androidRANLIB}"
    # Cross-cache hints for libffi's autotools checks:
    # - Do not set ac_cv_prog_cc_c11 (it can be treated as a compiler token).
    # - Keep compiler/cross detection deterministic across arm64/x86_64 hosts.
    export ac_cv_prog_cc_works=yes
    export ac_cv_prog_cc_cross=yes
    # Android/aarch64 is always little-endian; avoid brittle runtime/probe paths.
    export ac_cv_c_bigendian=no
  '';
  configurePhase = ''
    runHook preConfigure
    ./configure \
      --prefix=$out \
      --build=${pkgs.stdenv.buildPlatform.config} \
      --host=${androidToolchain.androidTarget} \
      --with-sysroot=${androidToolchain.androidNdkSysroot} ${
      lib.concatMapStringsSep " " (flag: flag) buildFlags
    } || {
      echo "=== libffi config.log (tail) ==="
      [ -f config.log ] && tail -n 200 config.log
      [ -f aarch64-unknown-linux-android/config.log ] && tail -n 200 aarch64-unknown-linux-android/config.log
      exit 1
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
    # Also check .libs directory as fallback
    if [ -d .libs ] && [ ! -f "$out/lib/libffi.a" ]; then
      mkdir -p $out/lib
      find .libs -name "*.a" -exec cp {} $out/lib/ \;
    fi
    [ -f "$out/lib/libffi.a" ] || { echo "missing libffi.a"; exit 1; }
    runHook postInstall
  '';
  NIX_CFLAGS_COMPILE = "-fPIC";
  NIX_CXXFLAGS_COMPILE = "-fPIC";
  __impureHostDeps = [ "/bin/sh" ];
}
