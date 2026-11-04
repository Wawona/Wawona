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
  terminalSrc ? null,
  # Same fetchTree as flake libghosttyRsSrc. Path-stages VT crates so
  # importCargoLock does not need git outputHashes for libghostty-vt.
  libghosttyRsSrc ? null,
  westonSimpleShmLinuxNix,
}:

let
  workspaceSrc = pkgs.callPackage ./workspace-src.nix {
    inherit wawonaSrc waypipeSrc wawonaVersion coreutilsSrc terminalSrc libghosttyRsSrc;
    platform = "macos"; # keep the [[bin]] targets + lib crate-types
  };

  # Bundled Wayland clients + transports the Machine Configuration launcher
  # spawns (weston demos, foot, kmscube, waypipe/ssh). The JIT runner
  # (linux.nix) provides these via runtimeInputs; the prebuilt binary needs
  # them on the wrapper PATH or every "Start" is `command not found`.
  clientPath = lib.makeBinPath [
    pkgs.weston
    (pkgs.callPackage westonSimpleShmLinuxNix { })
    pkgs.foot
    pkgs.kmscube
    pkgs.waypipe
    pkgs.openssh
    pkgs.fastfetch
  ];

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

  # Vendor from the *workspaceSrc* lock, not the raw tree lock. workspace-src
  # expands uutils pins and rewrites [[package]] dependency lists in
  # Cargo.lock (uucore thiserror sync, etc.). Vendoring ../../Cargo.lock then
  # comparing against that patched lock fails cargoSetupPostPatchHook.
  cargoLock = {
    lockFile = "${workspaceSrc}/Cargo.lock";
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

  # Bake ship build into About when CI/Fastlane sets WAWONA_BUILD_NUMBER.
  WAWONA_BUILD_NUMBER =
    let
      bn = builtins.getEnv "WAWONA_BUILD_NUMBER";
      gh = builtins.getEnv "GITHUB_RUN_NUMBER";
    in
    if bn != "" then bn else if gh != "" then gh else "1";

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.wrapGAppsHook4
  ];
  buildInputs = gtkStack;

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : "${clientPath}")
  '';

  meta = {
    description = "Wawona Linux GTK binaries (ahead-of-time compiled)";
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "wawona-linux-ui";
  };
}
