# cairo cross-compiled for Android (static). 2D image-surface renderer for the
# weston toytoolkit (clients/window.c draws into cairo image surfaces backed by
# SHM) on Android (NDK).
#
# Depends on pixman + freetype + fontconfig (+ expat) + libpng. The X/XCB/quartz/
# win32 backends, glib(cairo-gobject), tee/xml/spectre and symbol-lookup are
# disabled to keep the static leaf minimal; zlib comes from the NDK sysroot.
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
  src = pkgs.cairo.src;
  pixman = buildModule.buildForAndroid "pixman" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  expat = buildModule.buildForAndroid "expat" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  buildFlags = [
    "-Dtests=disabled"
    "-Dxlib=disabled"
    "-Dxcb=disabled"
    "-Dquartz=disabled"
    "-Dpng=enabled"
    "-Dglib=disabled"
    "-Dtee=disabled"
    "-Dspectre=disabled"
    "-Dsymbol-lookup=disabled"
    "-Dfreetype=enabled"
    "-Dfontconfig=enabled"
    "-Dzlib=enabled"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "cairo-android";
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
    export PKG_CONFIG_PATH="${pixman}/lib/pkgconfig:${freetype}/lib/pkgconfig:${fontconfig}/lib/pkgconfig:${expat}/lib/pkgconfig:${libpng}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
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
