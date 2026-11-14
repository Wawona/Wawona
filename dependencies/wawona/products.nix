# One product catalog for flake packages + CI.
#
# Apple / Android apps are built by `cargo xtask build <target>` over the
# committed Xcode 27 and Gradle projects (see xtask/src/product.rs). Nix only
# builds Linux products and the .deps slices. This file is the single place
# that names every shippable product and, on Linux, the one mkProduct that
# wires the GTK runner aliases.
#
# CI reads the sibling JSON matrix: .github/ci-product-matrix.json.

{
  lib,
  pkgs,
  wawonaVersion,
  wawonaLinuxUiBin ? null,
  nix-appimage ? null,
  system ? pkgs.system,
  callPackage ? pkgs.callPackage,
}:

let
  # Platforms that cargo xtask builds (committed projects). Not Nix derivations.
  xtaskProducts = [
    "macos"
    "ios"
    "ipados"
    "ios-modeb"
    "tvos"
    "visionos"
    "watchos"
    "android"
  ];

  mkProduct = {
    platform,
  }:
    if builtins.elem platform ["linux" "wawona" "default"]
    then
      callPackage ./linux.nix {
        inherit wawonaVersion wawonaLinuxUiBin;
      }
    else if platform == "linux-compositor-host"
    then
      callPackage ./linux-host.nix {
        inherit wawonaVersion wawonaLinuxUiBin;
      }
    else if platform == "linux-tray"
    then
      callPackage ./linux-tray.nix {
        inherit wawonaVersion wawonaLinuxUiBin;
      }
    else if platform == "linux-vm"
    then
      callPackage ./linux-vm.nix {
        inherit wawonaVersion;
      }
    else if platform == "appimage"
    then
      if nix-appimage == null || wawonaLinuxUiBin == null
      then throw "mkProduct appimage needs nix-appimage and wawonaLinuxUiBin"
      else
        nix-appimage.lib.${system}.mkAppImage {
          program = "${wawonaLinuxUiBin}/bin/wawona-linux-ui";
          name = "Wawona-${lib.head (lib.splitString "-" system)}.AppImage";
        }
    else if builtins.elem platform xtaskProducts
    then
      throw "mkProduct: ${platform} is a cargo xtask product (cargo xtask build ${platform}), not a Nix derivation. See .github/ci-product-matrix.json"
    else throw "mkProduct: unknown platform '${platform}'";

  linuxPackages =
    lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && wawonaLinuxUiBin != null) {
      wawona-linux = mkProduct { platform = "linux"; };
      wawona = mkProduct { platform = "wawona"; };
      default = mkProduct { platform = "default"; };
      wawona-linux-compositor-host = mkProduct { platform = "linux-compositor-host"; };
      wawona-linux-tray = mkProduct { platform = "linux-tray"; };
      wawona-linux-vm = mkProduct { platform = "linux-vm"; };
    }
    // lib.optionalAttrs (
      pkgs.stdenv.hostPlatform.isLinux && wawonaLinuxUiBin != null && nix-appimage != null
    ) {
      wawona-appimage = mkProduct { platform = "appimage"; };
    };
in {
  inherit mkProduct xtaskProducts linuxPackages;
}
