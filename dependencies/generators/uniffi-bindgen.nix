# Host UniFFI 0.30 bindgen CLI.
#
# Separate rustPlatform package. Never a crate2nix workspace member. Enabling
# `uniffi` `cli` on the Wawona crate itself splits uniffi_bindgen SVHs (E0460).
# Output is a store path. Do not copy generated Swift/Kotlin into git.
#
# Pin: crates.io `uniffi` 0.30.0 (same as Wawona/Cargo.toml). Lock is the
# crate's own Cargo.lock (input pin, not an app binding).
{
  pkgs,
  lib,
}:
let
  rustPlatform =
    if pkgs ? rustToolchain then
      pkgs.makeRustPlatform {
        cargo = pkgs.rustToolchain;
        rustc = pkgs.rustToolchain;
      }
    else
      pkgs.rustPlatform;
in
rustPlatform.buildRustPackage {
  pname = "wawona-uniffi-bindgen";
  version = "0.30.0";

  src = pkgs.fetchurl {
    name = "uniffi-0.30.0.tar.gz";
    url = "https://static.crates.io/crates/uniffi/0.30.0/download";
    hash = "sha256-yGb2J8PwTD3waLaLstclSSyqpTndMT4qnSa7hbGjL04=";
  };
  sourceRoot = "uniffi-0.30.0";

  cargoLock = {
    lockFile = ./uniffi-bindgen/Cargo.lock;
  };

  buildFeatures = [ "cli" ];
  cargoBuildFlags = [ "--bin" "uniffi-bindgen" ];
  doCheck = false;

  meta = {
    description = "Mozilla UniFFI 0.30 bindgen for Nix-generated Wawona Swift/Kotlin";
    mainProgram = "uniffi-bindgen";
    license = lib.licenses.mpl20;
  };
}
