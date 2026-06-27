# cairo cross-compiled for iOS (static). 2D image-surface renderer for the weston
# toytoolkit (clients/window.c draws into cairo image surfaces backed by SHM).
#
# Depends on pixman-ios (required), freetype-ios + fontconfig-ios (+ expat). PNG,
# glib(cairo-gobject), the X/XCB/quartz/win32 backends, tee/xml/spectre and
# symbol-lookup are disabled to keep the static leaf on the proven meson path with
# no extra cross deps (toytoolkit only needs the image + ft/fontconfig surfaces).
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
  src = pkgs.cairo.src;
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
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
  name = "cairo-ios";
  inherit src;

  # Weston only needs the static libcairo archive + .pc files; skip util/ binaries
  # (csi-replay etc.) that link-test the full font stack and break on tvOS/watchOS.
  postPatch = ''
    python3 - <<'PY'
from pathlib import Path
p = Path("meson.build")
lines = p.read_text().splitlines(keepends=True)
out = []
for line in lines:
    if "subdir('util" in line.replace('"', "'"):
        out.append("# " + line)
    else:
        out.append(line)
p.write_text("".join(out))
PY
  '';

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
    export PKG_CONFIG_PATH="${pixman}/lib/pkgconfig:${freetype}/lib/pkgconfig:${fontconfig}/lib/pkgconfig:${expat}/lib/pkgconfig:${libpng}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
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
