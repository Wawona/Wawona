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
  };

  outputs = { self, nixpkgs, android-nixpkgs, rust-overlay, crate2nix }:
  let
    linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
    darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
    systemsList = linuxSystems ++ darwinSystems;

    pkgsFor = system:
      let
        isDarwin = (system == "x86_64-darwin" || system == "aarch64-darwin");
        customOverlays = if isDarwin then [
          (import rust-overlay)
          (self: super: {
            rustToolchain = super.rust-bin.stable.latest.default.override {
              targets = [ "aarch64-apple-ios" "aarch64-apple-ios-sim" ];
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
        ] else [];
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
              "/src" "/android" "/deps" "/protocols" "/scripts" "/include" "/VERSION" "/Cargo" "/build.rs" "/flake"
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

        vulkan-cts-android = import ./dependencies/libs/vulkan-cts/android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
          androidToolchain = toolchainsAndroid.androidToolchain;
        };
        gl-cts-android = import ./dependencies/libs/vulkan-cts/gl-cts-android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
          androidToolchain = toolchainsAndroid.androidToolchain;
        };

        waypipe-patched-android = import ./dependencies/libs/waypipe/waypipe-patched-src.nix {
          pkgs = androidPkgs;
          inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-android.sh; platform = "android";
        };

        workspace-src-android = androidPkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; platform = "android"; inherit wawonaVersion;
        };

        backend-android = androidPkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
          inherit crate2nix wawonaVersion nixpkgs androidSDK;
          toolchains = if isLinuxHost then toolchainsAndroid else toolchains;
          androidToolchain = if isLinuxHost then toolchainsAndroid.androidToolchain else toolchains.androidToolchain;
          workspaceSrc = workspace-src-android; platform = "android";
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
          nom = pkgs.nix-output-monitor;
          local-runner = pkgs.callPackage ./scripts/local-runner.nix { };
          wawona-shell = pkgs.callPackage ./dependencies/clients/wawona-shell { };
          wawona-tools = pkgs.callPackage ./dependencies/clients/wawona-tools { };
          
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
          wawona-android-backend = backend-android;
          android-toolchain-sanity = androidToolchainSanity;
          gradlegen = gradlegenPkg.generateScript;
          wawona-android-project = gradlegenPkg.generateScript;
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
          wawona-android-provision = androidUtils.provisionAndroidScript;
        }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          teamId = let value = builtins.getEnv "TEAM_ID"; in if value == "" then null else value;
          iosXcode = import ./dependencies/toolchains/ios-xcodeenv.nix { inherit (pkgs) lib pkgs; TEAM_ID = teamId; };
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
          iosDeps = {
            xkbcommon = toolchains.buildForIOS "xkbcommon" {}; libffi = toolchains.buildForIOS "libffi" {};
            libwayland = toolchains.buildForIOS "libwayland" {}; zstd = toolchains.buildForIOS "zstd" {};
            lz4 = toolchains.buildForIOS "lz4" {}; zlib = toolchains.buildForIOS "zlib" {};
            libssh2 = toolchains.buildForIOS "libssh2" {}; mbedtls = toolchains.buildForIOS "mbedtls" {};
            openssl = toolchains.buildForIOS "openssl" {}; ffmpeg = toolchains.buildForIOS "ffmpeg" {};
            epoll-shim = toolchains.buildForIOS "epoll-shim" {}; waypipe = toolchains.buildForIOS "waypipe" {};
            weston = toolchains.buildForIOS "weston" {}; weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" {}; pixman = toolchains.buildForIOS "pixman" {};
            sshpass = toolchains.buildForIOS "sshpass" {};
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
          };
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
          xcodegenOutputs = pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc iosDeps iosSimDeps macosDeps;
             macosBackend = backend-macos;
             iosBackend = backend-ios;
             iosSimBackend = backend-ios-sim;
             macosWeston = toolchains.buildForMacOS "weston" { };
          };
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            rustBackend = backend-macos; xcodeProject = xcodegenOutputs.project;
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
          wawona-ios-simulator = iosXcode.simulateApp {
            name = "wawona-ios-simulator";
            app = wawona-ios-app-sim;
            bundleId = "com.aspauldingcode.Wawona";
          };
        in {
          wawona-macos = wawona-macos;
          wawona-ios = wawona-ios-app-sim;
          wawona-ios-app-sim = wawona-ios-app-sim;
          wawona-ios-app-device = wawona-ios-app-device;
          wawona-ios-ipa = wawona-ios-ipa;
          wawona-ios-xcarchive = wawona-ios-xcarchive;
          wawona-ios-simulator = wawona-ios-simulator;
          wawona-macos-backend = backend-macos;
          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-macos-project = xcodegenOutputs.app;
          wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = iosXcode.provisionXcodeScript;
          wawona-ios-xcode-wrapper = iosXcode.xcodeWrapper;
          xcodegen = xcodegenOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          graphics-validate-macos = pkgs.callPackage ./dependencies/tests/graphics-validate.nix { };
          vulkan-cts = toolchains.buildForMacOS "vulkan-cts" { };
          vulkan-cts-ios = toolchains.buildForIOS "vulkan-cts" { };
          gl-cts = toolchains.buildForMacOS "gl-cts" { };
          gl-cts-ios = toolchains.buildForIOS "gl-cts" { };
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = weston-terminal-pkg;
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
        }));
      in packages;

    getAppsForSystem = system: pkgs: systemPackages:
      let
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; };
        };
      in {
        nom = { type = "app"; program = "${pkgs.nix-output-monitor}/bin/nom"; };
        local-runner = { type = "app"; program = "${systemPackages.local-runner}/bin/local-runner"; };
        wawona-android-provision = { type = "app"; program = "${systemPackages.wawona-android-provision}/bin/provision-android"; };
        wawona-android-project = { type = "app"; program = "${systemPackages.gradlegen}/bin/gradlegen"; };
        wawona-android = { type = "app"; program = "${systemPackages.wawona-android}/bin/wawona-android-run"; };
        vulkan-cts-android = { type = "app"; program = "${systemPackages.vulkan-cts-android}/bin/vulkan-cts-android-run"; };
        gl-cts-android = { type = "app"; program = "${systemPackages.gl-cts-android}/bin/gl-cts-android-run"; };
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-macos = { type = "app"; program = "${systemPackages.wawona-macos}/bin/wawona"; };
        wawona-macos-project = { type = "app"; program = "${systemPackages.wawona-macos-project}/bin/xcodegen"; };
        wawona-ios = { type = "app"; program = appPrograms.wawonaIos; };
        wawona-ios-project = { type = "app"; program = "${systemPackages.wawona-ios-project}/bin/xcodegen"; };
        wawona-ios-provision = { type = "app"; program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode"; };
        graphics-validate-macos = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-macos"; };
      });

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system (pkgsFor system));
  in {
    packages = allSystemPackages;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system (pkgsFor system) allSystemPackages.${system});
    devShells = nixpkgs.lib.genAttrs systemsList (system: {
      default = let pkgs = pkgsFor system; in if pkgs.stdenv.isDarwin then (pkgs.mkShell {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.nix-output-monitor pkgs.rustToolchain pkgs.libxkbcommon pkgs.libffi pkgs.wayland-protocols pkgs.openssl ]
          ++ [ (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).ensureIosSimSDK (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).findXcodeScript ];
        shellHook = "export XDG_RUNTIME_DIR=\"/tmp/wawona-$(id -u)\"; export WAYLAND_DISPLAY=\"wayland-0\"; alias nb='nom build'; alias nd='nom develop';";
      }) else (pkgs.mkShell {
        buildInputs = [ pkgs.hello pkgs.nix-output-monitor ];
        shellHook = "alias nb='nom build'; alias nd='nom develop';";
      });
    });
    checks = nixpkgs.lib.genAttrs systemsList (system: let pkgs = pkgsFor system; in pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      graphics-validate-smoke = pkgs.runCommand "graphics-validate-smoke" { nativeBuildInputs = [ pkgs.coreutils ]; } "echo 'smoke check'; test -n '${allSystemPackages.${system}.wawona-android}'; touch $out";
    });
  };
}
