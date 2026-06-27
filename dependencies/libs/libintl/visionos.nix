{ lib, pkgs, buildPackages, common, buildModule, simulator ? false, iosToolchain ? null, ... }:
import ./apple-mobile.nix {
  inherit lib pkgs buildModule simulator iosToolchain;
  pname = "libintl-visionos";
}
