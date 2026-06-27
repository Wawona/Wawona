# harfbuzz cross-compiled for iOS (static). Text shaping engine for the pango half
# of the weston toytoolkit stack on Apple platforms.
#
# Depends on freetype-ios + glib-ios (and glib's transitive libffi/pcre2 .pc files
# must be on PKG_CONFIG_PATH for static Requires.private resolution). cairo/icu/
# gobject/introspection are disabled to keep the leaf small and break the
# harfbuzz<->cairo cycle.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
}:

let
  xcodeUtils = import ../../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  mesonSetup = import ../../toolchains/apple-mobile-meson.nix {
    inherit lib buildPackages xcodeUtils iosToolchain simulator;
  };
  src = pkgs.harfbuzz.src;
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  glib = buildModule.buildForIOS "glib" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };
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
  name = "harfbuzz-ios";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
  ];
  buildInputs = [ ];

  preConfigure = mesonSetup.preConfigureShell { };

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    export PKG_CONFIG_PATH="${freetype}/lib/pkgconfig:${glib}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
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
