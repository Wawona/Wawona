# Reproducible, ahead-of-time compiled Linux GTK binaries for Wawona.
#
# Unlike dependencies/wawona/linux.nix (which JIT-compiles via `cargo run` at
# launch), this derivation compiles `wawona-linux-ui` (+ the tray and
# compositor-host helpers) offline with crate vendoring from Cargo.lock. It is
# the base for the AppImage prebuilt (dependencies/wawona/appimage.nix) and
# doubles as the CI/local compile gate for the GTK UI on Linux.
{
  pkgs,
  lib,
  wawonaVersion,
  wawonaSrc ? ../..,
  waypipeSrc,
  coreutilsSrc,
}:

let
  workspaceSrc = pkgs.callPackage ./workspace-src.nix {
    inherit wawonaSrc waypipeSrc wawonaVersion coreutilsSrc;
    platform = "macos"; # keep the [[bin]] targets + lib crate-types
  };

  rustPlatform = pkgs.makeRustPlatform {
    cargo = pkgs.rustToolchain;
    rustc = pkgs.rustToolchain;
  };

  gtkStack = [
    pkgs.gtk4
    pkgs.libadwaita
    pkgs.glib
    pkgs.cairo
    pkgs.pango
    pkgs.gdk-pixbuf
    pkgs.graphene
    pkgs.harfbuzz
    pkgs.fribidi
    pkgs.freetype
    pkgs.fontconfig
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.openssl
    pkgs.libffi
    pkgs.zstd
    pkgs.lz4
    pkgs.vulkan-loader
  ];
in
rustPlatform.buildRustPackage {
  pname = "wawona-linux-ui";
  version = wawonaVersion;
  src = workspaceSrc;

  # Use the in-tree lockfile directly (it already pins waypipe/coreutils and
  # their sub-crates) to avoid an import-from-derivation on workspaceSrc.
  cargoLock = {
    lockFile = ../../Cargo.lock;
  };

  # The GTK UI binaries; the staticlib/cdylib + root binary are not needed here.
  buildNoDefaultFeatures = false;
  buildFeatures = [ "linux-ui" ];
  cargoBuildFlags = [
    "--bin" "wawona-linux-ui"
    "--bin" "wawona-linux-tray"
    "--bin" "wawona-linux-compositor-host"
  ];
  # Unit tests run in the dedicated cargo-test-linux CI job; skip here to keep
  # the prebuilt/AppImage build fast and deterministic.
  doCheck = false;

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.wrapGAppsHook4
  ];
  buildInputs = gtkStack;

  meta = {
    description = "Wawona Linux GTK binaries (ahead-of-time compiled)";
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "wawona-linux-ui";
  };
}
