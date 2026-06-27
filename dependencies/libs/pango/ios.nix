# pango cross-compiled for iOS (static). Text layout engine; final dependency of
# the weston toytoolkit (clients/window.c uses pangocairo for text).
#
# Depends on the full cross stack: glib + harfbuzz + fontconfig + freetype + cairo
# + fribidi (and their transitive .pc files: libffi/pcre2/pixman/expat). Pango's
# glib-mkenums/genmarshal helpers are arch-independent python scripts, so no native
# compiler is needed. introspection/docs/xft/sysprof are disabled.
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
  src = pkgs.pango.src;
  glib = buildModule.buildForIOS "glib" { inherit simulator; };
  harfbuzz = buildModule.buildForIOS "harfbuzz" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  cairo = buildModule.buildForIOS "cairo" { inherit simulator; };
  fribidi = buildModule.buildForIOS "fribidi" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
  buildFlags = [
    "-Dintrospection=disabled"
    "-Dgtk_doc=false"
    "-Dfontconfig=enabled"
    "-Dcairo=enabled"
    "-Dfreetype=enabled"
    "-Dxft=disabled"
    "-Dsysprof=disabled"
    "-Dlibthai=disabled"
    "-Dbuild-testsuite=false"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "pango-ios";
  inherit src;

  # pango's darwin branch unconditionally links the CoreText backend against the
  # ApplicationServices umbrella framework, which does not exist on iOS/tvOS/etc.
  # The toytoolkit uses the pangoft2/pangocairo (freetype+fontconfig) backend, so
  # strip the CoreText/ApplicationServices block entirely.
  postPatch = ''
    python3 - <<'PY'
from pathlib import Path
p = Path("meson.build")
t = p.read_text()
start = t.index("has_core_text = false")
marker = "pango_deps += dependency('appleframeworks', modules: [ 'CoreFoundation', 'ApplicationServices' ])"
mi = t.index(marker, start)
end = t.index("endif", mi) + len("endif")
t = t[:start] + "has_core_text = false" + t[end:]
# Cross builds cannot link-run cairo-ft+fontconfig probe; cairo-ios enables fontconfig.
t = t.replace(
    "if not cc.links(cairo_fc_test,",
    "if false and not cc.links(cairo_fc_test,",
)
p.write_text(t)
PY
  '';

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    glib
  ];
  buildInputs = [ ];

  preConfigure = mesonSetup.preConfigureShell {
    extraCrossBinaries = ''
      objc = '$IOS_CC'
      objcpp = '$IOS_CXX'
    '';
  };

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    export PKG_CONFIG_PATH="${glib}/lib/pkgconfig:${harfbuzz}/lib/pkgconfig:${fontconfig}/lib/pkgconfig:${freetype}/lib/pkgconfig:${cairo}/lib/pkgconfig:${fribidi}/lib/pkgconfig:${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:${pixman}/lib/pkgconfig:${expat}/lib/pkgconfig:${libpng}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --cross-file=ios-cross-file.txt \
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
