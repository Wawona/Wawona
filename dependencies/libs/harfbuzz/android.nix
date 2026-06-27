# harfbuzz cross-compiled for Android (static). Text shaping engine for the pango
# half of the weston toytoolkit stack on Android (NDK).
#
# Depends on freetype-android + glib-android (and glib's transitive libffi/pcre2
# .pc files must be on PKG_CONFIG_PATH). cairo/icu/gobject/introspection are
# disabled to keep the leaf small and break the harfbuzz<->cairo cycle.
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
  src = pkgs.harfbuzz.src;
  freetype = buildModule.buildForAndroid "freetype" { };
  glib = buildModule.buildForAndroid "glib" { };
  libffi = buildModule.buildForAndroid "libffi" { };
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  buildFlags = [
    "-Dtests=disabled"
    "-Ddocs=disabled"
    "-Dutilities=disabled"
    "-Dfreetype=enabled"
    "-Dglib=enabled"
    "-Dgobject=disabled"
    "-Dicu=disabled"
    "-Dcairo=disabled"
    "-Dintrospection=disabled"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "harfbuzz-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
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

    [built-in options]
    c_args = ['-fPIC']
    cpp_args = ['-fPIC']
    c_link_args = []
    cpp_link_args = []
    EOF
  '';

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${freetype}/lib/pkgconfig:${glib}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=android-cross-file.txt \
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
