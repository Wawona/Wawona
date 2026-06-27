# glib cross-compiled for Android (static). Core type/utility library required by
# the pango/harfbuzz half of the weston toytoolkit stack on Android (NDK).
#
# Depends on libffi-android + pcre2-android (PKG_CONFIG_PATH); zlib from the NDK
# sysroot. glib builds codegen helpers on the BUILD machine, so a native-file
# points meson at the build-host compiler and needs_exe_wrapper=true stops meson
# from trying to run Android host binaries during configure.
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
  src = pkgs.glib.src;
  libffi = buildModule.buildForAndroid "libffi" { };
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  libintl = buildModule.buildForAndroid "libintl" { };
  buildFlags = [
    "-Dtests=false"
    "-Dnls=disabled"
    "-Dlibmount=disabled"
    "-Dselinux=disabled"
    "-Dman-pages=disabled"
    "-Dintrospection=disabled"
    "-Ddtrace=false"
    "-Dsystemtap=false"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "glib-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    stdenv.cc
  ];
  buildInputs = [ ];

  preConfigure = ''
    cat > android-cross-file.txt <<EOF
    [binaries]
    c = '${androidToolchain.androidCC}'
    cpp = '${androidToolchain.androidCXX}'
    ar = '${androidToolchain.androidAR}'
    strip = '${androidToolchain.androidSTRIP}'
    pkgconfig = '${buildPackages.pkg-config}/bin/pkg-config'

    [host_machine]
    system = 'android'
    cpu_family = 'aarch64'
    cpu = 'aarch64'
    endian = 'little'

    [properties]
    needs_exe_wrapper = true
    pkg_config_libdir = '${libintl}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig'

    [built-in options]
    c_args = ['-fPIC', '-I${libintl}/include']
    cpp_args = ['-fPIC', '-I${libintl}/include']
    c_link_args = ['-L${libintl}/lib', '-lintl']
    cpp_link_args = ['-L${libintl}/lib', '-lintl']
    EOF

    cat > native-file.txt <<EOF
    [binaries]
    c = '${buildPackages.stdenv.cc}/bin/cc'
    cpp = '${buildPackages.stdenv.cc}/bin/c++'
    ar = '${buildPackages.stdenv.cc}/bin/ar'
    strip = 'strip'
    pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
    EOF
  '';

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${libintl}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --native-file=native-file.txt \
      --cross-file=android-cross-file.txt \
      --pkg-config-path="${libintl}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig" \
      --buildtype=release \
      -Ddefault_library=static \
      ${lib.concatMapStringsSep " " (flag: flag) buildFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    meson install -C build
    runHook postInstall
  '';
}
