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
  iosToolchain = import ../apple/default.nix { inherit lib pkgs; };
  firstNonNull = values:
    let
      filtered = builtins.filter (value: value != null) values;
    in
    if filtered == [ ] then null else builtins.head filtered;
  callPackageFiltered = path: overrides:
    let
      fn = import path;
      fnArgs = builtins.functionArgs fn;
      iosSiblingPath = (builtins.dirOf path) + "/ios.nix";
      hasIosSibling = builtins.pathExists iosSiblingPath;
      iosSiblingFnArgs = if hasIosSibling then builtins.functionArgs (import iosSiblingPath) else { };
    in
    if fnArgs == { } then
      if hasIosSibling && iosSiblingFnArgs != { } then
        pkgs.callPackage path (builtins.intersectAttrs iosSiblingFnArgs overrides)
      else
        pkgs.callPackage path overrides
    else
      pkgs.callPackage path (builtins.intersectAttrs fnArgs overrides);

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
      normalizedEntry = entry;
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
      iosScript =
        if registryEntry != null then
          if simulator then
            registryEntry.iosSim or registryEntry.iosDevice or registryEntry.ios or null
          else
            registryEntry.iosDevice or registryEntry.ios or null
        else
          null;
    in
    if iosScript != null then
      callPackageFiltered iosScript (iosArgs // normalizedEntry)
    else
      # Fallback for platforms/ios.nix (which might handle other names)
      (import ../platforms/ios.nix {
        inherit lib pkgs buildPackages common simulator iosToolchain;
        buildModule = iosModule;
      }).buildForIOS name normalizedEntry;

  # --- iPadOS Toolchain ---
  # iPadOS is a first-class platform and does not fall back to iOS recipes.
  buildForTVOSInternal =
    name: entry:
    let
      normalizedEntry = entry // { simulator = entry.simulator or false; };
      simulator = normalizedEntry.simulator;
      tvosModule = {
        buildForTVOS = buildForTVOSInternal;
        # Shared Apple recipes should resolve nested deps through tvOS.
        buildForIOS = buildForTVOSInternal;
      };
      tvosIosToolchain = iosToolchain // {
        isTVOSToolchain = true;
        mkIOSBuildEnv = { simulator ? false, minVersion ? "17.0" }:
          iosToolchain.mkAppleEnv {
            sdkName = if simulator then "appletvsimulator" else "appletvos";
            platform = "tvos";
            inherit simulator minVersion;
          };
      };
      tvosArgs = {
        inherit lib pkgs buildPackages common simulator stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = tvosModule;
        iosToolchain = tvosIosToolchain;
      };
      registryEntry = registry.${name} or null;
      tvosScript =
        if registryEntry != null then
          if simulator then
            registryEntry.tvosSim or registryEntry.tvosDevice or registryEntry.tvos or null
          else
            registryEntry.tvosDevice or registryEntry.tvos or null
        else
          null;
    in
    if tvosScript != null then
      callPackageFiltered tvosScript (tvosArgs // normalizedEntry)
    else
      throw "Missing tvOS module mapping for '${name}' in dependencies/toolchains/common/registry.nix";

  # --- iPadOS Toolchain ---
  # iPadOS is a first-class platform and does not fall back to iOS recipes.
  buildForIPadOSInternal =
    name: entry:
    let
      normalizedEntry = entry // { simulator = entry.simulator or false; };
      simulator = normalizedEntry.simulator;
      ipadosModule = {
        buildForIPadOS = buildForIPadOSInternal;
        buildForIOS = buildForIOSInternal;
      };
      ipadosArgs = {
        inherit lib pkgs buildPackages common simulator stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = ipadosModule;
        inherit iosToolchain;
      };
      registryEntry = registry.${name} or null;
      ipadosScript =
        if registryEntry != null then
          if simulator then
            registryEntry.ipadosSim or registryEntry.ipadosDevice or registryEntry.ipados or null
          else
            registryEntry.ipadosDevice or registryEntry.ipados or null
        else
          null;
    in
    if ipadosScript != null then
      callPackageFiltered ipadosScript (ipadosArgs // normalizedEntry)
    else
      throw "Missing iPadOS module mapping for '${name}' in dependencies/toolchains/common/registry.nix";

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

  # --- watchOS Toolchain ---

  buildForWatchOSInternal =
    name: entry:
    let
      simulator = entry.simulator or false;
      watchosModule = {
        buildForWatchOS = buildForWatchOSInternal;
        # Allow watchos.nix files that call buildModule.buildForIOS to fall through
        buildForIOS = buildForIOSInternal;
      };
      watchosArgs = {
        inherit lib pkgs buildPackages common simulator stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = watchosModule;
        iosToolchain = iosToolchain;
      };

      registryEntry = registry.${name} or null;
      watchosScript =
        if registryEntry != null then
          if simulator then
            registryEntry.watchosSim or registryEntry.watchosDevice or registryEntry.watchos or null
          else
            registryEntry.watchosDevice or registryEntry.watchos or null
        else
          null;
    in
    if watchosScript != null then
      callPackageFiltered watchosScript (watchosArgs // entry)
    else
      # Explicit watchOS policy: allow fallback to iOS when watchOS recipe is absent.
      buildForIOSInternal name entry;

  # --- visionOS Toolchain ---

  buildForVisionOSInternal =
    name: entry:
    let
      normalizedEntry = entry // { simulator = entry.simulator or false; };
      simulator = normalizedEntry.simulator;
      visionosModule = {
        buildForVisionOS = buildForVisionOSInternal;
        # Strict visionOS policy: shared iOS recipes must resolve nested deps
        # through visionOS, never through iOS outputs.
        buildForIOS = buildForVisionOSInternal;
      };
      visionosIosToolchain = iosToolchain // {
        # Consumed by shared iOS recipes (e.g. xkbcommon) to pick matching native deps.
        isVisionOSToolchain = true;
        mkIOSBuildEnv = { simulator ? false, minVersion ? "26.0" }:
          iosToolchain.mkAppleEnv {
            sdkName = if simulator then "xrsimulator" else "xros";
            platform = "visionos";
            inherit simulator minVersion;
          };
      };
      visionosArgs = {
        inherit lib pkgs buildPackages common simulator stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = visionosModule;
        iosToolchain = visionosIosToolchain;
      };
      registryEntry = registry.${name} or null;
      visionosScript =
        if registryEntry != null then
          if simulator then
            registryEntry.visionosSim or registryEntry.visionosDevice or registryEntry.visionos or null
          else
            registryEntry.visionosDevice or registryEntry.visionos or null
        else
          null;
    in
    if visionosScript != null then
      callPackageFiltered visionosScript (visionosArgs // normalizedEntry)
    else
      throw "Missing visionOS module mapping for '${name}' in dependencies/toolchains/common/registry.nix";

  # --- WearOS Toolchain ---

  buildForWearOSInternal =
    name: entry:
    let
      emulator = entry.emulator or false;
      stdenv = pkgsAndroidEffective.stdenv;
      wearosModule = {
        buildForWearOS = buildForWearOSInternal;
        # Allow wearos.nix recipes to intentionally reuse Android modules.
        buildForAndroid = buildForAndroidInternal;
      };
      wearosArgs = {
        inherit lib pkgs buildPackages common androidSDK androidToolchain stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = wearosModule;
      };
      registryEntry = registry.${name} or null;
      wearosScript =
        if registryEntry != null then
          if emulator then
            firstNonNull [
              (registryEntry.wearosEmulator or null)
              (registryEntry.wearosDevice or null)
              (registryEntry.wearos or null)
              (registryEntry.androidEmulator or null)
              (registryEntry.androidDevice or null)
              (registryEntry.android or null)
            ]
          else
            firstNonNull [
              (registryEntry.wearosDevice or null)
              (registryEntry.wearos or null)
              (registryEntry.androidDevice or null)
              (registryEntry.android or null)
            ]
        else
          null;
    in
    if wearosScript != null then
      callPackageFiltered wearosScript (wearosArgs // entry)
    else
      (import ../platforms/wearos.nix {
        inherit lib pkgs buildPackages common androidSDK androidToolchain;
        buildModule = wearosModule;
      }).buildForWearOS name entry;

  # --- Linux Toolchain ---

  buildForLinuxInternal =
    name: entry:
    let
      linuxModule = {
        buildForLinux = buildForLinuxInternal;
      };
      linuxArgs = {
        inherit lib pkgs buildPackages common stdenv wawonaSrc;
        inherit (pkgs) fetchurl meson ninja pkg-config;
        buildModule = linuxModule;
      };
      registryEntry = registry.${name} or null;
      macosBaseScript = if registryEntry != null then registryEntry.macos or null else null;
      derivedLinuxScript =
        if macosBaseScript != null then
          let
            candidate = builtins.replaceStrings [ "/macos.nix" ] [ "/linux.nix" ] (toString macosBaseScript);
          in
          if builtins.pathExists candidate then candidate else null
        else
          null;
      linuxScript =
        if registryEntry != null then
          firstNonNull [
            (registryEntry.linuxNative or null)
            (registryEntry.linux or null)
            derivedLinuxScript
          ]
        else
          derivedLinuxScript;
    in
    if linuxScript != null then
      callPackageFiltered linuxScript (linuxArgs // entry)
    else
      (import ../platforms/linux.nix {
        inherit lib pkgs buildPackages common;
        buildModule = linuxModule;
      }).buildForLinux name entry;

  # --- Top-level interface ---

  registry = common.registry;

  # macOS package set used by wawona/macos.nix (buildModule.macos.libwayland, etc.)
  macos = {
    libwayland = buildForMacOSInternal "libwayland" { };
  };

in
{
  buildForIOS = buildForIOSInternal;
  buildForTVOS = buildForTVOSInternal;
  buildForIPadOS = buildForIPadOSInternal;
  buildForWatchOS = buildForWatchOSInternal;
  buildForVisionOS = buildForVisionOSInternal;
  buildForWearOS = buildForWearOSInternal;
  buildForLinux = buildForLinuxInternal;
  buildForMacOS = buildForMacOSInternal;
  buildForAndroid = buildForAndroidInternal;
  inherit androidToolchain macos;
}
