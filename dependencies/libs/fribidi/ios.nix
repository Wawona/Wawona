# fribidi cross-compiled for iOS (static). Unicode bidi algorithm; pango shaping
# dependency for the weston toytoolkit on Apple platforms. Standalone meson lib.
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
  src = pkgs.fribidi.src;
  buildFlags = [
    "-Ddocs=false"
    "-Dtests=false"
    "-Dbin=false"
  ];
in
pkgs.stdenv.mkDerivation {
  name = "fribidi-ios";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
    stdenv.cc # build-machine compiler for fribidi's gen.tab unicode-table generators
  ];
  buildInputs = [ ];

  preConfigure =
    mesonSetup.preConfigureShell { }
    + mesonSetup.nativeFileShell;

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --native-file=native-file.txt \
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
