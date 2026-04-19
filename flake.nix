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

    pkgsFor = system:
      let
        isDarwin = (system == "x86_64-darwin" || system == "aarch64-darwin");
        customOverlays = if isDarwin then [
          (import rust-overlay)
          (self: super: {
            rustToolchain = super.rust-bin.nightly.latest.default.override {
              extensions = [ "rust-src" ];
              targets = [
                "aarch64-apple-ios"
                "aarch64-apple-ios-sim"
                "aarch64-apple-tvos"
                "aarch64-apple-tvos-sim"
                "aarch64-apple-visionos"
                "aarch64-apple-visionos-sim"
                "aarch64-apple-watchos"
                "aarch64-apple-watchos-sim"
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
              abiVersions = [ androidConfig.hostEmulatorAbi ];
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
            systemImage = "${sdkRoot}/system-images/android-${toString androidConfig.compileSdk}/google_apis_playstore/${androidConfig.hostEmulatorAbi}";
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
        gradle = pkgs.gradle_9.override { java = jdk17; };
        
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

        hasGraphicsValidate = builtins.pathExists ./dependencies/tests/graphics-validate.nix;
        hasAndroidCts = builtins.pathExists ./dependencies/libs/vulkan-cts/android.nix
          && builtins.pathExists ./dependencies/libs/vulkan-cts/gl-cts-android.nix;
        vulkan-cts-android = if hasAndroidCts then import ./dependencies/libs/vulkan-cts/android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
          androidToolchain = toolchainsAndroid.androidToolchain;
        } else null;
        gl-cts-android = if hasAndroidCts then import ./dependencies/libs/vulkan-cts/gl-cts-android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
          androidToolchain = toolchainsAndroid.androidToolchain;
        } else null;

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

        westonSimpleShmPatched = androidPkgs.callPackage ./dependencies/libs/weston-simple-shm/patched-src.nix { };
        studioAndroidDeps = [
          (toolchainsAndroid.buildForAndroid "swiftshader" { })
          (toolchainsAndroid.buildForAndroid "pixman" { })
          (toolchainsAndroid.buildForAndroid "libwayland" { })
          (toolchainsAndroid.buildForAndroid "expat" { })
          (toolchainsAndroid.buildForAndroid "libffi" { })
          (toolchainsAndroid.buildForAndroid "libxml2" { })
          (toolchainsAndroid.buildForAndroid "xkbcommon" { })
          (toolchainsAndroid.buildForAndroid "openssl" { })
          (toolchainsAndroid.buildForAndroid "zstd" { })
          (toolchainsAndroid.buildForAndroid "lz4" { })
        ];
        studioNixDepIncludes =
          (pkgs.lib.concatMapStringsSep " " (d: "-I${d}/include") studioAndroidDeps)
          + " -I${toolchainsAndroid.buildForAndroid "pixman" { }}/include/pixman-1";
        studioNixDepLibs =
          pkgs.lib.concatMapStringsSep " " (d: "-L${d}/lib") studioAndroidDeps;
        studioRuntimeLibDirs =
          pkgs.lib.concatMapStringsSep ":" (d: "${d}/lib") studioAndroidDeps;
        studioRustBackendLib = "${backend-android}/lib/libwawona.a";
        studioRustBackendSharedLib = "${backend-android}/lib/libwawona_core.so";

        gradlegenPkg = pkgs.callPackage ./dependencies/generators/gradlegen.nix ({
          wawonaSrc = if isLinuxHost then ./. else src;
          inherit wawonaVersion;
          androidSdkRoot = androidSDK.sdkRoot;
          westonSimpleShmSrc = westonSimpleShmPatched;
          iconAssets = "AUTO";
          nixDepIncludes = studioNixDepIncludes;
          nixDepLibs = studioNixDepLibs;
          rustBackendLib = studioRustBackendLib;
          rustBackendSharedLib = studioRustBackendSharedLib;
          runtimeLibDirs = studioRuntimeLibDirs;
        } // (pkgs.lib.optionalAttrs (!isLinuxHost) {
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
          weston-simple-shm =
            if pkgs.stdenv.isDarwin
            then toolchains.buildForMacOS "weston-simple-shm" {}
            else pkgs.callPackage ./dependencies/libs/weston-simple-shm/linux.nix {};
          foot = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "foot" {} else pkgs.foot;
          waypipe = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "waypipe" { } else pkgs.waypipe;
          
          # Wawona (Native on Linux, Cross-wrapped on Darwin)
          wawona = if pkgs.stdenv.isDarwin 
            then (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs 
              (pkgs.callPackage ./dependencies/wawona/macos.nix {
                buildModule = toolchains; inherit wawonaSrc wawonaVersion;
                waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
                foot = toolchains.buildForMacOS "foot" { };
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
            else pkgs.callPackage ./dependencies/wawona/linux.nix {
              inherit wawonaVersion;
              waypipeSrc = waypipe-src;
            };
        };

        packages = commonPackages // (pkgs.lib.optionalAttrs (isLinuxHost || androidSDK != null) {
          wawona-android = wawonaAndroidPkg;
          wawona-wearos-android = wawonaWearAndroidPkg;
          wawona-android-backend = backend-android;
          android-toolchain-sanity = androidToolchainSanity;
          gradle-deps-update =
            let
              updateScript = (pkgs.callPackage ./dependencies/gradle-deps.nix {
                wawonaSrc = if isLinuxHost then ./. else src;
                inherit androidSDK;
                inherit gradle;
              }).mitmCache.passthru.updateScript;
            in pkgs.writeShellScriptBin "gradle-deps-update" ''
              exec ${updateScript} "$@"
            '';
          gradlegen = gradlegenPkg.generateScript;
          wawona-android-project = gradlegenPkg.generateScript;
          wawona-android-provision = androidUtils.provisionAndroidScript;
          wawona-wearos = pkgs.callPackage ./dependencies/wawona/wearos.nix {
            inherit wawonaVersion androidSDK;
            wearAndroidPackage = "wawona-wearos-android";
          };
        }) // (pkgs.lib.optionalAttrs hasAndroidCts {
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
        }) // (pkgs.lib.optionalAttrs isLinuxHost {
          wawona-linux = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
          };
          wawona-linux-compositor-host = pkgs.callPackage ./dependencies/wawona/linux-host.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
          };
          wawona-linux-tray = pkgs.callPackage ./dependencies/wawona/linux-tray.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
          };
          wawona-linux-vm = pkgs.callPackage ./dependencies/wawona/linux-vm.nix {
            inherit wawonaVersion;
          };
          default = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
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
          iosDeps = {
            xkbcommon = toolchains.buildForIOS "xkbcommon" {}; libffi = toolchains.buildForIOS "libffi" {};
            libwayland = toolchains.buildForIOS "libwayland" {}; zstd = toolchains.buildForIOS "zstd" {};
            lz4 = toolchains.buildForIOS "lz4" {}; zlib = toolchains.buildForIOS "zlib" {};
            libssh2 = toolchains.buildForIOS "libssh2" {}; mbedtls = toolchains.buildForIOS "mbedtls" {};
            openssl = toolchains.buildForIOS "openssl" {}; ffmpeg = toolchains.buildForIOS "ffmpeg" {};
            epoll-shim = toolchains.buildForIOS "epoll-shim" {}; waypipe = toolchains.buildForIOS "waypipe" {};
            weston = toolchains.buildForIOS "weston" {}; weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" {}; pixman = toolchains.buildForIOS "pixman" {};
            foot = toolchains.buildForIOS "foot" {};
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
            foot = toolchains.buildForIOS "foot" { simulator = true; };
            sshpass = toolchains.buildForIOS "sshpass" { simulator = true; };
          };
          tvosDeps = {
            xkbcommon = toolchains.buildForTVOS "xkbcommon" {};
            libffi = toolchains.buildForTVOS "libffi" {};
            libwayland = toolchains.buildForTVOS "libwayland" {};
            zstd = toolchains.buildForTVOS "zstd" {};
            lz4 = toolchains.buildForTVOS "lz4" {};
            zlib = toolchains.buildForTVOS "zlib" {};
            libssh2 = toolchains.buildForTVOS "libssh2" {};
            mbedtls = toolchains.buildForTVOS "mbedtls" {};
            openssl = toolchains.buildForTVOS "openssl" {};
            ffmpeg = toolchains.buildForTVOS "ffmpeg" {};
            epoll-shim = toolchains.buildForTVOS "epoll-shim" {};
            waypipe = toolchains.buildForTVOS "waypipe" {};
            weston = toolchains.buildForTVOS "weston" {};
            weston-simple-shm = toolchains.buildForTVOS "weston-simple-shm" {};
            pixman = toolchains.buildForTVOS "pixman" {};
            foot = toolchains.buildForTVOS "foot" {};
            sshpass = toolchains.buildForTVOS "sshpass" {};
          };
          tvosSimDeps = {
            xkbcommon = toolchains.buildForTVOS "xkbcommon" { simulator = true; };
            libffi = toolchains.buildForTVOS "libffi" { simulator = true; };
            libwayland = toolchains.buildForTVOS "libwayland" { simulator = true; };
            zstd = toolchains.buildForTVOS "zstd" { simulator = true; };
            lz4 = toolchains.buildForTVOS "lz4" { simulator = true; };
            zlib = toolchains.buildForTVOS "zlib" { simulator = true; };
            libssh2 = toolchains.buildForTVOS "libssh2" { simulator = true; };
            mbedtls = toolchains.buildForTVOS "mbedtls" { simulator = true; };
            openssl = toolchains.buildForTVOS "openssl" { simulator = true; };
            ffmpeg = toolchains.buildForTVOS "ffmpeg" { simulator = true; };
            epoll-shim = toolchains.buildForTVOS "epoll-shim" { simulator = true; };
            waypipe = toolchains.buildForTVOS "waypipe" { simulator = true; };
            weston = toolchains.buildForTVOS "weston" { simulator = true; };
            weston-simple-shm = toolchains.buildForTVOS "weston-simple-shm" { simulator = true; };
            pixman = toolchains.buildForTVOS "pixman" { simulator = true; };
            foot = toolchains.buildForTVOS "foot" { simulator = true; };
            sshpass = toolchains.buildForTVOS "sshpass" { simulator = true; };
          };
          visionosDeps = {
            xkbcommon = toolchains.buildForVisionOS "xkbcommon" {};
            libffi = toolchains.buildForVisionOS "libffi" {};
            libwayland = toolchains.buildForVisionOS "libwayland" {};
            libssh2 = toolchains.buildForVisionOS "libssh2" {};
            openssl = toolchains.buildForVisionOS "openssl" {};
            epoll-shim = toolchains.buildForVisionOS "epoll-shim" {};
            pixman = toolchains.buildForVisionOS "pixman" {};
            weston-simple-shm = toolchains.buildForVisionOS "weston-simple-shm" {};
          };
          visionosSimDeps = {
            xkbcommon = toolchains.buildForVisionOS "xkbcommon" { simulator = true; };
            libffi = toolchains.buildForVisionOS "libffi" { simulator = true; };
            libwayland = toolchains.buildForVisionOS "libwayland" { simulator = true; };
            libssh2 = toolchains.buildForVisionOS "libssh2" { simulator = true; };
            openssl = toolchains.buildForVisionOS "openssl" { simulator = true; };
            epoll-shim = toolchains.buildForVisionOS "epoll-shim" { simulator = true; };
            pixman = toolchains.buildForVisionOS "pixman" { simulator = true; };
            weston-simple-shm = toolchains.buildForVisionOS "weston-simple-shm" { simulator = true; };
          };
          watchosDeps = {
            xkbcommon = toolchains.buildForWatchOS "xkbcommon" {};
            libffi = toolchains.buildForWatchOS "libffi" {};
            libwayland = toolchains.buildForWatchOS "libwayland" {};
            zstd = toolchains.buildForWatchOS "zstd" {};
            lz4 = toolchains.buildForWatchOS "lz4" {};
            zlib = toolchains.buildForWatchOS "zlib" {};
            libssh2 = toolchains.buildForWatchOS "libssh2" {};
            mbedtls = toolchains.buildForWatchOS "mbedtls" {};
            openssl = toolchains.buildForWatchOS "openssl" {};
            ffmpeg = toolchains.buildForWatchOS "ffmpeg" {};
            epoll-shim = toolchains.buildForWatchOS "epoll-shim" {};
            weston = toolchains.buildForWatchOS "weston" {};
            weston-simple-shm = toolchains.buildForWatchOS "weston-simple-shm" {};
            pixman = toolchains.buildForWatchOS "pixman" {};
            foot = toolchains.buildForWatchOS "foot" {};
            sshpass = toolchains.buildForWatchOS "sshpass" {};
          };
          watchosSimDeps = {
            xkbcommon = toolchains.buildForWatchOS "xkbcommon" { simulator = true; };
            libffi = toolchains.buildForWatchOS "libffi" { simulator = true; };
            libwayland = toolchains.buildForWatchOS "libwayland" { simulator = true; };
            zstd = toolchains.buildForWatchOS "zstd" { simulator = true; };
            lz4 = toolchains.buildForWatchOS "lz4" { simulator = true; };
            zlib = toolchains.buildForWatchOS "zlib" { simulator = true; };
            libssh2 = toolchains.buildForWatchOS "libssh2" { simulator = true; };
            mbedtls = toolchains.buildForWatchOS "mbedtls" { simulator = true; };
            openssl = toolchains.buildForWatchOS "openssl" { simulator = true; };
            ffmpeg = toolchains.buildForWatchOS "ffmpeg" { simulator = true; };
            epoll-shim = toolchains.buildForWatchOS "epoll-shim" { simulator = true; };
            weston = toolchains.buildForWatchOS "weston" { simulator = true; };
            weston-simple-shm = toolchains.buildForWatchOS "weston-simple-shm" { simulator = true; };
            pixman = toolchains.buildForWatchOS "pixman" { simulator = true; };
            foot = toolchains.buildForWatchOS "foot" { simulator = true; };
            sshpass = toolchains.buildForWatchOS "sshpass" { simulator = true; };
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
          backend-tvos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "tvos"; nativeDeps = tvosDeps;
          };
          backend-tvos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "tvos"; simulator = true; nativeDeps = tvosSimDeps;
          };
          backend-visionos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "visionos"; nativeDeps = visionosDeps;
          };
          backend-visionos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios; platform = "visionos"; simulator = true; nativeDeps = visionosSimDeps;
          };
          xcodegenOutputs = pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc iosDeps iosSimDeps tvosDeps tvosSimDeps visionosDeps visionosSimDeps watchosDeps watchosSimDeps macosDeps;
             macosBackend = backend-macos;
             iosBackend = backend-ios;
             iosSimBackend = backend-ios-sim;
             tvosBackend = backend-tvos;
             tvosSimBackend = backend-tvos-sim;
             visionosBackend = backend-visionos;
             visionosSimBackend = backend-visionos-sim;
             macosWeston = toolchains.buildForMacOS "weston" { };
          };
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            foot = toolchains.buildForMacOS "foot" { };
            rustBackend = backend-macos; xcodeProject = xcodegenOutputs.project;
          };
          wawona-ios-app-sim = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
          };
          wawona-watchos-app-sim = pkgs.callPackage ./dependencies/wawona/watchos.nix {
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
          wawona-tvos-app-sim = pkgs.callPackage ./dependencies/wawona/tvos.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
          };
          wawona-tvos-app-device = pkgs.callPackage ./dependencies/wawona/tvos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
          };
          wawona-visionos-app-sim = pkgs.callPackage ./dependencies/wawona/visionos.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
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
          install = pkgs.writeShellScriptBin "install" ''
            set -eu
            uid="$(id -u)"
            domain="gui/$uid"
            launch_agents_dir="$HOME/Library/LaunchAgents"
            compositor_label="com.aspauldingcode.wawona.compositorhost"
            menubar_label="com.aspauldingcode.wawona.menubar"
            runtime_dir="/tmp/wawona-$uid"
            exec_path="${wawona-macos}/Applications/Wawona.app/Contents/MacOS/Wawona"

            mkdir -p "$launch_agents_dir"
            mkdir -p "$runtime_dir"
            chmod 700 "$runtime_dir" || true

            write_agent() {
              label="$1"
              mode="$2"
              log_prefix="$3"
              plist_path="$launch_agents_dir/$label.plist"
              cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$exec_path</string>
    <string>$mode</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>/tmp/$log_prefix-$uid.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/$log_prefix-$uid.error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>XDG_RUNTIME_DIR</key>
    <string>$runtime_dir</string>
    <key>WAYLAND_DISPLAY</key>
    <string>wayland-0</string>
    <key>WAWONA_SKIP_LAUNCH_AGENT_BOOTSTRAP</key>
    <string>1</string>
  </dict>
</dict>
</plist>
EOF
            }

            ensure_loaded() {
              label="$1"
              plist_path="$launch_agents_dir/$label.plist"
              target="$domain/$label"
              if launchctl print "$target" >/dev/null 2>&1; then
                launchctl kickstart -k "$target" >/dev/null 2>&1 || true
              else
                launchctl bootstrap "$domain" "$plist_path"
                launchctl kickstart -k "$target" >/dev/null 2>&1 || true
              fi
            }

            if [ ! -x "$exec_path" ]; then
              echo "Error: Wawona executable not found at $exec_path" >&2
              exit 1
            fi

            write_agent "$compositor_label" "--compositor-host" "wawona-compositor"
            write_agent "$menubar_label" "--menubar" "wawona-menubar"
            ensure_loaded "$compositor_label"
            ensure_loaded "$menubar_label"
            echo "Wawona launch agents installed and running:"
            echo "  - $compositor_label"
            echo "  - $menubar_label"
          '';
          uninstall = pkgs.writeShellScriptBin "uninstall" ''
            set -eu
            uid="$(id -u)"
            domain="gui/$uid"
            launch_agents_dir="$HOME/Library/LaunchAgents"
            compositor_label="com.aspauldingcode.wawona.compositorhost"
            menubar_label="com.aspauldingcode.wawona.menubar"
            app_path="/Applications/Wawona.app"

            unload_agent() {
              label="$1"
              target="$domain/$label"
              plist_path="$launch_agents_dir/$label.plist"
              launchctl bootout "$target" >/dev/null 2>&1 || true
              launchctl remove "$label" >/dev/null 2>&1 || true
              rm -f "$plist_path"
            }

            unload_agent "$compositor_label"
            unload_agent "$menubar_label"

            if [ -d "$app_path" ]; then
              rm -rf "$app_path"
            fi

            echo "Wawona launch agents removed:"
            echo "  - $compositor_label"
            echo "  - $menubar_label"
            echo "Wawona app bundle removed from /Applications if present."
          '';
          wawona-macos = wawona-macos;
          wawona-ios = wawona-ios-app-sim;
          wawona-tvos = wawona-tvos-app-sim;
          wawona-watchos = wawona-watchos-app-sim;
          wawona-visionos = wawona-visionos-app-sim;
          wawona-ios-app-sim = wawona-ios-app-sim;
          wawona-tvos-app-sim = wawona-tvos-app-sim;
          wawona-watchos-app-sim = wawona-watchos-app-sim;
          wawona-visionos-app-sim = wawona-visionos-app-sim;
          wawona-ios-app-device = wawona-ios-app-device;
          wawona-tvos-app-device = wawona-tvos-app-device;
          wawona-ios-ipa = wawona-ios-ipa;
          wawona-ios-xcarchive = wawona-ios-xcarchive;
          wawona-ios-simulator = wawona-ios-simulator;
          wawona-macos-backend = backend-macos;
          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-tvos-backend = backend-tvos;
          wawona-tvos-sim-backend = backend-tvos-sim;
          wawona-macos-project = xcodegenOutputs.app;
          wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = apple.provisionXcodeScript;
          wawona-ios-xcode-wrapper = apple.xcodeWrapperDrv;
          xcodegen = xcodegenOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          # optional local graphics test package (present in some trees only)
          vulkan-cts = toolchains.buildForMacOS "vulkan-cts" { };
          vulkan-cts-ios = toolchains.buildForIOS "vulkan-cts" { };
          gl-cts = toolchains.buildForMacOS "gl-cts" { };
          gl-cts-ios = toolchains.buildForIOS "gl-cts" { };
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = weston-terminal-pkg;
          foot = (import ./dependencies/wawona/shell-wrappers.nix).footWrapper pkgs (toolchains.buildForMacOS "foot" {}) wawona-macos;
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
        } // (pkgs.lib.optionalAttrs hasGraphicsValidate {
          graphics-validate-macos = pkgs.callPackage ./dependencies/tests/graphics-validate.nix { };
        })));
      in packages;

    getAppsForSystem = system: pkgs: systemPackages:
      let
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import ./dependencies/apple { inherit (pkgs) lib pkgs; nixXcodeenvtests = inputs."nix-xcodeenvtests"; };
        };
        hasGraphicsValidate = builtins.pathExists ./dependencies/tests/graphics-validate.nix;
        hasAndroidCts = builtins.pathExists ./dependencies/libs/vulkan-cts/android.nix
          && builtins.pathExists ./dependencies/libs/vulkan-cts/gl-cts-android.nix;
      in {
        nom = { type = "app"; program = "${pkgs.nix-output-monitor}/bin/nom"; };
        local-runner = { type = "app"; program = "${systemPackages.local-runner}/bin/local-runner"; };
        wawona-android-provision = { type = "app"; program = "${systemPackages.wawona-android-provision}/bin/provision-android"; };
        wawona-android-project = { type = "app"; program = "${systemPackages.gradlegen}/bin/gradlegen"; };
        wawona-android = { type = "app"; program = "${systemPackages.wawona-android}/bin/wawona-android-run"; };
        wawona-wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
        wearos = { type = "app"; program = "${systemPackages.wawona-wearos}/bin/wawona-wearos-run"; };
      } // (pkgs.lib.optionalAttrs hasAndroidCts {
        vulkan-cts-android = { type = "app"; program = "${systemPackages.vulkan-cts-android}/bin/vulkan-cts-android-run"; };
        gl-cts-android = { type = "app"; program = "${systemPackages.gl-cts-android}/bin/gl-cts-android-run"; };
      }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
        default = { type = "app"; program = "${systemPackages.wawona-linux}/bin/wawona-linux-run"; };
        wawona-linux = { type = "app"; program = "${systemPackages.wawona-linux}/bin/wawona-linux-run"; };
        wawona-linux-compositor-host = { type = "app"; program = "${systemPackages.wawona-linux-compositor-host}/bin/wawona-linux-compositor-host-run"; };
        wawona-linux-tray = { type = "app"; program = "${systemPackages.wawona-linux-tray}/bin/wawona-linux-tray-run"; };
        weston-simple-shm = { type = "app"; program = "${systemPackages.weston-simple-shm}/bin/weston-simple-shm"; };
        wawona-linux-vm = { type = "app"; program = "${systemPackages.wawona-linux-vm}/bin/wawona-linux-vm-run"; };
      }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        weston = {
          type = "app";
          program = "${(import ./dependencies/wawona/shell-wrappers.nix).westonAppWrapper pkgs systemPackages.weston systemPackages.wawona-macos "weston"}/bin/weston";
        };
        weston-terminal = {
          type = "app";
          program = "${(import ./dependencies/wawona/shell-wrappers.nix).westonAppWrapper pkgs systemPackages.weston systemPackages.wawona-macos "weston-terminal"}/bin/weston-terminal";
        };
        weston-simple-shm = {
          type = "app";
          program = "${(import ./dependencies/wawona/shell-wrappers.nix).westonAppWrapper pkgs systemPackages.weston systemPackages.wawona-macos "weston-simple-shm"}/bin/weston-simple-shm";
        };
        waypipe = {
          type = "app";
          program = "${(import ./dependencies/wawona/shell-wrappers.nix).waypipeWrapper pkgs systemPackages.waypipe systemPackages.wawona-macos}/bin/waypipe";
        };
        foot = { type = "app"; program = "${systemPackages.foot}/bin/foot"; };
        install = { type = "app"; program = "${systemPackages.install}/bin/install"; };
        uninstall = { type = "app"; program = "${systemPackages.uninstall}/bin/uninstall"; };
        wawona-uninstall = { type = "app"; program = "${systemPackages.uninstall}/bin/uninstall"; };
        wawona-macos = { type = "app"; program = "${systemPackages.wawona-macos}/bin/wawona"; };
        wawona-macos-project = { type = "app"; program = "${systemPackages.wawona-macos-project}/bin/xcodegen"; };
        wawona-ios = { type = "app"; program = appPrograms.wawonaIos; };
        wawona-tvos = { type = "app"; program = appPrograms.wawonaTvos; };
        wawona-watchos = { type = "app"; program = appPrograms.wawonaWatchos; };
        wawona-visionos = { type = "app"; program = appPrograms.wawonaVisionos; };
        wawona-ios-project = { type = "app"; program = "${systemPackages.wawona-ios-project}/bin/xcodegen"; };
        wawona-ios-provision = { type = "app"; program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode"; };
      } // (pkgs.lib.optionalAttrs hasGraphicsValidate {
        graphics-validate-macos = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-macos"; };
      }));

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system (pkgsFor system));
  in {
    packages = allSystemPackages;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system (pkgsFor system) allSystemPackages.${system});
    devShells = nixpkgs.lib.genAttrs systemsList (system: {
      default = let
        pkgs = pkgsFor system;
        apple = import ./dependencies/apple { inherit (pkgs) lib pkgs; nixXcodeenvtests = inputs."nix-xcodeenvtests"; };
      in if pkgs.stdenv.isDarwin then (pkgs.mkShell {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.nix-output-monitor pkgs.rustToolchain pkgs.libxkbcommon pkgs.libffi pkgs.wayland-protocols pkgs.openssl ]
          ++ [ apple.ensureIosSimSDK apple.findXcodeScript ];
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
