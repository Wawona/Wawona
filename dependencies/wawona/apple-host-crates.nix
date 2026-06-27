# Shared host-side crate2nix graph for all Apple cross backends.
# Delegates to rust-backend-c2n hostGraphOnly so crate overrides (pkg-config,
# wayland-sys, openssl, …) match the cross backend host builds exactly.
{
  pkgs,
  lib,
  crate2nix,
  workspaceSrc,
  wawonaVersion,
  toolchains,
  nixpkgs,
  nativeDeps,
}:

pkgs.callPackage ./rust-backend-c2n.nix {
  inherit
    crate2nix
    wawonaVersion
    workspaceSrc
    toolchains
    nixpkgs
    nativeDeps
    ;
  platform = "ios";
  simulator = false;
  hostGraphOnly = true;
  appleHostCrates = null;
}
