{
  lib,
  pkgs,
  stdenv,
  buildPackages,
  wawonaSrc ? ../..,
  pkgsAndroid ? null,
  pkgsIos ? null,
  androidSDK ? null,
  androidAllowExperimentalFallback ? false,
}:

let
  pkgsMacOS = pkgs;
  iosToolchain = import ./ios-xcodeenv.nix { inherit lib pkgs; };
  callPackageFiltered = path: overrides:
    let
      fn = import path;
    in
    pkgs.callPackage path (builtins.intersectAttrs (builtins.functionArgs fn) overrides);

  pkgsIosRaw = import (pkgs.path) {
    system = pkgs.stdenv.hostPlatform.system;
    crossSystem = (import "${pkgs.path}/lib/systems/examples.nix" { lib = pkgs.lib; }).iphone64;
    config = {
      allowUnsupportedSystem = true;
      allowUnfree = true;
    };
  };

  pkgsAndroidRaw = import (pkgs.path) {
    system = pkgs.stdenv.hostPlatform.system;
    crossSystem = (import "${pkgs.path}/lib/systems/examples.nix" { lib = pkgs.lib; }).aarch64-android-11; # Match our API level
    config = {
      allowUnsupportedSystem = true;
      allowUnfree = true;
    };
    overlays = [
      (self: super: {
        # Some Android cross derivations still invoke gcc for HOSTCC.
        # On Darwin we only have clang/cc, so pin HOSTCC explicitly.
        linuxHeaders = super.linuxHeaders.overrideAttrs (old: {
          makeFlags = (old.makeFlags or [ ]) ++ [ "HOSTCC=cc" ];
        });
      })
    ];
  };

  # Use the raw pkgs if the passed ones are causing recursion or missing
  pkgsIosEffective = if pkgsIos != null then pkgsIos else pkgsIosRaw;
  pkgsAndroidEffective = if pkgsAndroid != null then pkgsAndroid else pkgsAndroidRaw;

  common = import ./common/common.nix { inherit lib pkgs; };
  androidToolchain = import ./android.nix {
    inherit lib pkgs androidSDK;
    allowExperimentalFallback = androidAllowExperimentalFallback;
  };

  # --- Android Toolchain ---
  
  buildForAndroidInternal =
    name: entry:
    let
      # Use global isolated pkgsAndroid
      stdenv = pkgsAndroidEffective.stdenv;
      androidModule = {
        buildForAndroid = buildForAndroidInternal;
      };
      androidArgs = {
        inherit lib pkgs buildPackages common androidSDK androidToolchain stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = androidModule;
      };
      
      # Use registry for standard libraries
      registryEntry = registry.${name} or null;
      androidScript = if registryEntry != null then registryEntry.android or null else null;
    in
    if androidScript != null then
      callPackageFiltered androidScript androidArgs
    else
      # Fallback for platforms/android.nix (which might handle other names)
      (import ../platforms/android.nix {
        inherit lib pkgs buildPackages common androidSDK;
        inherit androidToolchain;
        buildModule = androidModule;
      }).buildForAndroid name entry;

  # --- iOS Toolchain ---

  buildForIOSInternal =
    name: entry:
    let
      normalizedEntry =
        entry
        // lib.optionalAttrs (name == "gl-cts" && !(entry ? buildTargets)) { buildTargets = "glcts-gl"; }
        // lib.optionalAttrs (name == "vulkan-cts" && !(entry ? buildTargets)) { buildTargets = "deqp"; };
      simulator = entry.simulator or false;
      # Use passed pkgsIos instead of pkgs.pkgsCross
      iosModule = {
        buildForIOS = buildForIOSInternal;
      };
      iosArgs = {
        inherit lib pkgs buildPackages common simulator stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = iosModule;
        inherit iosToolchain;
      };

      # Use registry for standard libraries
      registryEntry = registry.${name} or null;
      iosScript = if registryEntry != null then registryEntry.ios or null else null;
    in
    if iosScript != null then
      callPackageFiltered iosScript (iosArgs // normalizedEntry)
    else
      # Fallback for platforms/ios.nix (which might handle other names)
      (import ../platforms/ios.nix {
        inherit lib pkgs buildPackages common simulator iosToolchain;
        buildModule = iosModule;
      }).buildForIOS name normalizedEntry;

  # --- macOS Toolchain ---

  buildForMacOSInternal =
    name: entry:
    let
      macosModule = {
        buildForMacOS = buildForMacOSInternal;
      };
      macosArgs = {
        inherit lib pkgs common stdenv wawonaSrc;
        inherit (pkgs) fetchurl fetchFromGitHub meson ninja pkg-config autoreconfHook zlib libiconv icu;
        libxkbcommon = buildForMacOSInternal "xkbcommon" { };
        wayland = buildForMacOSInternal "libwayland" { };
        wayland-scanner = pkgs.wayland-scanner;
        wayland-protocols = pkgs.wayland-protocols;
        pixman = buildForMacOSInternal "pixman" { };
        epoll-shim = buildForMacOSInternal "epoll-shim" { };
        buildModule = macosModule;
      };

      # Use registry for standard libraries
      registryEntry = registry.${name} or null;
      macosScript = if registryEntry != null then registryEntry.macos or null else null;
    in
    if macosScript != null then
      callPackageFiltered macosScript macosArgs
    else if name == "pixman" then
      pkgs.pixman
    else if name == "libxml2" then
      pkgs.callPackage ../libs/libxml2/macos.nix { }
    else
      # Fallback for platforms/macos.nix (which might handle other names)
      (import ../platforms/macos.nix {
        inherit lib pkgs common;
        buildModule = macosModule;
      }).buildForMacOS name entry;

  # --- Top-level interface ---

  registry = common.registry;

  # macOS package set used by wawona/macos.nix (buildModule.macos.libwayland, etc.)
  macos = {
    libwayland = buildForMacOSInternal "libwayland" { };
  };

in
{
  buildForIOS = buildForIOSInternal;
  buildForMacOS = buildForMacOSInternal;
  buildForAndroid = buildForAndroidInternal;
  inherit androidToolchain macos;
}
