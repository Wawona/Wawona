{ lib, pkgs, buildModule, wawonaSrc, wawonaVersion, pkgsAndroid, pkgsIos, rustBackendMacOS ? null, rustBackendIOS ? null, rustBackendIOSSim ? null, rustBackendAndroid ? null, weston ? null, waypipe ? null, androidSDK ? null, androidSrc ? null, ... }:

# Central entry point for Wawona applications.
# Returns: { ios, ipados, macos, watchos, android, linux, linux-vm, visionos, common, generators }

let
  # Dependency version strings (registry entries in wwn-toolchain / wwn-* repos)
  depVersions = {
    waylandVersion   = "1.23.0";
    xkbcommonVersion = "1.7.0";
    lz4Version       = "1.10.0";
    zstdVersion      = "1.5.7";
    libffiVersion    = "3.5.2";
    sshpassVersion   = "1.10";
    waypipeVersion   = "0.10.6";
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
      foot = buildModule.buildForMacOS "foot" { };
      fastfetch = buildModule.buildForMacOS "fastfetch" { };
      phoon = buildModule.buildForMacOS "phoon" { };
      wawonaWasm = buildModule.buildForMacOS "wawona-wasm" { };
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
      # phoon (wwn-phoon-rs): clean-room Rust moon-phase utility, bundled on the
      # Linux target too (native host build via the toolchain).
      phoon = buildModule.buildForLinux "phoon" { };
    };

    linux-vm = pkgs.callPackage ./linux-vm.nix {
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
        westonSimpleShmSrc = pkgs.callPackage pkgs.westonSimpleShmPatchedSrcNix { };
      } // lib.optionalAttrs (androidSDK != null) { androidSdkRoot = androidSDK.sdkRoot; });
    };
  };
in
  apps
