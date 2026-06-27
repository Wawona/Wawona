# glib cross-compiled for iOS (static). Core type/utility library required by the
# pango/harfbuzz half of the weston toytoolkit stack on Apple platforms.
#
# Depends on libffi-ios (closures) + pcre2-ios (gregex), wired via PKG_CONFIG_PATH;
# zlib comes from the SDK. glib builds codegen helpers on the BUILD machine, so a
# native-file points meson at Xcode clang + macOS SDK and needs_exe_wrapper=true
# stops meson from trying to run iOS host binaries during configure.
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
  src = pkgs.glib.src;
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };
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
  name = "glib-ios";
  inherit src;

  __noChroot = true;

  nativeBuildInputs = with buildPackages; [
    meson
    ninja
    pkg-config
    python3
  ];
  buildInputs = [ ];

  preConfigure =
    mesonSetup.preConfigureShell {
      includePolyfills = true;
      needsExeWrapper = true;
    }
    + mesonSetup.nativeFileShell;

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    export PKG_CONFIG_PATH="${libffi}/lib/pkgconfig:${pcre2}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
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
