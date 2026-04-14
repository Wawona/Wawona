{ lib, pkgs, buildPackages, common, buildModule, ... }:
(import ../../platforms/linux.nix { inherit lib pkgs buildPackages common buildModule; }).buildForLinux "weston-simple-shm" { }
