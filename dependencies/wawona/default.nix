{ lib, pkgs, buildModule, wawonaSrc, wawonaVersion, pkgsAndroid, pkgsIos, rustBackendMacOS ? null, rustBackendIOS ? null, rustBackendIOSSim ? null, rustBackendAndroid ? null, weston ? null, waypipe ? null, androidSDK ? null, androidSrc ? null, ... }:

# Central entry point for Wawona applications.
# Returns: { ios, ipados, macos, watchos, android, linux, linux-vm, wearos, visionos, common, generators }

let
  # Dependency version strings (must match the tags/versions in dependencies/libs/*)
  depVersions = {
    waylandVersion   = "1.23.0";       # dependencies/libs/libwayland/macos.nix  tag
    xkbcommonVersion = "1.7.0";        # dependencies/libs/xkbcommon/macos.nix   tag
    lz4Version       = "1.10.0";       # dependencies/libs/lz4/macos.nix         rev
    zstdVersion      = "1.5.7";        # dependencies/libs/zstd/macos.nix        rev
    libffiVersion    = "3.5.2";        # dependencies/libs/libffi/macos.nix      tag
    sshpassVersion   = "1.10";         # dependencies/libs/sshpass/macos.nix     version
    waypipeVersion   = "0.10.6";       # dependencies/libs/waypipe/macos.nix     tag
  };

  apps = {
    ios = pkgs.callPackage ./ios.nix {
      inherit buildModule wawonaSrc wawonaVersion;
      weston = buildModule.buildForIOS "weston" { };
      targetPkgs = pkgsIos;
      rustBackend = rustBackendIOS;
      rustBackendSim = rustBackendIOSSim;
    };

    macos = pkgs.callPackage ./macos.nix ({
      inherit buildModule wawonaSrc wawonaVersion weston waypipe;
      rustBackend = rustBackendMacOS;
    } // depVersions);

    android = pkgs.callPackage ./android.nix {
      inherit buildModule wawonaVersion androidSDK;
      targetPkgs = pkgsAndroid;
      wawonaSrc = if androidSrc != null then androidSrc else wawonaSrc;
      rustBackend = rustBackendAndroid;
    };

    linux = pkgs.callPackage ./linux.nix {
      inherit wawonaVersion;
      rustBackend = rustBackendMacOS;
    };

    linux-vm = pkgs.callPackage ./linux-vm.nix {
      inherit wawonaVersion;
    };

    wearos = pkgs.callPackage ./wearos.nix {
      inherit wawonaVersion;
    };

    visionos = pkgs.callPackage ./visionos.nix {
      inherit wawonaVersion;
    };

    common = import ./common.nix {
      inherit lib pkgs wawonaSrc;
    };

    generators = {
      xcodegen = pkgs.callPackage ../generators/xcodegen.nix {
         inherit wawonaVersion rustBackendIOS rustBackendIOSSim rustBackendMacOS wawonaSrc buildModule;
         targetPkgs = pkgs;
         rustPlatform = pkgs.rustPlatform;
         libwaylandIOS = buildModule.buildForIOS "libwayland" { };
         xkbcommonIOS = buildModule.buildForIOS "xkbcommon" { };
         pixmanIOS = buildModule.buildForIOS "pixman" { };
         libffiIOS = buildModule.buildForIOS "libffi" { };
         opensslIOS = buildModule.buildForIOS "openssl" { };
         libssh2IOS = buildModule.buildForIOS "libssh2" { };
         mbedtlsIOS = buildModule.buildForIOS "mbedtls" { };
         zstdIOS = buildModule.buildForIOS "zstd" { };
         lz4IOS = buildModule.buildForIOS "lz4" { };
         epollShimIOS = buildModule.buildForIOS "epoll-shim" { };
         waypipeIOS = buildModule.buildForIOS "waypipe" { };
         westonSimpleShmIOS = buildModule.buildForIOS "weston-simple-shm" { };
         westonIOS = buildModule.buildForIOS "weston" { };
         cairoIOS = null;
         pangoIOS = null;
         glibIOS = null;
         harfbuzzIOS = null;
         fontconfigIOS = null;
         freetypeIOS = null;
         libpngIOS = null;
      };
      gradlegen = pkgs.callPackage ../generators/gradlegen.nix ({
        wawonaAndroidProject = apps.android.project or null;
        inherit wawonaSrc wawonaVersion;
        westonSimpleShmSrc = pkgs.callPackage ../libs/weston-simple-shm/patched-src.nix { };
      } // lib.optionalAttrs (androidSDK != null) { androidSdkRoot = androidSDK.sdkRoot; });
    };
  };
in
  apps
