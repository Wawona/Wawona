# freetype cross-compiled for iOS (static). Foundational font-rasterizer for the
# weston toytoolkit (clients/window.c) cairo/pango stack on Apple platforms.
#
# harfbuzz is disabled here to break the freetype<->harfbuzz cycle (harfbuzz is
# built later and depends on freetype; freetype only needs harfbuzz for
# auto-hint shaping, which the toytoolkit does not require). png/brotli/bzip2 are
# off to keep the leaf dependency-free (only system zlib from the SDK).
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
  src = pkgs.freetype.src;
  buildFlags = [
    "-Dharfbuzz=disabled"
    "-Dbrotli=disabled"
    "-Dbzip2=disabled"
    "-Dpng=disabled"
    "-Dzlib=system"
    "-Dtests=disabled"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "freetype-ios";
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
