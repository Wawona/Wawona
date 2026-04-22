{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null, ... }:

# Explicit watchOS module forwarding to the platform-adjusted iOS recipe.
let
  iosModule = import ./ios.nix;
  forwarded = {
    inherit lib pkgs buildPackages common buildModule simulator iosToolchain;
  };
in
iosModule (builtins.intersectAttrs (builtins.functionArgs iosModule) forwarded)
