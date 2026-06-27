# freetype cross-compiled for Android (static). Foundational font-rasterizer for
# the weston toytoolkit cairo/pango stack on Android (NDK).
#
# harfbuzz is disabled to break the freetype<->harfbuzz cycle; png/brotli/bzip2 are
# off to keep the leaf dependency-free (zlib comes from the NDK sysroot).
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
  name = "freetype-android";
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
