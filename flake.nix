{
  description = "Wawona Compositor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/5585cc3ee71bdd8d9ee255523f11b920138fa688";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    crate2nix.url = "github:nix-community/crate2nix";
    "nix-xcodeenvtests" = {
      url = "github:svanderburg/nix-xcodeenvtests";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, android-nixpkgs, rust-overlay, crate2nix, ... }:
  let
    linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
    darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
    systemsList = linuxSystems ++ darwinSystems;
    skipOverlay = (self: super: {
      skip = super.callPackage ./dependencies/tools/skip.nix {
        openjdk = super.jdk17;
      };
    });

    pkgsFor = system:
      let
        isDarwin = (system == "x86_64-darwin" || system == "aarch64-darwin");
        customOverlays = if isDarwin then [
          (import rust-overlay)
          (self: super: {
            rustToolchain = super.rust-bin.stable.latest.default.override {
              targets = [
                "aarch64-apple-ios"
                "aarch64-apple-ios-sim"
                # aarch64-apple-watchos is a Rust tier-3 target not distributed
                # in stable prebuilt binaries; add it here once it becomes
                # available in a release channel or switch to nightly:
                # "aarch64-apple-watchos"
                # "aarch64-apple-watchos-sim"
              ];
            };
            rustToolchainAndroid = super.rust-bin.stable.latest.default.override {
              targets = [ "aarch64-linux-android" ];
            };
            rustPlatformAndroid = super.makeRustPlatform {
              cargo = self.rustToolchainAndroid;
              rustc = self.rustToolchainAndroid;
            };
            rustPlatform = super.makeRustPlatform {
              cargo = self.rustToolchain;
              rustc = self.rustToolchain;
            };
          })
          (self: super: {
            linuxHeaders = super.linuxHeaders.overrideAttrs (old: {
              makeFlags = (old.makeFlags or []) ++ [ "HOSTCC=cc" ];
            });
            makeLinuxHeaders = args: (super.makeLinuxHeaders args).overrideAttrs (old: {
              preConfigure = (old.preConfigure or "") + ''
                mkdir -p $TMPDIR/gcc-shim
                ln -s $(command -v cc) $TMPDIR/gcc-shim/gcc
                ln -s $(command -v c++) $TMPDIR/gcc-shim/g++
                export PATH=$TMPDIR/gcc-shim:$PATH
              '';
            });
            llvmPackages_21 = if super.stdenv.targetPlatform.isAndroid then super.llvmPackages_21 // {
              compiler-rt = super.llvmPackages_21.compiler-rt.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  sed -i 's|#include <pthread.h>|typedef int pthread_once_t; int pthread_once(pthread_once_t *, void (*)(void));|' lib/builtins/os_version_check.c || true
                '';
              });
            } else super.llvmPackages_21;
          })
          skipOverlay
        ] else [ skipOverlay ];
      in import nixpkgs {
        inherit system;
        overlays = customOverlays;
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
          android_sdk.accept_license = true;
        };
      };

    srcFor = pkgs:
      pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let 
            relPath = pkgs.lib.removePrefix (toString ./.) (toString path);
            isImportant = pkgs.lib.any (p: pkgs.lib.hasPrefix p relPath) [
              "/src" "/Sources" "/Darwin" "/android" "/deps" "/protocols" "/scripts" "/include"
              "/VERSION" "/Cargo" "/Package.swift" "/Package.resolved" "/build.rs" "/flake"
            ];
            isIgnored = pkgs.lib.any (p: pkgs.lib.hasInfix p relPath) [
              "/.git" "/result" "/.direnv" "/target" "/.gemini" "/Inspiration" "/.idea" "/.vscode" "/.DS_Store"
            ];
          in (relPath == "") || (isImportant && !isIgnored);
      };

    # Use a minimal pkgs for version lookup to avoid recursion
    bootstrapPkgs = import nixpkgs { system = "x86_64-linux"; };
    wawonaVersion = bootstrapPkgs.lib.removeSuffix "\n" (builtins.readFile (./. + "/VERSION"));
    waypipe-src = bootstrapPkgs.fetchFromGitLab {
      owner = "mstoeckl"; repo = "waypipe"; rev = "v0.11.0";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };

    getPackagesForSystem = system: pkgs:
      let
        isLinuxHost = builtins.elem system linuxSystems;

        # Clean package set for Android — only the rust-overlay is included
        # to provide pkgs.rust-bin for waypipe/android.nix. The second and third
        # host overlays are excluded to prevent cargo → libsecret → gjs → 
        # spidermonkey → cbindgen recursive evaluation chains.
        androidPkgs = if isLinuxHost then (import nixpkgs {
          inherit system;
          config = { allowUnfree = true; android_sdk.accept_license = true; };
          overlays = [
            (import rust-overlay)
            (self: super: {
              rustToolchainAndroid = super.rust-bin.stable.latest.default.override {
                targets = [ "aarch64-linux-android" ];
              };
              rustPlatformAndroid = super.makeRustPlatform {
                cargo = self.rustToolchainAndroid;
                rustc = self.rustToolchainAndroid;
              };
            })
            skipOverlay
          ];
        }) else pkgs;

        androidConfig = import ./dependencies/android/sdk-config.nix {
          inherit system;
          lib = androidPkgs.lib;
        };
        androidAllowExperimentalFallback =
          # In pure flake eval, getEnv is empty, so allow fallback explicitly on
          # arm64 hosts where native NDK host prebuilts are not currently shipped.
          ((builtins.getEnv "WAWONA_ANDROID_EXPERIMENTAL_FALLBACK") == "1")
          || (builtins.elem system [ "aarch64-linux" "aarch64-darwin" ]);

        pkgsIos = if !isLinuxHost then pkgs.pkgsCross.iphone64 else null;
        
        # Define a clean cross-set
        pkgsAndroidCross = androidPkgs.pkgsCross.aarch64-android;
        androidSDK =
          let
            androidComposition = androidPkgs.androidenv.composeAndroidPackages {
              cmdLineToolsVersion = "latest";
              platformToolsVersion = "latest";
              buildToolsVersions = [ androidConfig.buildToolsVersion ];
              platformVersions = [ (toString androidConfig.compileSdk) ];
              abiVersions = [ "arm64-v8a" ];
              systemImageTypes = [ "google_apis_playstore" ];
              includeEmulator = androidConfig.emulatorSupported;
              includeSystemImages = androidConfig.emulatorSupported;
              includeNDK = true;
              includeCmake = true;
              ndkVersions = [ androidConfig.ndkVersion ];
              cmakeVersions = [ androidConfig.cmakeVersion ];
              useGoogleAPIs = false;
            };
            sdkRoot = "${androidComposition.androidsdk}/libexec/android-sdk";
          in {
            androidsdk = androidComposition.androidsdk;
            inherit sdkRoot;
            platformTools = androidComposition.platform-tools;
            cmdlineTools = androidComposition.androidsdk;
            buildTools = "${sdkRoot}/build-tools/${androidConfig.buildToolsVersion}";
            cmake = "${sdkRoot}/cmake/${androidConfig.cmakeVersion}";
            ndk = "${sdkRoot}/ndk/${androidConfig.ndkVersion}";
            emulator = if androidConfig.emulatorSupported then androidComposition.emulator else androidComposition.androidsdk;
            systemImage = "${sdkRoot}/system-images/android-${toString androidConfig.compileSdk}/google_apis_playstore/arm64-v8a";
            androidSdkPackages = { };
            inherit androidConfig;
          };

        src = srcFor pkgs;
        wawonaSrc = ./.;

        toolchains = import ./dependencies/toolchains {
          inherit (pkgs) lib pkgs stdenv buildPackages;
          inherit wawonaSrc androidSDK;
          pkgsAndroid = pkgsAndroidCross;
          pkgsIos = pkgsIos;
          inherit androidAllowExperimentalFallback;
        };
        appleToolchain = import ./dependencies/apple {
          inherit (pkgs) lib pkgs;
          nixXcodeenvtests = inputs."nix-xcodeenvtests";
        };
        jdk17 = androidPkgs.jdk17;
        gradle = androidPkgs.gradle.override { java = jdk17; };
        
        # On Linux, create a separate toolchains instance using the overlay-free
        # androidPkgs to prevent rust-overlay from triggering recursive evaluation
        # chains through cargo → libsecret → gjs → spidermonkey → cbindgen.
        toolchainsAndroid = if isLinuxHost then import ./dependencies/toolchains {
          inherit (androidPkgs) lib stdenv buildPackages;
          pkgs = androidPkgs;
          inherit wawonaSrc androidSDK;
          pkgsAndroid = pkgsAndroidCross;
          pkgsIos = null;
          inherit androidAllowExperimentalFallback;
        } else toolchains;

        androidUtils = import ./dependencies/utils/android-wrapper.nix { 
          lib = androidPkgs.lib; pkgs = androidPkgs; inherit androidSDK; 
        };


        waypipe-patched-android = import ./dependencies/libs/waypipe/waypipe-patched-src.nix {
          pkgs = androidPkgs;
          inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-android.sh; platform = "android";
        };

        workspace-src-android = androidPkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; platform = "android"; inherit wawonaVersion;
        };

        backend-android = androidPkgs.callPackage ./dependencies/wawona/rust-backend-android-brp.nix {
          inherit wawonaVersion androidSDK;
          androidToolchain = if isLinuxHost then toolchainsAndroid.androidToolchain else toolchains.androidToolchain;
          workspaceSrc = workspace-src-android;
          nativeDeps = {
            xkbcommon = toolchainsAndroid.buildForAndroid "xkbcommon" {};
            libwayland = toolchainsAndroid.buildForAndroid "libwayland" {};
            zstd = toolchainsAndroid.buildForAndroid "zstd" {};
            lz4 = toolchainsAndroid.buildForAndroid "lz4" {};
            pixman = toolchainsAndroid.buildForAndroid "pixman" {};
            openssl = toolchainsAndroid.buildForAndroid "openssl" {};
            libffi = toolchainsAndroid.buildForAndroid "libffi" {};
            expat = toolchainsAndroid.buildForAndroid "expat" {};
            libxml2 = toolchainsAndroid.buildForAndroid "libxml2" {};
          };
        };

        wawonaAndroidPkg = import ./dependencies/wawona/android.nix {
          pkgs = androidPkgs;
          buildModule = toolchainsAndroid;
          inherit (androidPkgs) lib stdenv clang pkg-config unzip zip patchelf file util-linux glslang mesa;
          inherit gradle jdk17 wawonaSrc androidSDK androidUtils;
          androidToolchain = toolchainsAndroid.androidToolchain;
          rustBackend = backend-android;
          targetPkgs = pkgsAndroidCross;
          waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
        };
        wawonaWearAndroidPkg = import ./dependencies/wawona/android.nix {
          pkgs = androidPkgs;
          buildModule = toolchainsAndroid;
          inherit (androidPkgs) lib stdenv clang pkg-config unzip zip patchelf file util-linux glslang mesa;
          inherit gradle jdk17 wawonaSrc androidSDK androidUtils;
          androidToolchain = toolchainsAndroid.androidToolchain;
          rustBackend = backend-android;
          targetPkgs = pkgsAndroidCross;
          waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
          appTarget = "wearos";
        };

        androidToolchainSanity = import ./dependencies/toolchains/android-toolchain-sanity.nix {
          pkgs = androidPkgs;
          androidToolchain = toolchainsAndroid.androidToolchain;
        };

        gradlegenPkg = pkgs.callPackage ./dependencies/generators/gradlegen.nix ({
          wawonaSrc = if isLinuxHost then ./. else src;
          inherit wawonaVersion;
        } // (pkgs.lib.optionalAttrs isLinuxHost {
          iconAssets = null;
        }) // (pkgs.lib.optionalAttrs (!isLinuxHost) {
          iconAssets = null;
          wawonaAndroidProject = wawonaAndroidPkg.project;
        }));

        # ── Cross-Platform Packages ───────────────────────────────────────
        commonPackages = rec {
          local-runner = pkgs.callPackage ./scripts/local-runner.nix { };
          wawona-shell = pkgs.callPackage ./dependencies/clients/wawona-shell { };
          wawona-tools = pkgs.callPackage ./dependencies/clients/wawona-tools { };
          skip = pkgs.skip;
          
          # Weston and Waypipe (Native on Linux, Cross-wrapped on Darwin)
          weston = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "weston" {} else pkgs.weston;
          waypipe = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "waypipe" { } else pkgs.waypipe;
          
          # Wawona (Native on Linux, Cross-wrapped on Darwin)
          wawona = if pkgs.stdenv.isDarwin 
            then (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs 
              (pkgs.callPackage ./dependencies/wawona/macos.nix {
                buildModule = toolchains; inherit wawonaSrc wawonaVersion;
                waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
                rustBackend = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
                  inherit crate2nix wawonaVersion toolchains nixpkgs;
                  workspaceSrc = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
                    wawonaSrc = src; 
                    waypipeSrc = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
                      inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh; platform = "macos";
                    };
                    platform = "macos"; inherit wawonaVersion;
                  };
                  platform = "macos"; nativeDeps = {
                    libwayland = toolchains.buildForMacOS "libwayland" { };
                    xkbcommon = toolchains.buildForMacOS "xkbcommon" { };
                    waypipe = toolchains.buildForMacOS "waypipe" { };
                    sshpass = toolchains.buildForMacOS "sshpass" { };
                  };
                };
                xcodeProject = (pkgs.callPackage ./dependencies/generators/xcodegen.nix {
                   inherit wawonaVersion wawonaSrc;
                   macosBackend = null;
                   iosBackend = null;
                   iosSimBackend = null;
                   macosDeps = {};
                   iosDeps = {};
                   iosSimDeps = {};
                   macosWeston = toolchains.buildForMacOS "weston" { };
                }).project;
              })
            else pkgs.hello; # TODO: Add Linux wrapper
        };

        packages = commonPackages // (pkgs.lib.optionalAttrs (isLinuxHost || androidSDK != null) {
          wawona-android = wawonaAndroidPkg;
          wawona-wearos-android = wawonaWearAndroidPkg;
          wawona-android-backend = backend-android;
          android-toolchain-sanity = androidToolchainSanity;
          gradlegen = gradlegenPkg.generateScript;
          wawona-android-project = gradlegenPkg.generateScript;
          wawona-android-provision = androidUtils.provisionAndroidScript;
          wawona-wearos = pkgs.callPackage ./dependencies/wawona/wearos.nix {
            inherit wawonaVersion androidSDK;
            wearAndroidPackage = "wawona-wearos-android";
          };
        }) // (pkgs.lib.optionalAttrs isLinuxHost {
          wawona-linux = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
          };
          wawona-linux-vm = pkgs.callPackage ./dependencies/wawona/linux-vm.nix {
            inherit wawonaVersion;
          };
        }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          teamId = let value = builtins.getEnv "TEAM_ID"; in if value == "" then null else value;
          apple = import ./dependencies/apple {
            inherit (pkgs) lib pkgs;
            TEAM_ID = teamId;
            nixXcodeenvtests = inputs."nix-xcodeenvtests";
          };
          missingTeamRelease = name: pkgs.runCommand name { } ''
            echo "Set TEAM_ID and build with --impure to produce signed iOS release artifacts." >&2
            exit 1
          '';
          waypipe-patched-macos = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh; platform = "macos";
          };
          waypipe-patched-ios = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh; platform = "ios";
          };
          weston-terminal-pkg = pkgs.runCommand "weston-terminal" { } ''
            mkdir -p "$out/bin"
            ln -s "${commonPackages.weston}/bin/weston-terminal" "$out/bin/weston-terminal"
          '';
          workspace-src-macos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-macos; platform = "macos"; inherit wawonaVersion;
          };
          workspace-src-ios = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-ios; platform = "ios"; inherit wawonaVersion;
          };
          macosDeps = {
            libwayland = toolchains.buildForMacOS "libwayland" { };
            xkbcommon = toolchains.buildForMacOS "xkbcommon" { };
            waypipe = toolchains.buildForMacOS "waypipe" { };
            sshpass = toolchains.buildForMacOS "sshpass" { };
          };
          iosDeviceDeps = {
            xkbcommon = toolchains.buildForIOS "xkbcommon" {}; libffi = toolchains.buildForIOS "libffi" {};
            libwayland = toolchains.buildForIOS "libwayland" {}; zstd = toolchains.buildForIOS "zstd" {};
            lz4 = toolchains.buildForIOS "lz4" {}; zlib = toolchains.buildForIOS "zlib" {};
            libssh2 = toolchains.buildForIOS "libssh2" {}; mbedtls = toolchains.buildForIOS "mbedtls" {};
            openssl = toolchains.buildForIOS "openssl" {}; ffmpeg = toolchains.buildForIOS "ffmpeg" {};
            epoll-shim = toolchains.buildForIOS "epoll-shim" {}; waypipe = toolchains.buildForIOS "waypipe" {};
            weston = toolchains.buildForIOS "weston" {}; weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" {}; pixman = toolchains.buildForIOS "pixman" {};
            sshpass = toolchains.buildForIOS "sshpass" {};
            foot = toolchains.buildForIOS "foot" {};
          };
          iosSimDeps = {
            xkbcommon = toolchains.buildForIOS "xkbcommon" { simulator = true; };
            libffi = toolchains.buildForIOS "libffi" { simulator = true; };
            libwayland = toolchains.buildForIOS "libwayland" { simulator = true; };
            zstd = toolchains.buildForIOS "zstd" { simulator = true; };
            lz4 = toolchains.buildForIOS "lz4" { simulator = true; };
            zlib = toolchains.buildForIOS "zlib" { simulator = true; };
            libssh2 = toolchains.buildForIOS "libssh2" { simulator = true; };
            mbedtls = toolchains.buildForIOS "mbedtls" { simulator = true; };
            openssl = toolchains.buildForIOS "openssl" { simulator = true; };
            ffmpeg = toolchains.buildForIOS "ffmpeg" { simulator = true; };
            epoll-shim = toolchains.buildForIOS "epoll-shim" { simulator = true; };
            waypipe = toolchains.buildForIOS "waypipe" { simulator = true; };
            weston = toolchains.buildForIOS "weston" { simulator = true; };
            weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" { simulator = true; };
            pixman = toolchains.buildForIOS "pixman" { simulator = true; };
            sshpass = toolchains.buildForIOS "sshpass" { simulator = true; };
            foot = toolchains.buildForIOS "foot" { simulator = true; };
          };
          ipadosDeviceDeps = {
            xkbcommon = toolchains.buildForIPadOS "xkbcommon" {}; libffi = toolchains.buildForIPadOS "libffi" {};
            libwayland = toolchains.buildForIPadOS "libwayland" {}; zstd = toolchains.buildForIPadOS "zstd" {};
            lz4 = toolchains.buildForIPadOS "lz4" {}; zlib = toolchains.buildForIPadOS "zlib" {};
            libssh2 = toolchains.buildForIPadOS "libssh2" {}; mbedtls = toolchains.buildForIPadOS "mbedtls" {};
            openssl = toolchains.buildForIPadOS "openssl" {}; ffmpeg = toolchains.buildForIPadOS "ffmpeg" {};
            epoll-shim = toolchains.buildForIPadOS "epoll-shim" {}; waypipe = toolchains.buildForIPadOS "waypipe" {};
            weston = toolchains.buildForIPadOS "weston" {}; weston-simple-shm = toolchains.buildForIPadOS "weston-simple-shm" {}; pixman = toolchains.buildForIPadOS "pixman" {};
            sshpass = toolchains.buildForIPadOS "sshpass" {};
            foot = toolchains.buildForIPadOS "foot" {};
          };
          ipadosSimDeps = {
            xkbcommon = toolchains.buildForIPadOS "xkbcommon" { simulator = true; };
            libffi = toolchains.buildForIPadOS "libffi" { simulator = true; };
            libwayland = toolchains.buildForIPadOS "libwayland" { simulator = true; };
            zstd = toolchains.buildForIPadOS "zstd" { simulator = true; };
            lz4 = toolchains.buildForIPadOS "lz4" { simulator = true; };
            zlib = toolchains.buildForIPadOS "zlib" { simulator = true; };
            libssh2 = toolchains.buildForIPadOS "libssh2" { simulator = true; };
            mbedtls = toolchains.buildForIPadOS "mbedtls" { simulator = true; };
            openssl = toolchains.buildForIPadOS "openssl" { simulator = true; };
            ffmpeg = toolchains.buildForIPadOS "ffmpeg" { simulator = true; };
            epoll-shim = toolchains.buildForIPadOS "epoll-shim" { simulator = true; };
            waypipe = toolchains.buildForIPadOS "waypipe" { simulator = true; };
            weston = toolchains.buildForIPadOS "weston" { simulator = true; };
            weston-simple-shm = toolchains.buildForIPadOS "weston-simple-shm" { simulator = true; };
            pixman = toolchains.buildForIPadOS "pixman" { simulator = true; };
            sshpass = toolchains.buildForIPadOS "sshpass" { simulator = true; };
            foot = toolchains.buildForIPadOS "foot" { simulator = true; };
          };
          # Compatibility aliases for existing callers
          iosDeps = iosDeviceDeps;
          backend-macos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-macos; platform = "macos"; nativeDeps = macosDeps;
          };
          backend-ios = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "ios"; nativeDeps = iosDeps;
          };
          backend-ios-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "ios"; simulator = true; nativeDeps = iosSimDeps;
          };
          # Rewrite LC_BUILD_VERSION in iOS-built .a archives so the watchOS
          # linker accepts them.  The arm64 code is identical; only the Mach-O
          # platform tag differs.  vtool (ships with Xcode) does the rewrite.
          replatformForWatchOS = { drv, simulator ? false }:
            let
              platformName = if simulator then "watchossim" else "watchos";
              minVer = "10.0";
            in pkgs.runCommand "${drv.name}-watchos-replatform" {
              __noChroot = true;
            } ''
              cp -r ${drv} $out
              chmod -R u+w $out

              # Locate Xcode toolchain (same pattern as other watchos.nix recipes)
              unset DEVELOPER_DIR
              SDK=$(/usr/bin/xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null || true)
              if [ -n "$SDK" ]; then
                export DEVELOPER_DIR=$(echo "$SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
              fi
              [ -z "$DEVELOPER_DIR" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p 2>/dev/null || true)
              [ -z "$DEVELOPER_DIR" ] && DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
              TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"

              VTOOL="$TOOLCHAIN/vtool"
              AR="$TOOLCHAIN/ar"
              RANLIB="$TOOLCHAIN/ranlib"

              if [ ! -x "$VTOOL" ]; then
                echo "ERROR: vtool not found at $VTOOL" >&2
                exit 1
              fi

              for archive in $out/lib/*.a; do
                [ -f "$archive" ] || continue
                tmpdir=$(mktemp -d)
                (
                  cd "$tmpdir"
                  "$AR" x "$archive"
                  for obj in *; do
                    [ -f "$obj" ] || continue
                    "$VTOOL" -set-build-version ${platformName} ${minVer} ${minVer} \
                             -replace -output "$obj.tmp" "$obj" 2>/dev/null && mv "$obj.tmp" "$obj" || true
                  done
                  rm -f "$archive"
                  "$AR" rcs "$archive" * 2>/dev/null || true
                  "$RANLIB" "$archive" 2>/dev/null || true
                )
                rm -rf "$tmpdir"
              done
            '';

          watchosDeviceDeps = {
            libffi            = toolchains.buildForWatchOS "libffi"            {};
            libwayland        = toolchains.buildForWatchOS "libwayland"        {};
            epoll-shim        = toolchains.buildForWatchOS "epoll-shim"        {};
            pixman            = toolchains.buildForWatchOS "pixman"            {};
            weston            = toolchains.buildForWatchOS "weston"            {};
            weston-simple-shm = toolchains.buildForWatchOS "weston-simple-shm" {};
            foot              = toolchains.buildForWatchOS "foot"              {};
            waypipe           = replatformForWatchOS { drv = toolchains.buildForIOS "waypipe"  {}; };
            libssh2           = replatformForWatchOS { drv = toolchains.buildForIOS "libssh2"  {}; };
            openssl           = replatformForWatchOS { drv = toolchains.buildForIOS "openssl"  {}; };
            mbedtls           = replatformForWatchOS { drv = toolchains.buildForIOS "mbedtls"  {}; };
            zstd              = replatformForWatchOS { drv = toolchains.buildForIOS "zstd"     {}; };
            lz4               = replatformForWatchOS { drv = toolchains.buildForIOS "lz4"      {}; };
            sshpass           = replatformForWatchOS { drv = toolchains.buildForIOS "sshpass"  {}; };
          };
          watchosSimDeps = {
            libffi            = toolchains.buildForWatchOS "libffi"            { simulator = true; };
            libwayland        = toolchains.buildForWatchOS "libwayland"        { simulator = true; };
            epoll-shim        = toolchains.buildForWatchOS "epoll-shim"        { simulator = true; };
            pixman            = toolchains.buildForWatchOS "pixman"            { simulator = true; };
            weston            = toolchains.buildForWatchOS "weston"            { simulator = true; };
            weston-simple-shm = toolchains.buildForWatchOS "weston-simple-shm" { simulator = true; };
            foot              = toolchains.buildForWatchOS "foot"              { simulator = true; };
            waypipe           = replatformForWatchOS { drv = toolchains.buildForIOS "waypipe"  { simulator = true; }; simulator = true; };
            libssh2           = replatformForWatchOS { drv = toolchains.buildForIOS "libssh2"  { simulator = true; }; simulator = true; };
            openssl           = replatformForWatchOS { drv = toolchains.buildForIOS "openssl"  { simulator = true; }; simulator = true; };
            mbedtls           = replatformForWatchOS { drv = toolchains.buildForIOS "mbedtls"  { simulator = true; }; simulator = true; };
            zstd              = replatformForWatchOS { drv = toolchains.buildForIOS "zstd"     { simulator = true; }; simulator = true; };
            lz4               = replatformForWatchOS { drv = toolchains.buildForIOS "lz4"      { simulator = true; }; simulator = true; };
            sshpass           = replatformForWatchOS { drv = toolchains.buildForIOS "sshpass"  { simulator = true; }; simulator = true; };
          };
          # Compatibility alias for existing callers
          watchosDeps = watchosDeviceDeps;
          # Rust backend for watchOS: aarch64-apple-watchos is a tier-3 Rust target
          # not yet in stable prebuilt binaries. We provide an empty derivation so
          # the rest of the build succeeds; libwawona.a is excluded from watchOS
          # linking (see xcodegen.nix). When the target becomes stable, replace
          # pkgs.emptyDirectory with the real rust-backend-c2n callPackage below.
          backend-watchos = pkgs.emptyDirectory;
          backend-watchos-sim = pkgs.emptyDirectory;
          xcodegenMacOutputs = pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc iosDeps iosSimDeps ipadosSimDeps macosDeps watchosDeps watchosSimDeps;
             ipadosDeps = ipadosDeviceDeps;
             macosBackend = backend-macos;
             iosBackend = null;
             iosSimBackend = null;
             watchosBackend = null;
             watchosSimBackend = null;
             macosWeston = toolchains.buildForMacOS "weston" { };
             macosFoot = toolchains.buildForMacOS "foot" { };
          };
          xcodegenOutputs = pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc iosDeps iosSimDeps ipadosSimDeps macosDeps watchosDeps watchosSimDeps;
             ipadosDeps = ipadosDeviceDeps;
             macosBackend = backend-macos;
             iosBackend = backend-ios;
             iosSimBackend = backend-ios-sim;
             watchosBackend = backend-watchos;
             watchosSimBackend = backend-watchos-sim;
             macosWeston = toolchains.buildForMacOS "weston" { };
             macosFoot = toolchains.buildForMacOS "foot" { };
          };
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            foot = toolchains.buildForMacOS "foot" { };
            rustBackend = backend-macos; xcodeProject = xcodegenMacOutputs.project;
          };
          wawona-ios-app-sim = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
          };
          wawona-ios-app-device = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
          };
          wawona-ipados-app-sim = pkgs.callPackage ./dependencies/wawona/ipados.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            xcodeTarget = "Wawona-iPadOS";
            nativeSdk = "iphoneos";
            platformName = "iOS";
            bundleId = "com.aspauldingcode.Wawona.ipad";
          };
          wawona-ipados-app-device = pkgs.callPackage ./dependencies/wawona/ipados.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            xcodeTarget = "Wawona-iPadOS";
            nativeSdk = "iphoneos";
            platformName = "iOS";
            bundleId = "com.aspauldingcode.Wawona.ipad";
          };
          wawona-watchos-app-sim = pkgs.callPackage ./dependencies/wawona/watchos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            xcodeTarget = "Wawona-watchOS";
            nativeSdk = "watchos";
            platformName = "watchOS";
            bundleId = "com.aspauldingcode.Wawona.watch";
          };
          wawona-watchos-app-device = pkgs.callPackage ./dependencies/wawona/watchos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            xcodeTarget = "Wawona-watchOS";
            nativeSdk = "watchos";
            platformName = "watchOS";
            bundleId = "com.aspauldingcode.Wawona.watch";
          };
          wawona-ios-ipa = if teamId != null then pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            generateIPA = true;
          } else missingTeamRelease "wawona-ios-ipa";
          wawona-ios-xcarchive = if teamId != null then pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            generateXCArchive = true;
          } else missingTeamRelease "wawona-ios-xcarchive";
          wawona-ios-simulator = apple.simulateApp {
            name = "wawona-ios-simulator";
            app = wawona-ios-app-sim;
            bundleId = "com.aspauldingcode.Wawona";
          };
        in {
          # Full Cargo tree (wawona + patched waypipe) for refreshing Cargo.lock locally:
          #   WS=$(nix path-info .#wawona-workspace-src-ios)
          #   TMP=$(mktemp -d) && cp -rL "$WS"/. "$TMP/" && chmod -R u+w "$TMP"
          #   (cd "$TMP" && cargo generate-lockfile) && cp "$TMP/Cargo.lock" ./Cargo.lock
          wawona-workspace-src-ios = workspace-src-ios;
          wawona-macos = wawona-macos;
          wawona-ios = wawona-ios-app-sim;
          wawona-ios-app-sim = wawona-ios-app-sim;
          wawona-ios-app-device = wawona-ios-app-device;
          wawona-ios-sim = wawona-ios-app-sim;
          wawona-ios-device = wawona-ios-app-device;
          wawona-ipados = wawona-ipados-app-sim;
          wawona-ipados-app-sim = wawona-ipados-app-sim;
          wawona-ipados-app-device = wawona-ipados-app-device;
          wawona-ipados-sim = wawona-ipados-app-sim;
          wawona-ipados-device = wawona-ipados-app-device;
          wawona-ipad = wawona-ipados-app-sim;
          wawona-ipad-sim = wawona-ipados-app-sim;
          wawona-watchos = wawona-watchos-app-sim;
          wawona-watchos-app-sim = wawona-watchos-app-sim;
          wawona-watchos-app-device = wawona-watchos-app-device;
          wawona-watchos-sim = wawona-watchos-app-sim;
          wawona-watchos-device = wawona-watchos-app-device;
          wawona-ios-ipa = wawona-ios-ipa;
          wawona-ios-xcarchive = wawona-ios-xcarchive;
          wawona-ios-simulator = wawona-ios-simulator;
          wawona-macos-backend = backend-macos;
          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-watchos-backend = backend-watchos;
          wawona-watchos-sim-backend = backend-watchos-sim;
          wawona-macos-project = xcodegenMacOutputs.app;
          wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = apple.provisionXcodeScript;
          wawona-ios-xcode-wrapper = apple.xcodeWrapperDrv;
          xcodegen = xcodegenOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = weston-terminal-pkg;
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          wawona-visionos = pkgs.callPackage ./dependencies/wawona/visionos.nix {
            inherit wawonaVersion;
          };
          wawona-wearos = pkgs.callPackage ./dependencies/wawona/wearos.nix {
            inherit wawonaVersion androidSDK;
            wearAndroidPackage = "wawona-wearos-android";
          };
          wawona-linux-vm = pkgs.callPackage ./dependencies/wawona/linux-vm.nix {
            inherit wawonaVersion;
          };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
        }));
      in packages;

    getAppsForSystem = system: pkgs: systemPackages:
      let
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import ./dependencies/apple { inherit (pkgs) lib pkgs; nixXcodeenvtests = inputs."nix-xcodeenvtests"; };
        };
      in {
        local-runner = { type = "app"; program = "${systemPackages.local-runner}/bin/local-runner"; };
        wawona-android-provision = { type = "app"; program = "${systemPackages.wawona-android-provision}/bin/provision-android"; };
        wawona-android-project = { type = "app"; program = "${systemPackages.gradlegen}/bin/gradlegen"; };
        wawona-android = { type = "app"; program = "${systemPackages.wawona-android}/bin/wawona-android-run"; };
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
        wawona-linux = { type = "app"; program = "${systemPackages.wawona-linux}/bin/wawona-linux-run"; };
        wawona-linux-vm = { type = "app"; program = "${systemPackages.wawona-linux-vm}/bin/wawona-linux-vm-run"; };
        wawona-wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
        wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
      }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-macos = { type = "app"; program = "${systemPackages.wawona-macos}/bin/wawona"; };
        wawona-macos-project = { type = "app"; program = "${systemPackages.wawona-macos-project}/bin/xcodegen"; };
        wawona-ios = { type = "app"; program = appPrograms.wawonaIos; };
        wawona-ipados = { type = "app"; program = appPrograms.wawonaIpad; };
        wawona-ipad = { type = "app"; program = appPrograms.wawonaIpad; };
        wawona-watchos = { type = "app"; program = appPrograms.wawonaWatchos; };
        wawona-linux-vm = { type = "app"; program = "${systemPackages.wawona-linux-vm}/bin/wawona-linux-vm-run"; };
        wawona-wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
        wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
        wawona-visionos = { type = "app"; program = "${systemPackages.wawona-visionos}/bin/wawona-visionos-run"; };
        wawona-ios-project = { type = "app"; program = "${systemPackages.wawona-ios-project}/bin/xcodegen"; };
        wawona-ios-provision = { type = "app"; program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode"; };
      });

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system (pkgsFor system));
  in {
    packages = allSystemPackages;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system (pkgsFor system) allSystemPackages.${system});
    devShells = import ./dependencies/wawona/devshells.nix {
      systems = systemsList;
      pkgsFor = pkgsFor;
    };
    checks = nixpkgs.lib.genAttrs systemsList (system: let pkgs = pkgsFor system; in
      {
        matrix-platform-stubs = pkgs.runCommand "matrix-platform-stubs" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
          test -n '${allSystemPackages.${system}.wawona-android}'
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux "test -n '${allSystemPackages.${system}.wawona-linux}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux "test -n '${allSystemPackages.${system}.wawona-linux-vm}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isLinux "test -n '${allSystemPackages.${system}.wawona-wearos}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-macos}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-ios}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-ipados}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-watchos}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-linux-vm}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-wearos}'"}
          ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "test -n '${allSystemPackages.${system}.wawona-visionos}'"}
          touch $out
        '';
        wearos-linux-vm-smoke = pkgs.runCommand "wearos-linux-vm-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/dependencies/wawona/wearos.nix"
          test -f "$src/dependencies/wawona/linux-vm.nix"
          grep -q "wawona-wearos-run" "$src/dependencies/wawona/wearos.nix"
          grep -q "nixos-generators" "$src/dependencies/wawona/linux-vm.nix"
          grep -q "services.desktopManager.plasma6.enable = true;" "$src/dependencies/wawona/linux-vm.nix"
          touch "$out"
        '';
        ui-contracts-smoke = pkgs.runCommand "ui-contracts-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/Sources/WawonaUIContracts/MachineEditorContracts.swift"
          test -f "$src/Sources/WawonaUIContracts/SettingsContracts.swift"
          test -f "$src/Tests/WawonaUIContractsTests/MachineEditorContractsTests.swift"
          test -f "$src/Tests/WawonaUIContractsTests/SettingsContractsTests.swift"
          grep -q "enum MachineEditorFieldID" "$src/Sources/WawonaUIContracts/MachineEditorContracts.swift"
          grep -q "func visibleFields" "$src/Sources/WawonaUIContracts/MachineEditorContracts.swift"
          touch "$out"
        '';
        native-ui-entrypoints-smoke = pkgs.runCommand "native-ui-entrypoints-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/src/bin/wawona-linux-ui.rs"
          test -f "$src/Sources/WawonaUI/Wear/WawonaWearCompactRootView.swift"
          test -f "$src/Sources/WawonaUI/VisionOS/WawonaVisionShell.swift"
          grep -q "NavigationSplitView" "$src/src/bin/wawona-linux-ui.rs"
          grep -q "WawonaWearCompactRootView" "$src/android/app/src/main/java/com/aspauldingcode/wawona/Main.kt"
          touch "$out"
        '';
        android-skip-repro-smoke = pkgs.runCommand "android-skip-repro-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          grep -q "SKIP_ARTIFACTS_DIR" "$src/android/app/build.gradle.kts"
          grep -q "SKIP_EXPORT_STRATEGY" "$src/android/app/build.gradle.kts"
          grep -q "nix-prebuilt" "$src/android/app/build.gradle.kts"
          grep -q "skip export --project" "$src/dependencies/wawona/android.nix"
          touch "$out"
        '';
        android-wear-target-routing-smoke = pkgs.runCommand "android-wear-target-routing-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/Sources/WawonaUI/Wear/WawonaWearCompactRootView.swift"
          grep -q "WawonaRootView" "$src/android/app/src/main/java/com/aspauldingcode/wawona/Main.kt"
          grep -q "WawonaWearCompactRootView" "$src/Sources/WawonaWatch/WawonaWatchApp.swift"
          touch "$out"
        '';
        android-skip-artifacts-layout-smoke = pkgs.runCommand "android-skip-artifacts-layout-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          grep -q "WARN: skip export failed in Nix build; using checked-in android/Skip artifacts" "$src/dependencies/wawona/android.nix"
          grep -q "WARN: swift tool not found in Nix build; using checked-in android/Skip artifacts" "$src/dependencies/wawona/android.nix"
          grep -q "SKIP_ARTIFACTS_DIR" "$src/dependencies/wawona/android.nix"
          grep -q "android/Skip" "$src/dependencies/wawona/android.nix"
          touch "$out"
        '';
        ui-parity-gates-smoke = pkgs.runCommand "ui-parity-gates-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/scripts/ui_parity_diff.py"
          test -f "$src/docs/2026-UI-PARITY-CHECKLIST.md"
          grep -q "phone-home-light" "$src/scripts/ui_parity_diff.py"
          grep -q "wear-home-dark" "$src/scripts/ui_parity_diff.py"
          grep -q "python3 scripts/ui_parity_diff.py" "$src/docs/2026-UI-PARITY-CHECKLIST.md"
          grep -q "wawona-wearos-android" "$src/docs/2026-UI-PARITY-CHECKLIST.md"
          touch "$out"
        '';
        settings-architecture-smoke = pkgs.runCommand "settings-architecture-smoke" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
        } ''
          test -f "$src/Sources/WawonaUI/Settings/SettingsRootView.swift"
          test -f "$src/Sources/WawonaUI/Settings/MachineSettingsView.swift"
          test -f "$src/Sources/WawonaUI/Settings/GlobalConnectionTestsView.swift"
          test -f "$src/Sources/WawonaUI/Settings/SettingsDiagnosticsView.swift"
          test -f "$src/Tests/WawonaModelSettingsTests/WawonaModelSettingsTests.swift"
          grep -q "func resolvedSettings" "$src/Sources/WawonaModel/WawonaPreferences.swift"
          grep -q "MachineRuntimeOverrides" "$src/Sources/WawonaModel/MachineProfile.swift"
          touch "$out"
        '';
        version-schema-drift-check = pkgs.runCommand "version-schema-drift-check" {
          src = ./.;
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
        } ''
          VERSION_VALUE="$(tr -d '\n' < "$src/VERSION")"
          CARGO_VERSION="$(awk -F'"' '/^version = "/ { print $2; exit }' "$src/Cargo.toml")"
          LOCK_VERSION="$(awk '
            $0 ~ /\[\[package\]\]/ { in_pkg=0 }
            $0 ~ /name = "wawona"/ { in_pkg=1 }
            in_pkg && $0 ~ /version = "/ {
              split($0, a, "\""); print a[2]; exit
            }' "$src/Cargo.lock")"

          test "$VERSION_VALUE" = "$CARGO_VERSION"
          test "$VERSION_VALUE" = "$LOCK_VERSION"

          grep -q "wawona.machineProfiles.v1" "$src/Sources/WawonaModel/MachineProfile.swift"
          grep -q "wawona.pref." "$src/Sources/WawonaModel/WawonaPreferences.swift"
          grep -q "machine overrides > global defaults > hardcoded defaults" "$src/docs/settings.md"
          touch "$out"
        '';
      } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      dependencies-platform-triad = pkgs.runCommand "dependencies-platform-triad" {
        src = ./.;
        nativeBuildInputs = [ pkgs.findutils pkgs.gnugrep ];
      } ''
        cd "$src/dependencies"
        missing=0
        while IFS= read -r iosFile; do
          dir=$(dirname "$iosFile")
          if [ ! -f "$dir/ipados.nix" ]; then
            echo "Missing iPadOS module: $dir/ipados.nix" >&2
            missing=1
          fi
          if [ ! -f "$dir/watchos.nix" ]; then
            echo "Missing watchOS module: $dir/watchos.nix" >&2
            missing=1
          fi
        done < <(find . -type f -name ios.nix | sort)
        while IFS= read -r androidFile; do
          dir=$(dirname "$androidFile")
          if [ ! -f "$dir/wearos.nix" ]; then
            echo "Missing WearOS module: $dir/wearos.nix" >&2
            missing=1
          fi
        done < <(find ./clients ./libs -type f -name android.nix | sort)
        while IFS= read -r iosFile; do
          dir=$(dirname "$iosFile")
          if [ ! -f "$dir/visionos.nix" ]; then
            echo "Missing visionOS module: $dir/visionos.nix" >&2
            missing=1
          fi
        done < <(find ./clients ./libs -type f -name ios.nix | sort)
        while IFS= read -r macosFile; do
          dir=$(dirname "$macosFile")
          if [ ! -f "$dir/linux.nix" ]; then
            echo "Missing Linux module: $dir/linux.nix" >&2
            missing=1
          fi
        done < <(find ./clients ./libs -type f -name macos.nix | sort)
        [ "$missing" -eq 0 ]
        touch "$out"
      '';
      weston-terminal-no-compat-shim = pkgs.runCommand "weston-terminal-no-compat-shim" {
        src = ./.;
        nativeBuildInputs = [ pkgs.gnugrep ];
      } ''
        cd "$src/dependencies/clients/weston"
        bad=0
        for f in ios.nix ipados.nix watchos.nix visionos.nix android.nix wearos.nix linux.nix; do
          if grep -q "wwn_weston_terminal_is_compat_shim(void) { return 1; }" "$f"; then
            echo "Compat shim marker still present in $f" >&2
            bad=1
          fi
        done
        [ "$bad" -eq 0 ]
        touch "$out"
      '';
    });
  };
}
