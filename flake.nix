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

    # Extracted patched-software repos. Wawona is now a pure integration layer
    # consuming the cross-compile toolchain + library substrate (wwn-toolchain)
    # and the patched application ports (wwn-*) as flake inputs. nixpkgs and
    # wwn-toolchain are pinned uniformly so zsh's pkgs.zsh.src and weston's
    # source hashes resolve against one nixpkgs.
    wwn-toolchain.url = "github:Wawona/wwn-toolchain";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
    wwn-iland.url = "github:Wawona/wwn-iland";
    wwn-iland.inputs.nixpkgs.follows = "nixpkgs";
    wwn-iland.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-kmscube.url = "github:Wawona/wwn-kmscube";
    wwn-kmscube.inputs.nixpkgs.follows = "nixpkgs";
    wwn-kmscube.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-kmscube.inputs.wwn-iland.follows = "wwn-iland";
    wwn-weston.url = "github:Wawona/wwn-weston";
    wwn-weston.inputs.nixpkgs.follows = "nixpkgs";
    wwn-weston.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-weston.inputs.wwn-iland.follows = "wwn-iland";
    wwn-weston.inputs.wwn-kmscube.follows = "wwn-kmscube";
    wwn-zsh.url = "github:Wawona/wwn-zsh";
    wwn-zsh.inputs.nixpkgs.follows = "nixpkgs";
    wwn-zsh.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-waypipe.url = "github:Wawona/wwn-waypipe";
    wwn-waypipe.inputs.nixpkgs.follows = "nixpkgs";
    wwn-waypipe.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-coreutils.url = "github:Wawona/wwn-coreutils";
    wwn-coreutils.inputs.nixpkgs.follows = "nixpkgs";
    wwn-coreutils.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-foot.url = "github:Wawona/wwn-foot";
    wwn-foot.inputs.nixpkgs.follows = "nixpkgs";
    wwn-foot.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-fastfetch.url = "github:Wawona/wwn-fastfetch";
    wwn-fastfetch.inputs.nixpkgs.follows = "nixpkgs";
    wwn-fastfetch.inputs.wwn-toolchain.follows = "wwn-toolchain";
  };

  outputs = inputs@{ self, nixpkgs, android-nixpkgs, rust-overlay, crate2nix, wwn-toolchain, wwn-iland, wwn-kmscube, wwn-weston, wwn-zsh, wwn-waypipe, wwn-coreutils, wwn-foot, wwn-fastfetch, ... }:
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
      in (import nixpkgs {
        inherit system;
        overlays = customOverlays;
        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
          android_sdk.accept_license = true;
        };
      }).extend (_final: _prev: {
        # Inject the extracted-repo store paths into the package scope so that
        # `pkgs.callPackage`-based Wawona integration recipes (ios/ipados/macos/
        # watchos, rust-backend-c2n, linux) auto-resolve them through their
        # function signatures instead of via now-deleted in-tree relative paths.
        inherit applePath toolchainsDir androidToolchainNix
          westonSimpleShmPatchedSrcNix westonSimpleShmLinuxNix kmscubeMacosNix kmscubeIosNix
          fastfetchMacosNix fastfetchIosNix fastfetchLdflagsNix;
        # The Apple toolchain (xcode-wrapper) used to live in-tree; wwn-iland's
        # gl-clients recipes accept it as `xcodeUtils`/`iosToolchain`. Resolve it
        # from the wwn-toolchain input so callPackage can auto-fill those formals.
        iosToolchain = import applePath { lib = _final.lib; pkgs = _final; };
        xcodeUtils = _final.iosToolchain;
      });

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

    # --- wwn-* extracted-repo wiring ------------------------------------------
    # Moved recipe trees now live in their own repos; these aliases repoint the
    # former in-tree ./dependencies/... paths at the input store paths. The
    # cross-compile toolchain + library substrate comes from wwn-toolchain via
    # mkToolchains; the merged registry overlays each app repo's fragment.
    mergedRegistry = wwn-toolchain.lib.baseRegistry
      // wwn-iland.registryFragment
      // wwn-kmscube.registryFragment
      // wwn-weston.registryFragment
      // wwn-zsh.registryFragment
      // wwn-waypipe.registryFragment
      // wwn-foot.registryFragment
      // wwn-fastfetch.registryFragment;
    mkWawonaToolchains = { pkgs, pkgsAndroid ? null, pkgsIos ? null, androidSDK ? null, androidAllowExperimentalFallback ? false, wawonaSrc ? null }:
      wwn-toolchain.lib.mkToolchains {
        inherit pkgs pkgsAndroid pkgsIos androidSDK androidAllowExperimentalFallback wawonaSrc;
        registry = mergedRegistry;
        extraArgs = { ilandSrc = wwn-iland; };
      };
    # Repointed paths into the extracted repos.
    applePath = "${wwn-toolchain}/dependencies/apple";
    toolchainsDir = "${wwn-toolchain}/dependencies/toolchains";
    androidToolchainNix = "${wwn-toolchain}/dependencies/toolchains/android.nix";
    androidToolchainSanityNix = "${wwn-toolchain}/dependencies/toolchains/android-toolchain-sanity.nix";
    waypipePatchedSrcNix = "${wwn-waypipe}/dependencies/libs/waypipe/waypipe-patched-src.nix";
    waypipePatchAndroidSh = "${wwn-waypipe}/dependencies/libs/waypipe/patch-waypipe-android.sh";
    waypipePatchSourceSh = "${wwn-waypipe}/dependencies/libs/waypipe/patch-waypipe-source.sh";
    coreutilsPatchedSrcNix = "${wwn-coreutils}/dependencies/libs/coreutils/coreutils-patched-src.nix";
    coreutilsPatchSourceSh = "${wwn-coreutils}/dependencies/libs/coreutils/patch-coreutils-source.sh";
    coreutilsMulticallNix = "${wwn-coreutils}/dependencies/libs/coreutils/multicall.nix";
    westonSimpleShmPatchedSrcNix = "${wwn-weston}/dependencies/libs/weston-simple-shm/patched-src.nix";
    westonSimpleShmLinuxNix = "${wwn-weston}/dependencies/libs/weston-simple-shm/linux.nix";
    kmscubeMacosNix = "${wwn-kmscube}/dependencies/clients/kmscube/macos.nix";
    kmscubeIosNix = "${wwn-kmscube}/dependencies/clients/kmscube/apple-mobile.nix";
    kmscubeLdflagsNix = "${wwn-kmscube}/dependencies/generators/kmscube-ldflags.nix";
    fastfetchMacosNix = "${wwn-fastfetch}/dependencies/clients/fastfetch/macos.nix";
    fastfetchIosNix = "${wwn-fastfetch}/dependencies/clients/fastfetch/apple-mobile.nix";
    fastfetchLdflagsNix = "${wwn-fastfetch}/dependencies/generators/fastfetch-ldflags.nix";
    westonPtySpikeIosNix = "${wwn-weston}/dependencies/clients/weston/ios-pty-spike/ios.nix";
    westonToytoolkitLdflagsNix = "${wwn-weston}/dependencies/generators/weston-toytoolkit-ldflags.nix";
    # --------------------------------------------------------------------------
    waypipe-src = bootstrapPkgs.fetchFromGitLab {
      owner = "mstoeckl"; repo = "waypipe"; rev = "v0.11.0";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };
    # uutils coreutils umbrella crate — vendored for in-process ls/cat/cp/...
    # on the App-Store-compliant build (no fork/exec). See scripts/ensure-coreutils.sh.
    coreutils-src = bootstrapPkgs.fetchFromGitHub {
      owner = "uutils"; repo = "coreutils"; rev = "0.0.30";
      sha256 = "sha256-OZ9AsCJmQmn271OzEmqSZtt1OPn7zHTScQiiqvPhqB0=";
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

        toolchains = mkWawonaToolchains {
          inherit pkgs wawonaSrc androidSDK androidAllowExperimentalFallback;
          pkgsAndroid = pkgsAndroidCross;
          pkgsIos = pkgsIos;
        };
        appleToolchain = import applePath {
          inherit (pkgs) lib pkgs;
          nixXcodeenvtests = inputs."nix-xcodeenvtests";
        };
        jdk17 = androidPkgs.jdk17;
        gradle = pkgs.gradle_9.override { java = jdk17; };
        
        # On Linux, create a separate toolchains instance using the overlay-free
        # androidPkgs to prevent rust-overlay from triggering recursive evaluation
        # chains through cargo → libsecret → gjs → spidermonkey → cbindgen.
        toolchainsAndroid = if isLinuxHost then mkWawonaToolchains {
          pkgs = androidPkgs;
          inherit wawonaSrc androidSDK androidAllowExperimentalFallback;
          pkgsAndroid = pkgsAndroidCross;
          pkgsIos = null;
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

        waypipe-patched-android = import waypipePatchedSrcNix {
          pkgs = androidPkgs;
          inherit waypipe-src; patchScript = waypipePatchAndroidSh; platform = "android";
        };

        coreutils-patched-android = androidPkgs.callPackage coreutilsPatchedSrcNix {
          inherit coreutils-src; patchScript = coreutilsPatchSourceSh; platform = "android";
        };

        workspace-src-android = androidPkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; coreutilsSrc = coreutils-patched-android; platform = "android"; inherit wawonaVersion;
        };
        workspace-src-wearos = androidPkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; coreutilsSrc = coreutils-patched-android; platform = "wearos"; inherit wawonaVersion;
        };

        backend-android = androidPkgs.callPackage ./dependencies/wawona/rust-backend-android-brp.nix {
          inherit wawonaVersion androidSDK;
          backendName = "wawona-android-backend";
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
        backend-wearos = androidPkgs.callPackage ./dependencies/wawona/rust-backend-android-brp.nix {
          inherit wawonaVersion androidSDK;
          backendName = "wawona-wearos-backend";
          androidToolchain = if isLinuxHost then toolchainsAndroid.androidToolchain else toolchains.androidToolchain;
          workspaceSrc = workspace-src-wearos;
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
          inherit androidToolchainNix westonSimpleShmPatchedSrcNix;
        };
        wawonaWearAndroidPkg = import ./dependencies/wawona/android.nix {
          pkgs = androidPkgs;
          buildModule = toolchainsAndroid;
          inherit (androidPkgs) lib stdenv clang pkg-config unzip zip patchelf file util-linux glslang mesa;
          inherit gradle jdk17 wawonaSrc androidSDK androidUtils;
          androidToolchain = toolchainsAndroid.androidToolchain;
          rustBackend = backend-wearos;
          targetPkgs = pkgsAndroidCross;
          waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
          appTarget = "wearos";
          inherit androidToolchainNix westonSimpleShmPatchedSrcNix;
        };

        androidToolchainSanity = import androidToolchainSanityNix {
          pkgs = androidPkgs;
          androidToolchain = toolchainsAndroid.androidToolchain;
        };

        westonSimpleShmPatched = androidPkgs.callPackage westonSimpleShmPatchedSrcNix { };
        # weston toytoolkit (cairo/pango) closure cross-compiled via the NDK; feeds
        # the APK native build so libweston-13.a and demo *_main symbols can link.
        mobileToytoolkitDepsAndroid =
          import ./dependencies/wawona/mobile-toytoolkit-deps.nix {
            buildFn = toolchainsAndroid.buildForAndroid;
          };
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
        ] ++ (pkgs.lib.attrValues mobileToytoolkitDepsAndroid)
          ++ [
            (toolchainsAndroid.buildForAndroid "weston" { })
            (toolchainsAndroid.buildForAndroid "libintl" { })
          ];
        studioWestonToytoolkitLdflags = import westonToytoolkitLdflagsNix {
          inherit (pkgs) lib;
          deps = mobileToytoolkitDepsAndroid // {
            weston = toolchainsAndroid.buildForAndroid "weston" { };
            libintl = toolchainsAndroid.buildForAndroid "libintl" { };
          };
          forceLoadWeston = true;
          linkMode = "whole_archive";
        };
        studioNixDepIncludes =
          (pkgs.lib.concatMapStringsSep " " (d: "-I${d}/include") studioAndroidDeps)
          + " -I${toolchainsAndroid.buildForAndroid "pixman" { }}/include/pixman-1"
          + " -I${toolchainsAndroid.buildForAndroid "weston" { }}/include/weston-gen";
        studioNixDepLibs =
          (pkgs.lib.concatMapStringsSep " " (d: "-L${d}/lib") studioAndroidDeps)
          + " ${pkgs.lib.concatStringsSep " " studioWestonToytoolkitLdflags}";
        studioRuntimeLibDirs =
          pkgs.lib.concatMapStringsSep ":" (d: "${d}/lib") studioAndroidDeps;
        studioRustBackendLib = "${backend-android}/lib/libwawona.a";
        studioRustBackendSharedLib = "${backend-android}/lib/libwawona_core.so";
        studioOpenSSHBin = "${toolchainsAndroid.buildForAndroid "openssh" { }}/bin/ssh";
        studioSshpassBin = "${toolchainsAndroid.buildForAndroid "sshpass" { }}/bin/sshpass";

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
          opensshBinaryPath = studioOpenSSHBin;
          sshpassBinaryPath = studioSshpassBin;
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
            else pkgs.callPackage westonSimpleShmLinuxNix {};
          foot = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "foot" {} else pkgs.foot;
          fastfetch = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "fastfetch" { } else pkgs.fastfetch;
          waypipe = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "waypipe" { } else pkgs.waypipe;

          # ANGLE (OpenGL ES over Metal) + iland userland graphics core
          # (GBM/EGL/DRM over IOSurface) for nested GL clients (kmscube, es2gears,
          # weston-simple-egl). macOS-first; mobile cross builds are WIP.
          angle = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "angle" { } else pkgs.angle;
          iland = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "iland" { } else null;
          # GL smoke test (kmscube) over iland+ANGLE — nested inside Wawona
          # via the Mode A present-redirect. macOS only.
          kmscube = if pkgs.stdenv.isDarwin
            then pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; }
            else null;
          "iland-gl-clients" = if pkgs.stdenv.isDarwin
            then pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; }
            else null;
          
          # Wawona (Native on Linux, Cross-wrapped on Darwin)
          wawona = if pkgs.stdenv.isDarwin 
            then (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs 
              (pkgs.callPackage ./dependencies/wawona/macos.nix {
                buildModule = toolchains; inherit wawonaSrc wawonaVersion;
                waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
                foot = toolchains.buildForMacOS "foot" { };
                fastfetch = toolchains.buildForMacOS "fastfetch" { };
                rustBackend = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
                  inherit crate2nix wawonaVersion toolchains nixpkgs;
                  workspaceSrc = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
                    wawonaSrc = src;
                    waypipeSrc = pkgs.callPackage waypipePatchedSrcNix {
                      inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "macos";
                    };
                    coreutilsSrc = pkgs.callPackage coreutilsPatchedSrcNix {
                      inherit coreutils-src; patchScript = coreutilsPatchSourceSh; platform = "macos";
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
          wawona-wearos-backend = backend-wearos;
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
          install = pkgs.writeShellScriptBin "install" ''
            set -euo pipefail
            exec ${pkgs.nix}/bin/nix profile install "${self.outPath}#wawona" "$@"
          '';
          default = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
          };
          # Consumer-facing package name for use as a flake input or overlay,
          # matching the nixpkgs convention of installing `pkgs.wawona`.
          wawona = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
          };
        }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          teamId = let value = builtins.getEnv "TEAM_ID"; in if value == "" then null else value;
          apple = import applePath {
            inherit (pkgs) lib pkgs;
            TEAM_ID = teamId;
            nixXcodeenvtests = inputs."nix-xcodeenvtests";
          };
          missingTeamRelease = name: pkgs.runCommand name { } ''
            echo "Set TEAM_ID and build with --impure to produce signed iOS release artifacts." >&2
            exit 1
          '';
          waypipe-patched-macos = pkgs.callPackage waypipePatchedSrcNix {
            inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "macos";
          };
          coreutils-patched-macos = pkgs.callPackage coreutilsPatchedSrcNix {
            inherit coreutils-src; patchScript = coreutilsPatchSourceSh; platform = "macos";
          };
          waypipe-patched-ios = pkgs.callPackage waypipePatchedSrcNix {
            inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "ios";
          };
          waypipe-patched-ipados = pkgs.callPackage waypipePatchedSrcNix {
            inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "ios";
          };
          waypipe-patched-watchos = pkgs.callPackage waypipePatchedSrcNix {
            inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "ios";
          };
          coreutils-patched-ios = pkgs.callPackage coreutilsPatchedSrcNix {
            inherit coreutils-src; patchScript = coreutilsPatchSourceSh; platform = "ios";
          };
          weston-terminal-pkg = pkgs.runCommand "weston-terminal" { } ''
            mkdir -p "$out/bin"
            ln -s "${commonPackages.weston}/bin/weston-terminal" "$out/bin/weston-terminal"
          '';
          # macOS/Android exec-path userland: a uutils multicall binary (NOT the
          # in-process staticlib shim, which is Apple-mobile only). Prepend
          # "${coreutils-multicall-macos}/bin" to the macOS shell PATH.
          coreutils-multicall-macos = pkgs.callPackage coreutilsMulticallNix {
            inherit coreutils-src;
          };
          workspace-src-macos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-macos; coreutilsSrc = coreutils-patched-macos; platform = "macos"; inherit wawonaVersion;
          };
          workspace-src-ios = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-ios; coreutilsSrc = coreutils-patched-ios; platform = "ios"; inherit wawonaVersion;
          };
          workspace-src-ipados = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-ipados; coreutilsSrc = coreutils-patched-ios; platform = "ipados"; inherit wawonaVersion;
          };
          workspace-src-watchos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-watchos; coreutilsSrc = coreutils-patched-ios; platform = "watchos"; inherit wawonaVersion;
          };
          mobilePlatformDeps = import ./dependencies/wawona/mobile-platform-deps.nix { lib = pkgs.lib; inherit pkgs; };
          macosDeps = {
            libwayland = toolchains.buildForMacOS "libwayland" { };
            xkbcommon = toolchains.buildForMacOS "xkbcommon" { };
            waypipe = toolchains.buildForMacOS "waypipe" { };
            sshpass = toolchains.buildForMacOS "sshpass" { };
          };
          iosDeps = mobilePlatformDeps { buildFn = toolchains.buildForIOS; inherit toolchains; };
          iosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForIOS; inherit toolchains; simulator = true; };
          ipadosDeps = mobilePlatformDeps { buildFn = toolchains.buildForIPadOS; inherit toolchains; };
          ipadosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForIPadOS; inherit toolchains; simulator = true; };
          tvosDeps = mobilePlatformDeps { buildFn = toolchains.buildForTVOS; inherit toolchains; variant = "tv"; };
          tvosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForTVOS; inherit toolchains; variant = "tv"; simulator = true; };
          visionosDeps = mobilePlatformDeps { buildFn = toolchains.buildForVisionOS; inherit toolchains; variant = "vision"; };
          visionosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForVisionOS; inherit toolchains; variant = "vision"; simulator = true; };
          watchosDeps = mobilePlatformDeps { buildFn = toolchains.buildForWatchOS; inherit toolchains; variant = "watch"; };
          watchosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForWatchOS; inherit toolchains; variant = "watch"; simulator = true; };
          appleHostCrates = pkgs.callPackage ./dependencies/wawona/apple-host-crates.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios;
            nativeDeps = iosDeps;
          };
          backend-macos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-macos; platform = "macos"; nativeDeps = macosDeps;
          };
          backend-ios = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "ios"; nativeDeps = iosDeps;
          };
          backend-ios-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "ios"; simulator = true; nativeDeps = iosSimDeps;
          };
          backend-ipados = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ipados; platform = "ipados"; nativeDeps = ipadosDeps;
          };
          backend-ipados-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ipados; platform = "ipados"; simulator = true; nativeDeps = ipadosSimDeps;
          };
          backend-tvos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "tvos"; nativeDeps = tvosDeps;
          };
          backend-tvos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "tvos"; simulator = true; nativeDeps = tvosSimDeps;
          };
          backend-visionos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "visionos"; nativeDeps = visionosDeps;
          };
          backend-visionos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "visionos"; simulator = true; nativeDeps = visionosSimDeps;
          };
          backend-watchos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-watchos; platform = "watchos"; nativeDeps = watchosDeps;
          };
          backend-watchos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-watchos; platform = "watchos"; simulator = true; nativeDeps = watchosSimDeps;
          };
          mkXcodegen = platformFilter: pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc iosDeps iosSimDeps ipadosDeps ipadosSimDeps tvosDeps tvosSimDeps visionosDeps visionosSimDeps watchosDeps watchosSimDeps macosDeps platformFilter;
             macosBackend = backend-macos;
             iosBackend = backend-ios;
             iosSimBackend = backend-ios-sim;
             ipadosBackend = backend-ipados;
             ipadosSimBackend = backend-ipados-sim;
             tvosBackend = backend-tvos;
             tvosSimBackend = backend-tvos-sim;
             visionosBackend = backend-visionos;
             visionosSimBackend = backend-visionos-sim;
             watchosBackend = backend-watchos;
             watchosSimBackend = backend-watchos-sim;
             macosWeston = toolchains.buildForMacOS "weston" { };
             macosFoot = toolchains.buildForMacOS "foot" { };
             macosFastfetch = toolchains.buildForMacOS "fastfetch" { };
          };
          xcodegenOutputs = mkXcodegen null;
          xcodegenIosOutputs = mkXcodegen [ "ios" "ipados" ];
          xcodegenMacosOutputs = mkXcodegen [ "macos" ];
          xcodegenAppleOutputs = mkXcodegen [ "ios" "ipados" "macos" ];
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            foot = toolchains.buildForMacOS "foot" { };
            fastfetch = toolchains.buildForMacOS "fastfetch" { };
            # Keep runtime package host-only: do not force xcodegen/project outputs,
            # which pull in non-macOS backend graphs.
            rustBackend = backend-macos;
            xcodeProject = "";
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
          wawona-watchos-app-device = pkgs.callPackage ./dependencies/wawona/watchos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
          };
          wawona-ios-app-device = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
          };
          wawona-ipados-app-sim = pkgs.callPackage ./dependencies/wawona/ipados.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
          };
          wawona-ipados-app-device = pkgs.callPackage ./dependencies/wawona/ipados.nix {
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
          coreutils-multicall-macos = coreutils-multicall-macos;
          wawona-ios = wawona-ios-app-sim;
          wawona-ipados = wawona-ipados-app-sim;
          wawona-tvos = wawona-tvos-app-sim;
          wawona-watchos = wawona-watchos-app-sim;
          wawona-visionos = wawona-visionos-app-sim;
          wawona-ios-app-sim = wawona-ios-app-sim;
          wawona-ipados-app-sim = wawona-ipados-app-sim;
          wawona-tvos-app-sim = wawona-tvos-app-sim;
          wawona-watchos-app-sim = wawona-watchos-app-sim;
          wawona-visionos-app-sim = wawona-visionos-app-sim;
          wawona-ios-app-device = wawona-ios-app-device;
          wawona-ipados-app-device = wawona-ipados-app-device;
          wawona-tvos-app-device = wawona-tvos-app-device;
          wawona-watchos-app-device = wawona-watchos-app-device;
          wawona-ios-ipa = wawona-ios-ipa;
          wawona-ios-xcarchive = wawona-ios-xcarchive;
          wawona-ios-simulator = wawona-ios-simulator;
          wawona-macos-backend = backend-macos;
          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-ipados-backend = backend-ipados;
          wawona-ipados-sim-backend = backend-ipados-sim;
          wawona-tvos-backend = backend-tvos;
          wawona-tvos-sim-backend = backend-tvos-sim;
          wawona-visionos-backend = backend-visionos;
          wawona-visionos-sim-backend = backend-visionos-sim;
          wawona-watchos-backend = backend-watchos;
          wawona-watchos-sim-backend = backend-watchos-sim;
          wawona-macos-project = xcodegenOutputs.app;
          wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = apple.provisionXcodeScript;
          wawona-ios-xcode-wrapper = apple.xcodeWrapperDrv;
          xcodegen = xcodegenOutputs.app;
          xcodegen-ios = xcodegenIosOutputs.app;
          xcodegen-macos = xcodegenMacosOutputs.app;
          xcodegen-apple = xcodegenAppleOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = weston-terminal-pkg;
          foot = (import ./dependencies/wawona/shell-wrappers.nix).footWrapper pkgs (toolchains.buildForMacOS "foot" {}) wawona-macos;
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          # weston toytoolkit (cairo/pango) cross-compile stack for Apple mobile,
          # exposed individually for incremental build verification.
          freetype-ios = toolchains.buildForIOS "freetype" { };
          fribidi-ios = toolchains.buildForIOS "fribidi" { };
          pcre2-ios = toolchains.buildForIOS "pcre2" { };
          fontconfig-ios = toolchains.buildForIOS "fontconfig" { };
          glib-ios = toolchains.buildForIOS "glib" { };
          harfbuzz-ios = toolchains.buildForIOS "harfbuzz" { };
          cairo-ios = toolchains.buildForIOS "cairo" { };
          pango-ios = toolchains.buildForIOS "pango" { };
          libpng-ios = toolchains.buildForIOS "libpng" { };
          weston-ios = toolchains.buildForIOS "weston" { };
          weston-compositor-ios = toolchains.buildForIOS "weston-compositor" { };
          weston-compositor-ios-drm = toolchains.buildForIOS "weston-compositor-drm" { };
          weston-compositor-ios-drm-sim = toolchains.buildForIOS "weston-compositor-drm" { simulator = true; };
          angle-ios = toolchains.buildForIOS "angle" { };
          angle-ios-sim = toolchains.buildForIOS "angle" { simulator = true; };
          angle-android = toolchainsAndroid.buildForAndroid "angle" { };
          iland-ios = toolchains.buildForIOS "iland" { };
          iland-ios-sim = toolchains.buildForIOS "iland" { simulator = true; };
          kmscube-ios = toolchains.buildForIOS "kmscube" { simulator = true; };
          kmscube-ios-device = toolchains.buildForIOS "kmscube" { simulator = false; };
          fastfetch-ios = toolchains.buildForIOS "fastfetch" { simulator = true; };
          fastfetch-ios-device = toolchains.buildForIOS "fastfetch" { simulator = false; };
          fastfetch-macos = toolchains.buildForMacOS "fastfetch" { };
          iland-gl-clients-ios = toolchains.buildForIOS "kmscube" { simulator = true; };
          iland-gl-clients-ios-device = toolchains.buildForIOS "kmscube" { simulator = false; };
          weston-ios-gl = toolchains.buildForIOS "weston" { enableGlClients = true; };
          weston-ios-gl-sim = toolchains.buildForIOS "weston" { simulator = true; enableGlClients = true; };
          "wawona-pty-ios" = toolchains.buildForIOS "wawona-pty" { };
          "wawona-pty-ios-sim" = toolchains.buildForIOS "wawona-pty" { simulator = true; };
          zsh-ios = toolchains.buildForIOS "zsh" { };
          zsh-ios-sim = toolchains.buildForIOS "zsh" { simulator = true; };
          "zsh-framework-ios" = toolchains.buildForIOS "zsh-framework" { };
          "zsh-framework-ios-sim" = toolchains.buildForIOS "zsh-framework" { simulator = true; };
          "wawona-rootfs-ios" = toolchains.buildForIOS "wawona-rootfs" { };
          "wawona-rootfs-ios-sim" = toolchains.buildForIOS "wawona-rootfs" { simulator = true; };
          "wawona-pty-spike-ios" = pkgs.callPackage westonPtySpikeIosNix {
            buildModule = toolchains;
            iosToolchain = import applePath { inherit (pkgs) lib pkgs; };
            simulator = false;
          };
          "wawona-pty-spike-ios-sim" = pkgs.callPackage westonPtySpikeIosNix {
            buildModule = toolchains;
            iosToolchain = import applePath { inherit (pkgs) lib pkgs; };
            simulator = true;
          };
          # weston toytoolkit (cairo/pango) cross-compile stack for Android (NDK),
          # exposed individually for incremental build verification.
          freetype-android = toolchainsAndroid.buildForAndroid "freetype" { };
          fribidi-android = toolchainsAndroid.buildForAndroid "fribidi" { };
          pcre2-android = toolchainsAndroid.buildForAndroid "pcre2" { };
          fontconfig-android = toolchainsAndroid.buildForAndroid "fontconfig" { };
          glib-android = toolchainsAndroid.buildForAndroid "glib" { };
          harfbuzz-android = toolchainsAndroid.buildForAndroid "harfbuzz" { };
          cairo-android = toolchainsAndroid.buildForAndroid "cairo" { };
          pango-android = toolchainsAndroid.buildForAndroid "pango" { };
          libpng-android = toolchainsAndroid.buildForAndroid "libpng" { };
          weston-android = toolchainsAndroid.buildForAndroid "weston" { };
          weston-compositor-android = toolchainsAndroid.buildForAndroid "weston-compositor" { };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
          # Consumer-facing package name for use as a flake input or overlay,
          # matching the nixpkgs convention of installing `pkgs.wawona`.
          wawona = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
        } // (pkgs.lib.optionalAttrs (builtins.pathExists ./dependencies/libs/vulkan-cts) {
          # Optional local graphics test packages (present in some trees only).
          vulkan-cts = toolchains.buildForMacOS "vulkan-cts" { };
          vulkan-cts-ios = toolchains.buildForIOS "vulkan-cts" { };
        }) // (pkgs.lib.optionalAttrs (builtins.pathExists ./dependencies/libs/gl-cts) {
          gl-cts = toolchains.buildForMacOS "gl-cts" { };
          gl-cts-ios = toolchains.buildForIOS "gl-cts" { };
        }) // (pkgs.lib.optionalAttrs hasGraphicsValidate {
          graphics-validate-macos = pkgs.callPackage ./dependencies/tests/graphics-validate.nix { };
        })));
      in packages;

    getAppsForSystem = system: pkgs: systemPackages:
      let
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import applePath { inherit (pkgs) lib pkgs; nixXcodeenvtests = inputs."nix-xcodeenvtests"; };
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
        install = { type = "app"; program = "${systemPackages.install}/bin/install"; };
        wawona = { type = "app"; program = "${systemPackages.wawona}/bin/wawona-linux-run"; };
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
        wawona = { type = "app"; program = "${systemPackages.wawona}/bin/wawona"; };
        uninstall = { type = "app"; program = "${systemPackages.uninstall}/bin/uninstall"; };
        wawona-uninstall = { type = "app"; program = "${systemPackages.uninstall}/bin/uninstall"; };
        wawona-macos = { type = "app"; program = "${systemPackages.wawona-macos}/bin/wawona"; };
        wawona-macos-project = { type = "app"; program = "${systemPackages.wawona-macos-project}/bin/xcodegen"; };
        wawona-ios = { type = "app"; program = appPrograms.wawonaIos; };
        wawona-ipados = { type = "app"; program = appPrograms.wawonaIpad; };
        wawona-tvos = { type = "app"; program = appPrograms.wawonaTvos; };
        wawona-watchos = { type = "app"; program = appPrograms.wawonaWatchos; };
        wawona-visionos = { type = "app"; program = appPrograms.wawonaVisionos; };
        wawona-ios-project = { type = "app"; program = "${systemPackages.wawona-ios-project}/bin/xcodegen"; };
        xcodegen-ios = { type = "app"; program = "${systemPackages.xcodegen-ios}/bin/xcodegen"; };
        xcodegen-macos = { type = "app"; program = "${systemPackages.xcodegen-macos}/bin/xcodegen"; };
        xcodegen-apple = { type = "app"; program = "${systemPackages.xcodegen-apple}/bin/xcodegen"; };
        wawona-ios-provision = { type = "app"; program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode"; };
      } // (pkgs.lib.optionalAttrs hasGraphicsValidate {
        graphics-validate-macos = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-macos"; };
      }));

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system (pkgsFor system));
  in {
    packages = allSystemPackages;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system (pkgsFor system) allSystemPackages.${system});
    overlays.default = final: prev: {
      wawona = self.packages.${prev.stdenv.hostPlatform.system}.wawona;
    };
    devShells = import ./dependencies/wawona/devshells.nix {
      systems = systemsList;
      pkgsFor = pkgsFor;
    } // nixpkgs.lib.genAttrs systemsList (system: {
      # Legacy alias; prefer `nix develop` default from devshells.nix.
      wawona = (import ./dependencies/wawona/devshells.nix {
        systems = [ system ];
        pkgsFor = pkgsFor;
      }).${system}.default;
    });
    checks = nixpkgs.lib.genAttrs systemsList (system: let pkgs = pkgsFor system; in pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
      graphics-validate-smoke = pkgs.runCommand "graphics-validate-smoke" { nativeBuildInputs = [ pkgs.coreutils ]; } "echo 'smoke check'; test -n '${allSystemPackages.${system}.wawona-android}'; touch $out";
    });
  };
}
