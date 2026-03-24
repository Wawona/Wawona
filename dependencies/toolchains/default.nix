{
  lib,
  pkgs,
  stdenv,
  buildPackages,
  wawonaSrc ? ../..,
  pkgsAndroid ? null,
  pkgsIos ? null,
  androidSDK ? null,
}:

let
  pkgsMacOS = pkgs;

  pkgsIosRaw = import (pkgs.path) {
    inherit (pkgs.stdenv.hostPlatform) system;
    crossSystem = (import "${pkgs.path}/lib/systems/examples.nix" { lib = pkgs.lib; }).iphone64;
    config = {
      allowUnsupportedSystem = true;
      allowUnfree = true;
    };
  };

  pkgsAndroidRaw = import (pkgs.path) {
    inherit (pkgs.stdenv.hostPlatform) system;
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
  androidToolchain = import ./android.nix { inherit lib pkgs androidSDK; };

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
        inherit lib pkgs buildPackages common androidSDK androidToolchain;
        buildModule = androidModule;
      };
    in
    if name == "libwayland" then
      (import ../libs/libwayland/android.nix) androidArgs
    else if name == "expat" then
      (import ../libs/expat/android.nix) androidArgs
    else if name == "libffi" then
      (import ../libs/libffi/android.nix) androidArgs
    else if name == "libxml2" then
      (import ../libs/libxml2/android.nix) androidArgs
    else if name == "waypipe" then
      (import ../libs/waypipe/android.nix) androidArgs
    else if name == "pixman" then
      (import ../libs/pixman/android.nix) androidArgs
    else if name == "xkbcommon" then
      (import ../libs/xkbcommon/android.nix) androidArgs
    else if name == "openssl" then
      (import ../libs/openssl/android.nix) androidArgs
    else if name == "libssh2" then
      (import ../libs/libssh2/android.nix) androidArgs
    else if name == "mbedtls" then
      (import ../libs/mbedtls/android.nix) androidArgs
    else if name == "openssh" then
      (import ../libs/openssh/android.nix) androidArgs
    else if name == "sshpass" then
      (import ../libs/sshpass/android.nix) androidArgs
    else if name == "vulkan-cts" then
      (import ../libs/vulkan-cts/android.nix) {
        inherit lib pkgs buildPackages androidSDK;
      }
    else if name == "gl-cts" then
      (import ../libs/vulkan-cts/gl-cts-android.nix) {
        inherit lib pkgs buildPackages androidSDK;
      }
    else if name == "weston" then
      import ../clients/weston/android.nix {
        inherit lib pkgs stdenv wawonaSrc androidSDK;
        fetchurl = pkgs.fetchurl;
        meson = pkgs.meson;
        ninja = pkgs.ninja;
        pkg-config = pkgs.pkg-config;
        wayland = buildForAndroidInternal "libwayland" {};
        xkbcommon = buildForAndroidInternal "xkbcommon" {};
        pixman = buildForAndroidInternal "pixman" {};
        libffi = buildForAndroidInternal "libffi" {};
        wayland-scanner = pkgs.wayland-scanner;
        wayland-protocols = pkgs.wayland-protocols;
        python3 = pkgs.python3;
        cairo = pkgsAndroidEffective.cairo;
        pango = pkgsAndroidEffective.pango;
        glib = pkgsAndroidEffective.glib;
        harfbuzz = pkgsAndroidEffective.harfbuzz;
        fontconfig = pkgsAndroidEffective.fontconfig;
        freetype = pkgsAndroidEffective.freetype;
        libpng = pkgsAndroidEffective.libpng;
      }
    else
      (import ../platforms/android.nix {
        inherit lib pkgs buildPackages common androidSDK;
        buildModule = androidModule;
      }).buildForAndroid name entry;

  # --- iOS Toolchain ---

  buildForIOSInternal =
    name: entry:
    let
      simulator = entry.simulator or false;
      # Use passed pkgsIos instead of pkgs.pkgsCross
      iosModule = {
        buildForIOS = buildForIOSInternal;
      };
    in
    if name == "libwayland" then
      (import ../libs/libwayland/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "expat" then
      (import ../libs/expat/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "libffi" then
      (import ../libs/libffi/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "libxml2" then
      (import ../libs/libxml2/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "waypipe" then
      (import ../libs/waypipe/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "epoll-shim" then
      (import ../libs/epoll-shim/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "pixman" then
      (import ../libs/pixman/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "mbedtls" then
      (import ../libs/mbedtls/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "libssh2" then
      (import ../libs/libssh2/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "openssl" then
      (import ../libs/openssl/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "openssh" then
      (import ../libs/openssh/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "vulkan-cts" then
      (import ../libs/vulkan-cts/ios.nix) {
        inherit lib pkgs buildPackages;
        buildModule = iosModule;
      }
    else if name == "weston-simple-shm" then
      (import ../libs/weston-simple-shm/ios.nix) {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }
    else if name == "weston" then
      import ../clients/weston/ios.nix {
        inherit lib pkgs stdenv wawonaSrc simulator;
        fetchurl = pkgs.fetchurl;
        meson = pkgs.meson;
        ninja = pkgs.ninja;
        pkg-config = pkgs.pkg-config;
        wayland = buildForIOSInternal "libwayland" { inherit simulator; };
        pixman = buildForIOSInternal "pixman" { inherit simulator; };
        wayland-scanner = pkgs.wayland-scanner;
        wayland-protocols = pkgs.wayland-protocols;
        python3 = pkgs.python3;
        cairo = pkgsIosEffective.cairo;
        pango = pkgsIosEffective.pango;
        glib = pkgsIosEffective.glib;
        harfbuzz = pkgsIosEffective.harfbuzz;
        fontconfig = pkgsIosEffective.fontconfig;
        freetype = pkgsIosEffective.freetype;
        libpng = pkgsIosEffective.libpng;
      }
    else
      (import ../platforms/ios.nix {
        inherit lib pkgs buildPackages common simulator;
        buildModule = iosModule;
      }).buildForIOS name entry;

  # --- macOS Toolchain ---

  buildForMacOSInternal =
    name: entry:
    let
      macosModule = {
        buildForMacOS = buildForMacOSInternal;
      };
    in
    if name == "libwayland" then
      (import ../libs/libwayland/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "expat" then
      (import ../libs/expat/macos.nix) { inherit lib pkgs common; }
    else if name == "libffi" then
      (import ../libs/libffi/macos.nix) { inherit lib pkgs common; }
    else if name == "libxml2" then
      pkgs.callPackage ../libs/libxml2/macos.nix { }
    else if name == "epoll-shim" then
      (import ../libs/epoll-shim/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "waypipe" then
      (import ../libs/waypipe/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "spirv-tools" then
      (import ../libs/spirv-tools/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "sshpass" then
      (import ../libs/sshpass/macos.nix) {
        inherit lib pkgs common;
      }
    else if name == "xkbcommon" then
      (import ../libs/xkbcommon/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "pixman" then
      (import ../libs/pixman/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "tllist" then
      (import ../libs/tllist/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "freetype" then
      (import ../libs/freetype/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "fontconfig" then
      (import ../libs/fontconfig/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "utf8proc" then
      (import ../libs/utf8proc/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "fcft" then
      (import ../libs/fcft/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "foot" then
      (import ../clients/foot/macos.nix) {
        inherit lib pkgs common;
        buildModule = macosModule;
      }
    else if name == "vulkan-cts" then
      (import ../libs/vulkan-cts/macos.nix) {
        inherit lib pkgs;
      }
    else
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
