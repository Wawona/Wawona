# pango cross-compiled for Android (static). Text layout engine; final dependency
# of the weston toytoolkit (clients/window.c uses pangocairo for text) on Android.
#
# Depends on the full cross stack: glib + harfbuzz + fontconfig + freetype + cairo
# + fribidi (and their transitive .pc files). Build-machine glib tooling
# (glib-mkenums/genmarshal) comes from buildPackages.glib. introspection/docs/xft/
# sysprof are disabled. Unlike the Apple build, Android has no CoreText backend to
# patch out.
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
  src = pkgs.pango.src;
  glib = buildModule.buildForAndroid "glib" { };
  harfbuzz = buildModule.buildForAndroid "harfbuzz" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  cairo = buildModule.buildForAndroid "cairo" { };
  fribidi = buildModule.buildForAndroid "fribidi" { };
  libffi = buildModule.buildForAndroid "libffi" { };
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  expat = buildModule.buildForAndroid "expat" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  libintl = buildModule.buildForAndroid "libintl" { };
  buildFlags = [
    "-Dintrospection=disabled"
    "-Dgtk_doc=false"
    "-Dfontconfig=enabled"
    "-Dcairo=enabled"
    "-Dfreetype=enabled"
    "-Dxft=disabled"
    "-Dsysprof=disabled"
    "-Dlibthai=disabled"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "pango-android";
  inherit src;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    glib # build-machine glib-mkenums/glib-genmarshal + native glib-2.0.pc
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
    c_link_args = ['-L${libintl}/lib', '-lintl']
    cpp_link_args = ['-L${libintl}/lib', '-lintl']
    EOF
  '';

  configurePhase = ''
    runHook preConfigure
    export PKG_CONFIG_PATH="${glib}/lib/pkgconfig:${harfbuzz}/lib/pkgconfig:${fontconfig}/lib/pkgconfig:${freetype}/lib/pkgconfig:${cairo}/lib/pkgconfig:${fribidi}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:${pixman}/lib/pkgconfig:${expat}/lib/pkgconfig:${libpng}/lib/pkgconfig:${libintl}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=android-cross-file.txt \
      --buildtype=release \
      --wrap-mode=nofallback \
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
