{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null, ... }:

# Explicit watchOS module forwarding to the platform-adjusted iOS recipe.
import ./ios.nix {
  inherit lib pkgs buildPackages common buildModule simulator iosToolchain;
}
