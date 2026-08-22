{
  description = "Wawona Compositor";

  # Runner defaults for compile-heavy attrs. CI may reinforce via installer extra-conf.
  nixConfig = {
    max-jobs = "auto";
    cores = 0;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/5585cc3ee71bdd8d9ee255523f11b920138fa688";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    crate2nix.url = "github:nix-community/crate2nix";
    # Keep crate2nix on the single nixpkgs lineage; without this it and its
    # transitive cachix pull independent nixpkgs revs into flake.lock (#47).
    crate2nix.inputs.nixpkgs.follows = "nixpkgs";
    # p26-vm-nixos: microvm.nix drives a NixOS guest under vfkit
    # (Virtualization.framework) on macOS. Provides the writableStoreOverlay +
    # virtiofs ro-store rootfs (no make-disk-image/KVM) and the vsock plumbing
    # the Wayland-into-Wawona bridge needs.
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
    # Reproducible, glibc-portable AppImage bundler (static appimage runtime +
    # userns-chroot AppRun that maps the bundled /nix/store closure).
    nix-appimage.url = "github:ralismark/nix-appimage";
    nix-appimage.inputs.nixpkgs.follows = "nixpkgs";
    "nix-xcodeenvtests" = {
      url = "github:svanderburg/nix-xcodeenvtests";
      flake = false;
    };

    # Extracted patched-software repos. Wawona is now a pure integration layer
    # consuming the cross-compile toolchain + library substrate (wwn-toolchain)
    # and the patched application ports (wwn-*) as flake inputs. nixpkgs and
    # wwn-toolchain are pinned uniformly so zsh's pkgs.zsh.src and weston's
    # source hashes resolve against one nixpkgs.
    wwn-toolchain.url = "https://flakehub.com/f/Wawona/wwn-toolchain/*";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
    wwn-iland.url = "github:Wawona/wwn-iland/development";
    wwn-iland.inputs.nixpkgs.follows = "nixpkgs";
    wwn-iland.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-kmscube.url = "https://flakehub.com/f/Wawona/wwn-kmscube/*";
    wwn-kmscube.inputs.nixpkgs.follows = "nixpkgs";
    wwn-kmscube.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-kmscube.inputs.wwn-iland.follows = "wwn-iland";
    wwn-weston.url = "https://flakehub.com/f/Wawona/wwn-weston/*";
    wwn-weston.inputs.nixpkgs.follows = "nixpkgs";
    wwn-weston.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-weston.inputs.wwn-iland.follows = "wwn-iland";
    wwn-weston.inputs.wwn-kmscube.follows = "wwn-kmscube";
    wwn-zsh.url = "https://flakehub.com/f/Wawona/wwn-zsh/*";
    wwn-zsh.inputs.nixpkgs.follows = "nixpkgs";
    wwn-zsh.inputs.wwn-toolchain.follows = "wwn-toolchain";
    # SSH stack split out of wwn-toolchain: chooses the App-Store/Play
    # compliant backend per platform (libssh2 CLI on Apple mobile. Never
    # OpenSSH; OpenSSH portable on Android; regular OpenSSH on macOS/Linux)
    # + sshpass.
    wwn-ssh.url = "https://flakehub.com/f/Wawona/wwn-ssh/*";
    wwn-ssh.inputs.nixpkgs.follows = "nixpkgs";
    wwn-ssh.inputs.rust-overlay.follows = "rust-overlay";
    wwn-ssh.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-waypipe.url = "https://flakehub.com/f/Wawona/wwn-waypipe/*";
    wwn-waypipe.inputs.nixpkgs.follows = "nixpkgs";
    wwn-waypipe.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-waypipe.inputs.wwn-ssh.follows = "wwn-ssh";
    wwn-swinging-bridge.url = "github:Wawona/Wawona-Swinging-Bridge";
    wwn-swinging-bridge.inputs.nixpkgs.follows = "nixpkgs";
    wwn-swinging-bridge.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-swinging-bridge.inputs.rust-overlay.follows = "rust-overlay";
    wwn-coreutils.url = "https://flakehub.com/f/Wawona/wwn-coreutils/*";
    wwn-coreutils.inputs.nixpkgs.follows = "nixpkgs";
    wwn-coreutils.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-foot.url = "https://flakehub.com/f/Wawona/wwn-foot/*";
    wwn-foot.inputs.nixpkgs.follows = "nixpkgs";
    wwn-foot.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-fastfetch.url = "https://flakehub.com/f/Wawona/wwn-fastfetch/*";
    wwn-fastfetch.inputs.nixpkgs.follows = "nixpkgs";
    wwn-fastfetch.inputs.wwn-toolchain.follows = "wwn-toolchain";
    # phoon (clean-room Rust moon-phase utility), in-process shell tool.
    wwn-phoon-rs.url = "https://flakehub.com/f/Wawona/wwn-phoon-rs/*";
    wwn-phoon-rs.inputs.nixpkgs.follows = "nixpkgs";
    wwn-phoon-rs.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-phoon-rs.inputs.rust-overlay.follows = "rust-overlay";
    wwn-neovim.url = "https://flakehub.com/f/Wawona/wwn-neovim/*";
    wwn-neovim.inputs.nixpkgs.follows = "nixpkgs";
    wwn-neovim.inputs.wwn-toolchain.follows = "wwn-toolchain";
    # WASI P1/P2 interpreter (Pulley on Apple mobile). L3′. Toolchain only.
    # Cited: docs/wwn-repo-dag.md. github: until FlakeHub rolling exists.
    wwn-wasm.url = "github:Wawona/wwn-wasm";
    wwn-wasm.inputs.nixpkgs.follows = "nixpkgs";
    wwn-wasm.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-wasm.inputs.rust-overlay.follows = "rust-overlay";
    # niri (scrollable-tiling compositor), Phase-29 port #1: runs nested as a
    # Wayland client of the Wawona compositor on every target.
    wwn-niri.url = "https://flakehub.com/f/Wawona/wwn-niri/*";
    wwn-niri.inputs.nixpkgs.follows = "nixpkgs";
    wwn-niri.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-niri.inputs.rust-overlay.follows = "rust-overlay";
    # VM + container substrate. wwn-containers depends on wwn-vms, so pin both to
    # Wawona's single nixpkgs/toolchain and make containers follow this same
    # wwn-vms.
    wwn-vms.url = "https://flakehub.com/f/Wawona/wwn-vms/*";
    wwn-vms.inputs.nixpkgs.follows = "nixpkgs";
    wwn-vms.inputs.rust-overlay.follows = "rust-overlay";
    wwn-vms.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-vms.inputs.microvm.follows = "microvm";
    wwn-containers.url = "https://flakehub.com/f/Wawona/wwn-containers/*";
    wwn-containers.inputs.nixpkgs.follows = "nixpkgs";
    wwn-containers.inputs.rust-overlay.follows = "rust-overlay";
    wwn-containers.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-containers.inputs.wwn-vms.follows = "wwn-vms";
    # macOS Watchdog tools (IOWatchdog / watchdogd). L3'. Desktop Mode B only.
    # Cited: docs/wwn-repo-dag.md. github: until FlakeHub rolling exists.
    wwn-iowatchdog.url = "github:Wawona/wwn-iowatchdog/development";
    wwn-iowatchdog.inputs.nixpkgs.follows = "nixpkgs";
    # Linux-shaped VTs + Doorman login after Mode B own-display. L3'.
    # Cited: docs/wwn-repo-dag.md. github: until FlakeHub rolling exists.
    wwn-igetty.url = "github:Wawona/wwn-igetty/development";
    wwn-igetty.inputs.nixpkgs.follows = "nixpkgs";
    wwn-igetty.inputs.rust-overlay.follows = "rust-overlay";
    wwn-igetty.inputs.wwn-toolchain.follows = "wwn-toolchain";
    wwn-igetty.inputs.wwn-iland.follows = "wwn-iland";
    wwn-igetty.inputs.doorman.follows = "doorman";
    # Mode B console login (Linux getty/login parity). L3' peer, macOS-only.
    # Own nixpkgs + system SDK; do not follow Wawona nixpkgs.
    # Cited: docs/wwn-repo-dag.md.
    doorman.url = "github:Wawona/doorman";
  };

  outputs = inputs@{ self, nixpkgs, android-nixpkgs, rust-overlay, crate2nix, nix-appimage, wwn-toolchain, wwn-iland, wwn-kmscube, wwn-weston, wwn-zsh, wwn-ssh, wwn-waypipe, wwn-swinging-bridge, wwn-coreutils, wwn-foot, wwn-fastfetch, wwn-phoon-rs, wwn-neovim, wwn-wasm, wwn-niri, wwn-vms, wwn-containers, wwn-iowatchdog, wwn-igetty, doorman, ... }:
  let
    linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
    # Nixpkgs 26.11 throws on x86_64-darwin eval; flakehub-push runs
    # `nix flake show --all-systems`. Intel Mac is gone from this flake's
    # packages/apps surface; aarch64-darwin remains the Darwin target.
    darwinSystems = [ "aarch64-darwin" ];
    systemsList = linuxSystems ++ darwinSystems;

    pkgsFor = system:
      let
        isDarwin = (system == "x86_64-darwin" || system == "aarch64-darwin");
        customOverlays =
          [ (import rust-overlay) ]
          ++ (if isDarwin then [
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
          ] else [
            (self: super: {
              rustToolchain = super.rust-bin.stable.latest.default;
            })
          ]);
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
        inherit applePath toolchainsDir androidToolchainNix androidConfigNix androidWrapperNix
          westonSimpleShmPatchedSrcNix westonSimpleShmLinuxNix kmscubeMacosNix kmscubeIosNix
          fastfetchMacosNix fastfetchIosNix fastfetchLdflagsNix
          neovimMacosNix neovimIosNix neovimLdflagsNix
          westonToytoolkitLdflagsNix westonCompositorLdflagsNix mobileBaseLdflagsNix ilandGlLdflagsNix
          ilandGlAndroidLdflagsNix westonAndroidSignalPolyfill;
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
      // wwn-ssh.registryFragment
      // wwn-iland.registryFragment
      // wwn-kmscube.registryFragment
      // wwn-weston.registryFragment
      // wwn-zsh.registryFragment
      // wwn-waypipe.registryFragment
      // wwn-swinging-bridge.registryFragment
      // wwn-foot.registryFragment
      // wwn-fastfetch.registryFragment
      // wwn-phoon-rs.registryFragment
      // wwn-neovim.registryFragment
      // wwn-wasm.registryFragment
      // wwn-niri.registryFragment
      // wwn-vms.registryFragment
      // wwn-containers.registryFragment;
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
    westonAndroidSignalPolyfill = "${wwn-weston}/dependencies/toolchains/wwn-android-signal-polyfill.h";
    westonSimpleShmLinuxNix = "${wwn-weston}/dependencies/libs/weston-simple-shm/linux.nix";
    kmscubeMacosNix = "${wwn-kmscube}/dependencies/clients/kmscube/macos.nix";
    kmscubeIosNix = "${wwn-kmscube}/dependencies/clients/kmscube/apple-mobile.nix";
    kmscubeLdflagsNix = "${wwn-kmscube}/dependencies/generators/kmscube-ldflags.nix";
    fastfetchMacosNix = "${wwn-fastfetch}/dependencies/clients/fastfetch/macos.nix";
    fastfetchIosNix = "${wwn-fastfetch}/dependencies/clients/fastfetch/apple-mobile.nix";
    fastfetchLdflagsNix = "${wwn-fastfetch}/dependencies/generators/fastfetch-ldflags.nix";
    neovimMacosNix = "${wwn-neovim}/dependencies/libs/neovim/macos.nix";
    neovimIosNix = "${wwn-neovim}/dependencies/libs/neovim/apple-mobile.nix";
    neovimLdflagsNix = "${wwn-neovim}/dependencies/generators/neovim-ldflags.nix";
    westonPtySpikeIosNix = "${wwn-weston}/dependencies/clients/weston/ios-pty-spike/ios.nix";
    westonToytoolkitLdflagsNix = "${wwn-weston}/dependencies/generators/weston-toytoolkit-ldflags.nix";
    westonCompositorLdflagsNix = "${wwn-weston}/dependencies/generators/weston-compositor-ldflags.nix";
    mobileBaseLdflagsNix = "${wwn-toolchain}/dependencies/generators/mobile-base-ldflags.nix";
    ilandGlLdflagsNix = "${wwn-iland}/dependencies/generators/iland-gl-ldflags.nix";
    ilandGlAndroidLdflagsNix = "${wwn-iland}/dependencies/generators/iland-gl-android-ldflags.nix";
    androidConfigNix = "${wwn-toolchain}/dependencies/android/sdk-config.nix";
    androidWrapperNix = "${wwn-toolchain}/dependencies/utils/android-wrapper.nix";
    # --------------------------------------------------------------------------
    waypipe-src = bootstrapPkgs.fetchFromGitLab {
      owner = "mstoeckl"; repo = "waypipe"; rev = "v0.11.0";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };
    # uutils coreutils umbrella crate. Vendored for in-process ls/cat/cp/...
    # on the App-Store-compliant build (no fork/exec). See scripts/ensure-coreutils.sh.
    coreutils-src = bootstrapPkgs.fetchFromGitHub {
      owner = "uutils"; repo = "coreutils"; rev = "0.0.30";
      sha256 = "sha256-OZ9AsCJmQmn271OzEmqSZtt1OPn7zHTScQiiqvPhqB0=";
    };

    getPackagesForSystem = system: pkgs:
      let
        isLinuxHost = builtins.elem system linuxSystems;

        # Clean package set for Android. Only the rust-overlay is included
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

        androidConfig = import androidConfigNix {
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

        androidUtils = import androidWrapperNix {
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
        # Android PATH multicall (libcoreutils_bin.so); same safe subset as
        # in-process / macOS multicall. Requires rust-overlay on androidPkgs.
        coreutils-multicall-android = androidPkgs.callPackage
          "${wwn-coreutils}/dependencies/libs/coreutils/multicall-android.nix" {
            coreutils-src = coreutils-patched-android;
            androidToolchain = toolchainsAndroid.androidToolchain;
          };

        workspace-src-android = androidPkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; coreutilsSrc = coreutils-patched-android; platform = "android"; inherit wawonaVersion;
        };

        backend-android = androidPkgs.callPackage ./dependencies/wawona/rust-backend-android-brp.nix {
          inherit wawonaVersion androidSDK androidToolchainNix;
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
            ffmpeg = toolchainsAndroid.buildForAndroid "ffmpeg" {};
          };
        };
        wawonaAndroidPkg = import ./dependencies/wawona/android.nix {
          pkgs = androidPkgs;
          buildModule = toolchainsAndroid;
          inherit (androidPkgs) lib stdenv clang pkg-config unzip zip patchelf file util-linux glslang mesa;
          inherit gradle jdk17 wawonaSrc androidSDK androidUtils;
          srcFiltered = src;
          androidToolchain = toolchainsAndroid.androidToolchain;
          rustBackend = backend-android;
          coreutilsAndroid = coreutils-multicall-android;
          targetPkgs = pkgsAndroidCross;
          waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
          inherit androidToolchainNix westonSimpleShmPatchedSrcNix westonAndroidSignalPolyfill
            androidConfigNix westonToytoolkitLdflagsNix westonCompositorLdflagsNix ilandGlAndroidLdflagsNix;
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
          # anowaW C ABI header + libanowaw.so for Gradle/CMake parity builds
          (toolchainsAndroid.buildForAndroid "anowaw" { })
        ] ++ (pkgs.lib.attrValues mobileToytoolkitDepsAndroid)
          ++ [
            (toolchainsAndroid.buildForAndroid "weston" { enableGlClients = true; })
            (toolchainsAndroid.buildForAndroid "weston-compositor" { })
            (toolchainsAndroid.buildForAndroid "libintl" { })
            (toolchainsAndroid.buildForAndroid "iland" { })
            (toolchainsAndroid.buildForAndroid "angle" { })
            (toolchainsAndroid.buildForAndroid "kmscube" { })
            (toolchainsAndroid.buildForAndroid "gbm-es2-demo" { })
            (toolchainsAndroid.buildForAndroid "opengl-cube" { })
            (toolchainsAndroid.buildForAndroid "vkcube" { })
          ];
        studioIlandGlLdflags = import ilandGlAndroidLdflagsNix {
          inherit (pkgs) lib;
          deps = {
            iland = toolchainsAndroid.buildForAndroid "iland" { };
            angle = toolchainsAndroid.buildForAndroid "angle" { };
            kmscube = toolchainsAndroid.buildForAndroid "kmscube" { };
            "iland-gl-clients" = toolchainsAndroid.buildForAndroid "kmscube" { };
            "gbm-es2-demo" = toolchainsAndroid.buildForAndroid "gbm-es2-demo" { };
            "opengl-cube" = toolchainsAndroid.buildForAndroid "opengl-cube" { };
            vkcube = toolchainsAndroid.buildForAndroid "vkcube" { };
          };
        };
        studioWestonToytoolkitLdflags = import westonToytoolkitLdflagsNix {
          inherit (pkgs) lib;
          deps = mobileToytoolkitDepsAndroid // {
            weston = toolchainsAndroid.buildForAndroid "weston" { };
            libintl = toolchainsAndroid.buildForAndroid "libintl" { };
          };
          forceLoadWeston = true;
          linkMode = "whole_archive";
        };
        studioWestonCompositorLdflags = import westonCompositorLdflagsNix {
          inherit (pkgs) lib;
          deps = {
            weston-compositor = toolchainsAndroid.buildForAndroid "weston-compositor" { };
            libwayland = toolchainsAndroid.buildForAndroid "libwayland" { };
            expat = toolchainsAndroid.buildForAndroid "expat" { };
          };
          forceLoadCompositor = false;
          linkMode = "whole_archive";
        };
        studioNixDepIncludes =
          (pkgs.lib.concatMapStringsSep " " (d: "-I${d}/include") studioAndroidDeps)
          + " -I${toolchainsAndroid.buildForAndroid "pixman" { }}/include/pixman-1"
          + " -I${toolchainsAndroid.buildForAndroid "weston" { }}/include/weston-gen";
        studioNixDepLibs =
          (pkgs.lib.concatMapStringsSep " " (d: "-L${d}/lib") studioAndroidDeps)
          + " ${pkgs.lib.concatStringsSep " " (studioWestonToytoolkitLdflags ++ studioWestonCompositorLdflags ++ studioIlandGlLdflags)}";
        studioRuntimeLibDirs =
          pkgs.lib.concatMapStringsSep ":" (d: "${d}/lib") studioAndroidDeps;
        studioRustBackendLib = "${backend-android}/lib/libwawona.a";
        studioRustBackendSharedLib = "${backend-android}/lib/libwawona_core.so";
        studioOpenSSHBin = "${toolchainsAndroid.buildForAndroid "openssh" { }}/bin/ssh";
        studioSshpassBin = "${toolchainsAndroid.buildForAndroid "sshpass" { }}/bin/sshpass";
        studioZshPkg = toolchainsAndroid.buildForAndroid "zsh" { };
        studioZshBin = "${studioZshPkg}/bin/zsh";
        studioZshShare = "${studioZshPkg}/share/zsh";
        studioFastfetchBin = "${toolchainsAndroid.buildForAndroid "fastfetch" { }}/bin/fastfetch";
        studioPhoonBin = "${toolchainsAndroid.buildForAndroid "phoon" { }}/bin/phoon";
        studioNeovimBin = "${toolchainsAndroid.buildForAndroid "neovim" { }}/bin/nvim";
        # waypipe ships a real ELF binary as `waypipe.real` plus a Vulkan-wrapper
        # script named `waypipe`; gradlegen.nix picks whichever exists at build
        # time (same fallback android-shell-tools.nix uses for the release APK).
        studioWaypipePkg = toolchainsAndroid.buildForAndroid "waypipe" { };
        studioWaypipeBin = "${studioWaypipePkg}/bin/waypipe.real";
        studioWaypipeBinFallback = "${studioWaypipePkg}/bin/waypipe";

        gradlegenPkg = pkgs.callPackage ./dependencies/generators/gradlegen.nix {
          wawonaSrc = if isLinuxHost then ./. else src;
          inherit wawonaVersion westonAndroidSignalPolyfill;
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
          zshBinaryPath = studioZshBin;
          zshSharePath = studioZshShare;
          fastfetchBinaryPath = studioFastfetchBin;
          phoonBinaryPath = studioPhoonBin;
          neovimBinaryPath = studioNeovimBin;
          waypipeBinaryPath = studioWaypipeBin;
          waypipeBinaryPathFallback = studioWaypipeBinFallback;
          anowawAndroid = toolchainsAndroid.buildForAndroid "anowaw" {};
        };

        # ── Cross-Platform Packages ───────────────────────────────────────
        commonPackages = rec {
          nom = pkgs.nix-output-monitor;
          local-runner = pkgs.callPackage ./scripts/local-runner.nix { };
          wawona-shell = pkgs.callPackage ./dependencies/clients/wawona-shell { };
          wawona-tools = pkgs.callPackage ./dependencies/clients/wawona-tools { };
          # DejaVu (UI/CSD) + DejaVuSansM Nerd Font Mono (terminals).
          wawona-bundled-fonts = pkgs.callPackage ./dependencies/libs/fonts { };

          # Weston and Waypipe (Native on Linux, Cross-wrapped on Darwin)
          weston = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "weston" {} else pkgs.weston;
          weston-simple-shm =
            if pkgs.stdenv.isDarwin
            then toolchains.buildForMacOS "weston-simple-shm" {}
            else pkgs.callPackage westonSimpleShmLinuxNix {};
          foot = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "foot" {} else pkgs.foot;
          fastfetch = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "fastfetch" { } else pkgs.fastfetch;
          neovim = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "neovim" { } else pkgs.neovim;
          waypipe = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "waypipe" { } else pkgs.waypipe;

          # ANGLE (OpenGL ES over Metal) + iland userland graphics core
          # (GBM/EGL/DRM over IOSurface) for nested GL clients (kmscube, es2gears,
          # weston-simple-egl). macOS-first; mobile cross builds are WIP.
          angle = if pkgs.stdenv.isDarwin then toolchains.buildForMacOS "angle" { } else pkgs.angle;

          # Wawona (Native on Linux, Cross-wrapped on Darwin)
          wawona = if pkgs.stdenv.isDarwin 
            then (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs 
              (pkgs.callPackage ./dependencies/wawona/macos.nix {
                buildModule = toolchains; inherit wawonaSrc wawonaVersion;
                waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
                moltenvk = toolchains.buildForMacOS "moltenvk" { };
                kosmickrisp = toolchains.buildForMacOS "kosmickrisp" { };
                foot = toolchains.buildForMacOS "foot" { };
                niri = toolchains.buildForMacOS "niri" { };
                fuzzel = toolchains.buildForMacOS "fuzzel" { };
                fastfetch = toolchains.buildForMacOS "fastfetch" { };
                # Legacy commonPackages.wawona path (apps use wawona-macos +
                # sharedMacosCargoNix). Keep a self-contained backend here so this
                # attrset does not forward-ref the later packages let-binding.
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
                    pixman = toolchains.buildForMacOS "pixman" { };
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
              coreutilsSrc = coreutils-src;
            };
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          # ANGLE companion: iland userland graphics core (GBM/EGL/DRM over IOSurface).
          iland = toolchains.buildForMacOS "iland" { };
          # GL smoke test (kmscube) over iland+ANGLE. Nested inside Wawona
          # via the Mode A present-redirect. macOS only.
          kmscube = pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; };
          "iland-gl-clients" = pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; };
          "gbm-es2-demo" = toolchains.buildForMacOS "gbm-es2-demo" { };
          # wwn-igetty: Linux-shaped VTs + Doorman (Classic own-display).
          modeb-tty = wwn-igetty.packages.${system}.wwn-igetty;
          wwn-igetty = wwn-igetty.packages.${system}.wwn-igetty;
        };

        packages = commonPackages
          # WLCS conformance runner (ci-l2-wlcs). Linux-only, skeleton
          # integration; runtime battery is a CI lane. Guarded so darwin eval is
          # unaffected.
          // (pkgs.lib.optionalAttrs (isLinuxHost && builtins.pathExists ./dependencies/tests/wlcs.nix) {
            wawona-wlcs-run = pkgs.callPackage ./dependencies/tests/wlcs.nix { };
          })
          // (pkgs.lib.optionalAttrs (isLinuxHost || androidSDK != null) {
          wawona-android = wawonaAndroidPkg;
          wawona-android-backend = backend-android;
          # Exposed so the CI reproducibility gate (repro-rebuild) can --rebuild
          # the filtered-source assembly and byte-compare it across hosts.
          wawona-workspace-src-android = workspace-src-android;
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
          wawona-android-aab = import ./dependencies/wawona/android.nix {
            pkgs = androidPkgs;
            buildModule = toolchainsAndroid;
            inherit (androidPkgs) lib stdenv clang pkg-config unzip zip patchelf file util-linux glslang mesa;
            inherit gradle jdk17 wawonaSrc androidSDK androidUtils;
          srcFiltered = src;
            androidToolchain = toolchainsAndroid.androidToolchain;
            rustBackend = backend-android;
            coreutilsAndroid = coreutils-multicall-android;
            targetPkgs = pkgsAndroidCross;
            waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
            inherit androidToolchainNix westonSimpleShmPatchedSrcNix westonAndroidSignalPolyfill
            androidConfigNix westonToytoolkitLdflagsNix westonCompositorLdflagsNix ilandGlAndroidLdflagsNix;
            releaseArtifact = "release-aab";
          };
          coreutils-multicall-android = coreutils-multicall-android;
          angle-android = toolchainsAndroid.buildForAndroid "angle" { };
          weston-android = toolchainsAndroid.buildForAndroid "weston" { };
          weston-compositor-android = toolchainsAndroid.buildForAndroid "weston-compositor" { };
        }) // (pkgs.lib.optionalAttrs hasAndroidCts {
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
        }) // (pkgs.lib.optionalAttrs isLinuxHost {
          wawona-linux = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          wawona-linux-ui-bin = pkgs.callPackage ./dependencies/wawona/linux-ui-prebuilt.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          # Self-contained, glibc-portable AppImage of the GTK UI. The bundled
          # binary auto-selects the GDK x11/wayland backend at startup based on
          # the host's $WAYLAND_DISPLAY socket, so a single artifact serves both
          # X11 and Wayland hosts. Built reproducibly via the Determinate Linux
          # builder for x86_64 and aarch64.
          # Product-build short name (arch only). Ship: GitHub assets renames to
          # Wawona-{calver}-Linux-{arch}.AppImage in release.yml (aarch64→arm64).
          wawona-appimage = nix-appimage.lib.${system}.mkAppImage {
            program = "${self.packages.${system}.wawona-linux-ui-bin}/bin/wawona-linux-ui";
            name = "Wawona-${pkgs.lib.head (pkgs.lib.splitString "-" system)}.AppImage";
          };
          wawona-linux-compositor-host = pkgs.callPackage ./dependencies/wawona/linux-host.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          wawona-linux-tray = pkgs.callPackage ./dependencies/wawona/linux-tray.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          wawona-linux-vm = pkgs.callPackage ./dependencies/wawona/linux-vm.nix {
            inherit wawonaVersion;
          };
          # p26-vm-nixos: prebuilt NixOS guest (kernel+initrd+rootfs) for the
          # native Virtualization.framework bridge (wawona-vz on the macOS host).
          # Built here on the Linux/NixOS host and copied to the Mac, since VZ
          # direct-kernel boot needs aarch64-linux artifacts. See
          # docs/2026-nixos-vm-bridge.md.
          wawona-nixos-guest = import ./dependencies/wawona/nixos-guest.nix {
            inherit nixpkgs pkgs wawonaVersion;
            system = pkgs.system;
          };
          install = pkgs.writeShellScriptBin "install" ''
            set -euo pipefail
            exec ${pkgs.nix}/bin/nix profile install "${self.outPath}#wawona" "$@"
          '';
          default = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          # Consumer-facing package name for use as a flake input or overlay,
          # matching the nixpkgs convention of installing `pkgs.wawona`.
          wawona = pkgs.callPackage ./dependencies/wawona/linux.nix {
            inherit wawonaVersion;
            waypipeSrc = waypipe-src;
            coreutilsSrc = coreutils-src;
          };
          # Host-native phoon CLI for Linux (`nix run .#phoon`).
          phoon-linux = toolchains.buildForLinux "phoon" { };
          phoon = toolchains.buildForLinux "phoon" { };
          wawona-wasm-linux = toolchains.buildForLinux "wawona-wasm" { };
          wawona-wasm = toolchains.buildForLinux "wawona-wasm" { };
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
          waypipe-patched-watchos = pkgs.callPackage waypipePatchedSrcNix {
            inherit waypipe-src; patchScript = waypipePatchSourceSh; platform = "watchos";
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
          workspace-src-watchos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src; waypipeSrc = waypipe-patched-watchos; coreutilsSrc = coreutils-patched-ios; platform = "watchos"; inherit wawonaVersion;
          };
          mobilePlatformDeps = import ./dependencies/wawona/mobile-platform-deps.nix { lib = pkgs.lib; inherit pkgs; };
          macosToytoolkitDeps = import ./dependencies/wawona/macos-toytoolkit-deps.nix { inherit pkgs; };
          macosDeps = {
            libwayland = toolchains.buildForMacOS "libwayland" { };
            xkbcommon = toolchains.buildForMacOS "xkbcommon" { };
            pixman = toolchains.buildForMacOS "pixman" { };
            "epoll-shim" = toolchains.buildForMacOS "epoll-shim" { };
            waypipe = toolchains.buildForMacOS "waypipe" { };
            sshpass = toolchains.buildForMacOS "sshpass" { };
            # wwn-ssh macOS backend: regular OpenSSH (ssh, ssh-keygen, scp, ...)
            # bundled into Resources/bin for the in-app terminal.
            openssh = toolchains.buildForMacOS "openssh" { };
            iland = toolchains.buildForMacOS "iland" { };
            angle = toolchains.buildForMacOS "angle" { };
            kmscube = pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; };
            "iland-gl-clients" = pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; };
            "gbm-es2-demo" = toolchains.buildForMacOS "gbm-es2-demo" { };
            vkcube = toolchains.buildForMacOS "vkcube" { };
            "opengl-cube" = toolchains.buildForMacOS "opengl-cube" { };
            weston = toolchains.buildForMacOS "weston" { };
            "weston-compositor" = toolchains.buildForMacOS "weston-compositor-drm" { };
            "wawona-wasm" = toolchains.buildForMacOS "wawona-wasm" { };
          } // macosToytoolkitDeps;
          iosDeps = mobilePlatformDeps { buildFn = toolchains.buildForIOS; inherit toolchains; };
          iosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForIOS; inherit toolchains; simulator = true; };
          tvosDeps = mobilePlatformDeps { buildFn = toolchains.buildForTVOS; inherit toolchains; variant = "tv"; };
          tvosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForTVOS; inherit toolchains; variant = "tv"; simulator = true; };
          visionosDeps = mobilePlatformDeps { buildFn = toolchains.buildForVisionOS; inherit toolchains; variant = "vision"; };
          visionosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForVisionOS; inherit toolchains; variant = "vision"; simulator = true; };
          watchosDeps = mobilePlatformDeps { buildFn = toolchains.buildForWatchOS; inherit toolchains; variant = "watch"; };
          watchosSimDeps = mobilePlatformDeps { buildFn = toolchains.buildForWatchOS; inherit toolchains; variant = "watch"; simulator = true; };
          # One generatedCargoNix IFD per distinct workspaceSrc (#68 / runner speedups).
          sharedIosCargoNix = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
            name = "wawona-ios-workspace";
            src = workspace-src-ios;
          };
          sharedMacosCargoNix = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
            name = "wawona-macos-workspace";
            src = workspace-src-macos;
          };
          sharedWatchosCargoNix = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
            name = "wawona-watchos-workspace";
            src = workspace-src-watchos;
          };
          appleHostCrates = pkgs.callPackage ./dependencies/wawona/apple-host-crates.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios;
            nativeDeps = iosDeps;
            cargoNixDrv = sharedIosCargoNix;
          };
          backend-macos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-macos; platform = "macos"; nativeDeps = macosDeps;
            cargoNixDrv = sharedMacosCargoNix;
            desktopHost = true;
          };
          backend-ios = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "ios"; nativeDeps = iosDeps;
            cargoNixDrv = sharedIosCargoNix;
          };
          backend-ios-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "ios"; simulator = true; nativeDeps = iosSimDeps;
            cargoNixDrv = sharedIosCargoNix;
            # Product-sim CI: skip thin LTO / O3 on the Rust backend (Xcode stays Debug).
            release = false;
          };

          backend-tvos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "tvos"; nativeDeps = tvosDeps;
            cargoNixDrv = sharedIosCargoNix;
          };
          backend-tvos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "tvos"; simulator = true; nativeDeps = tvosSimDeps;
            cargoNixDrv = sharedIosCargoNix;
            # Product-sim CI: skip thin LTO / O3 on the Rust backend (Xcode stays Debug).
            release = false;
          };
          backend-visionos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "visionos"; nativeDeps = visionosDeps;
            cargoNixDrv = sharedIosCargoNix;
          };
          backend-visionos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-ios; platform = "visionos"; simulator = true; nativeDeps = visionosSimDeps;
            cargoNixDrv = sharedIosCargoNix;
            # Product-sim CI: skip thin LTO / O3 (Xcode stays Debug).
            release = false;
          };
          backend-watchos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-watchos; platform = "watchos"; nativeDeps = watchosDeps;
            cargoNixDrv = sharedWatchosCargoNix;
          };
          backend-watchos-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs appleHostCrates;
            workspaceSrc = workspace-src-watchos; platform = "watchos"; simulator = true; nativeDeps = watchosSimDeps;
            cargoNixDrv = sharedWatchosCargoNix;
            # Product-sim + iOS-embedded watch companion: skip thin LTO / O3.
            release = false;
          };
          mobileGuestArtifacts =
            if builtins.pathExists "${wwn-vms}/dependencies/vms/mobile/guest-artifacts.nix" then
              wwn-vms.packages.aarch64-linux.wawona-mobile-guest-artifacts or null
            else null;
          mobileVmEngine =
            if pkgs.stdenv.isDarwin && (wwn-vms.packages.${system}.wwn-vms-mobile-engine-ios-tci or null) != null then
              wwn-vms.packages.${system}.wwn-vms-mobile-engine-ios-tci
            else null;
          mkXcodegen = {
            platformFilter ? null,
            simulatorOnly ? false,
            # waypipe-on-watch currently fails openssl-sys (ios vs watch
            # -m*-simulator-version-min clash). Drop it so project.yml can still
            # emit Wawona-watchOS; LDFLAGS already treat waypipe as optional.
            dropWatchWaypipe ? false,
          }:
            let
              want = p: platformFilter == null || builtins.elem p platformFilter;
              # Empty unused platform deps so filterAttrs-forced targets do not
              # realize heavy closures (eval may still walk attrs; builds do not).
              empty = { };
              # Wawona-iOS embeds the watch companion for App Store / TF (#136),
              # so ios-filtered projects must still realize watch deps.
              wantWatch = want "watchos" || want "ios";
              watchDepsForXcodegen =
                if !wantWatch then empty
                else if simulatorOnly then empty
                else if dropWatchWaypipe then (watchosDeps // { waypipe = null; })
                else watchosDeps;
              watchSimDepsForXcodegen =
                if !wantWatch then empty
                else if dropWatchWaypipe then (watchosSimDeps // { waypipe = null; })
                else watchosSimDeps;
            in
            pkgs.callPackage ./dependencies/generators/xcodegen.nix {
              inherit wawonaVersion wawonaSrc platformFilter simulatorOnly mobileGuestArtifacts mobileVmEngine;
              iosDeps = if want "ios" || want "ipados" then (if simulatorOnly then empty else iosDeps) else empty;
              iosSimDeps = if want "ios" || want "ipados" then iosSimDeps else empty;
              ipadosDeps = if want "ipados" then (if simulatorOnly then empty else iosDeps) else empty;
              ipadosSimDeps = if want "ipados" then iosSimDeps else empty;
              tvosDeps = if want "tvos" then (if simulatorOnly then empty else tvosDeps) else empty;
              tvosSimDeps = if want "tvos" then tvosSimDeps else empty;
              visionosDeps = if want "visionos" then (if simulatorOnly then empty else visionosDeps) else empty;
              visionosSimDeps = if want "visionos" then visionosSimDeps else empty;
              watchosDeps = watchDepsForXcodegen;
              watchosSimDeps = watchSimDepsForXcodegen;
              macosDeps = if want "macos" then macosDeps else empty;
              macosBackend = if want "macos" then backend-macos else null;
              iosBackend = if (want "ios" || want "ipados") && !simulatorOnly then backend-ios else null;
              iosSimBackend = if want "ios" || want "ipados" then backend-ios-sim else null;
              ipadosBackend = if want "ipados" && !simulatorOnly then backend-ios else null;
              ipadosSimBackend = if want "ipados" then backend-ios-sim else null;
              tvosBackend = if want "tvos" && !simulatorOnly then backend-tvos else null;
              tvosSimBackend = if want "tvos" then backend-tvos-sim else null;
              visionosBackend = if want "visionos" && !simulatorOnly then backend-visionos else null;
              visionosSimBackend = if want "visionos" then backend-visionos-sim else null;
              watchosBackend = if wantWatch && !simulatorOnly then backend-watchos else null;
              watchosSimBackend = if wantWatch then backend-watchos-sim else null;
              macosWeston = if want "macos" then toolchains.buildForMacOS "weston" { } else null;
              macosFoot = if want "macos" then toolchains.buildForMacOS "foot" { } else null;
              macosFastfetch = if want "macos" then pkgs.fastfetch else null;
              macosPhoon = if want "macos" then toolchains.buildForMacOS "phoon" { } else null;
              macosNeovim = null;
              macosZsh = if want "macos" then pkgs.zsh else null;
              macosKmscube =
                if want "macos" then pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; } else null;
              macosModebTty =
                if want "macos" then wwn-igetty.packages.${system}.wwn-igetty else null;
              macosOpenglCube =
                if want "macos" then toolchains.buildForMacOS "opengl-cube" { } else null;
              macosVkcube =
                if want "macos" then toolchains.buildForMacOS "vkcube" { } else null;
              macosWestonSimpleEgl =
                if want "macos" then toolchains.buildForMacOS "weston-simple-egl" { } else null;
              macosNiri = if want "macos" then toolchains.buildForMacOS "niri" { } else null;
              macosFuzzel = if want "macos" then toolchains.buildForMacOS "fuzzel" { } else null;
            };
          xcodegenOutputs = mkXcodegen { };
          xcodegenIosOutputs = mkXcodegen { platformFilter = [ "ios" "ipados" ]; };
          xcodegenIosSimOutputs = mkXcodegen {
            platformFilter = [ "ios" ];
            simulatorOnly = true;
          };
          xcodegenMacosOutputs = mkXcodegen { platformFilter = [ "macos" ]; };
          xcodegenAppleOutputs = mkXcodegen { platformFilter = [ "ios" "ipados" "macos" ]; };
          # Full Apple matrix minus visionOS. Used when vision deps fail to
          # configure (e.g. lz4 -mvisionos-simulator-version-min clang gap).
          xcodegenNoVisionOutputs = mkXcodegen {
            platformFilter = [ "ios" "ipados" "macos" "tvos" "watchos" ];
            dropWatchWaypipe = true;
          };
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            moltenvk = toolchains.buildForMacOS "moltenvk" { };
            kosmickrisp = toolchains.buildForMacOS "kosmickrisp" { };
            foot = toolchains.buildForMacOS "foot" { };
            niri = toolchains.buildForMacOS "niri" { };
            fuzzel = toolchains.buildForMacOS "fuzzel" { };
            # anowaW app bridge (libanowaw.a + anowaw_mac_shim.o + headers).
            anowaw = toolchains.buildForMacOS "anowaw" { };
            fastfetch = pkgs.fastfetch;
            phoon = toolchains.buildForMacOS "phoon" { };
            wawonaWasm = toolchains.buildForMacOS "wawona-wasm" { };
            neovim = null;
            zsh = pkgs.zsh;
            kmscube = pkgs.callPackage kmscubeMacosNix { buildModule = toolchains; };
            modebTty = wwn-igetty.packages.${system}.wwn-igetty;
            # macOS-only xcodegen project (platformFilter = ["macos"]) so product
            # builds use the same Wawona-macOS scheme as local xcodebuild, without
            # pulling iOS/device backend graphs.
            rustBackend = backend-macos;
            xcodeProject = xcodegenMacosOutputs.project;
            # Mode B dylib enabled for all macOS builds (Wawona macOS is non-App Store).
            ilandBaremetal = toolchains.buildForMacOS "iland-baremetal" { };
            # L3' Watchdog tools (github.com/Wawona/wwn-iowatchdog).
            iowatchdog = wwn-iowatchdog.packages.${system}.wwn-iowatchdog;
          };
          wawona-ios-app-sim = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            # iOS-sim-only project: no macOS/iPadOS/device native fan-out.
            xcodeProject = xcodegenIosSimOutputs.project;
            simulator = true;
            rustBackend = backend-ios-sim;
            companionBackends = { "Wawona-watchOS" = backend-watchos-sim; };
          };
          wawona-watchos-app-sim = pkgs.callPackage ./dependencies/wawona/watchos.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            rustBackend = backend-watchos-sim;
          };
          wawona-watchos-app-device = pkgs.callPackage ./dependencies/wawona/watchos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            rustBackend = backend-watchos;
          };
          wawona-ios-app-device = pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            rustBackend = backend-ios;
            companionBackends = { "Wawona-watchOS" = backend-watchos; };
          };
          wawona-ipados-app-sim = pkgs.callPackage ./dependencies/wawona/ipados.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            rustBackend = backend-ios-sim;
            companionBackends = { "Wawona-watchOS" = backend-watchos-sim; };
          };
          wawona-ipados-app-device = pkgs.callPackage ./dependencies/wawona/ipados.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            rustBackend = backend-ios;
            companionBackends = { "Wawona-watchOS" = backend-watchos; };
          };
          wawona-tvos-app-sim = pkgs.callPackage ./dependencies/wawona/tvos.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            rustBackend = backend-tvos-sim;
          };
          wawona-tvos-app-device = pkgs.callPackage ./dependencies/wawona/tvos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            rustBackend = backend-tvos;
          };
          wawona-visionos-app-sim = pkgs.callPackage ./dependencies/wawona/visionos.nix {
            inherit wawonaSrc wawonaVersion teamId;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = true;
            rustBackend = backend-visionos-sim;
          };
          wawona-visionos-app-device = pkgs.callPackage ./dependencies/wawona/visionos.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            rustBackend = backend-visionos;
          };
          wawona-ios-ipa = if teamId != null then pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            generateIPA = true;
            rustBackend = backend-ios;
            companionBackends = { "Wawona-watchOS" = backend-watchos; };
          } else missingTeamRelease "wawona-ios-ipa";
          wawona-ios-xcarchive = if teamId != null then pkgs.callPackage ./dependencies/wawona/ios.nix {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            generateXCArchive = true;
            rustBackend = backend-ios;
            companionBackends = { "Wawona-watchOS" = backend-watchos; };
          } else missingTeamRelease "wawona-ios-xcarchive";
          mkPlatformIpa = name: file: args: if teamId != null then pkgs.callPackage file (args // {
            inherit wawonaSrc wawonaVersion;
            TEAM_ID = teamId;
            xcodeProject = xcodegenOutputs.project;
            simulator = false;
            generateIPA = true;
          }) else missingTeamRelease name;
          wawona-ipados-ipa = mkPlatformIpa "wawona-ipados-ipa" ./dependencies/wawona/ipados.nix {
            rustBackend = backend-ios;
            companionBackends = { "Wawona-watchOS" = backend-watchos; };
          };
          wawona-tvos-ipa = mkPlatformIpa "wawona-tvos-ipa" ./dependencies/wawona/tvos.nix {
            rustBackend = backend-tvos;
          };
          wawona-visionos-ipa = mkPlatformIpa "wawona-visionos-ipa" ./dependencies/wawona/visionos.nix {
            rustBackend = backend-visionos;
          };
          wawona-watchos-ipa = mkPlatformIpa "wawona-watchos-ipa" ./dependencies/wawona/watchos.nix {
            rustBackend = backend-watchos;
          };
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
            applaunch_label="com.aspauldingcode.wawona.applaunch"
            runtime_dir="/tmp/wawona-$uid"
            exec_path="${wawona-macos}/Applications/Wawona.app/Contents/MacOS/Wawona"
            dylib_path="${wawona-macos}/Applications/Wawona.app/Contents/Library/Wawona/iland/libwayland-mac.dylib"

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

            wait_unloaded() {
              target="$1"
              i=0
              while [ $i -lt 20 ]; do
                if ! launchctl print "$target" >/dev/null 2>&1; then
                  return 0
                fi
                sleep 0.25
                i=$((i + 1))
              done
              return 1
            }

            kill_matching_wawona() {
              # TERM leftover MacOS/Wawona processes so a stale flock lock
              # cannot make the new compositor-host exit as "already running".
              ps -axo pid=,args= | while read -r pid args; do
                case "$args" in
                  *"/Contents/MacOS/Wawona"*)
                    kill -TERM "$pid" >/dev/null 2>&1 || true
                    ;;
                esac
              done
              sleep 0.4
              ps -axo pid=,args= | while read -r pid args; do
                case "$args" in
                  *"/Contents/MacOS/Wawona"*)
                    kill -KILL "$pid" >/dev/null 2>&1 || true
                    ;;
                esac
              done
            }

            ensure_loaded() {
              label="$1"
              plist_path="$launch_agents_dir/$label.plist"
              target="$domain/$label"
              # kickstart on an already-loaded job keeps the old ProgramArguments
              # path. Boot out and wait until launchd actually drops the job.
              launchctl bootout "$target" >/dev/null 2>&1 || true
              launchctl remove "$label" >/dev/null 2>&1 || true
              wait_unloaded "$target" || true
              i=0
              while [ $i -lt 10 ]; do
                # After bootout, launchd often returns EIO (5) for a few
                # hundred ms. Swallow stderr until a retry succeeds.
                if launchctl bootstrap "$domain" "$plist_path" >/dev/null 2>&1; then
                  launchctl kickstart -k "$target" >/dev/null 2>&1 || true
                  return 0
                fi
                sleep 0.5
                i=$((i + 1))
              done
              echo "Error: launchctl bootstrap failed for $target" >&2
              launchctl bootstrap "$domain" "$plist_path"
            }

            verify_running() {
              label="$1"
              target="$domain/$label"
              i=0
              while [ $i -lt 20 ]; do
                prog="$(launchctl print "$target" 2>/dev/null | sed -n 's/^[[:space:]]*program = //p' | head -1)"
                pid="$(launchctl print "$target" 2>/dev/null | awk '/^[[:space:]]*pid = / { print $3; exit }')"
                if [ "$prog" = "$exec_path" ] && [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                  echo "  $label pid=$pid"
                  return 0
                fi
                sleep 0.25
                i=$((i + 1))
              done
              echo "Error: $label is not running this build" >&2
              echo "  want: $exec_path" >&2
              echo "  launchd program: $prog" >&2
              echo "  launchd pid: $pid" >&2
              exit 1
            }

            if [ ! -x "$exec_path" ]; then
              echo "Error: Wawona executable not found at $exec_path" >&2
              exit 1
            fi
            if [ ! -f "$dylib_path" ]; then
              echo "Error: Mode B dylib missing at $dylib_path" >&2
              echo "macOS Desktop Replacement needs libwayland-mac.dylib." >&2
              exit 1
            fi

            helper_path="/Library/Application Support/Wawona/run-modeb.sh"
            # Classic Take Over needs sticky claim-ok (Path B). Default: do not
            # restage privileged helper. Set WAWONA_MODEB_STAGE=1 to force.
            if [ "''${WAWONA_MODEB_STAGE:-0}" = 1 ]; then
              echo "Restaging Desktop Replacement helper (iowatchdog-then-unload)."
              echo "Administrator authorization is required once."
              if ! "$exec_path" --mode-b-stage; then
                echo "Error: failed to restage Desktop Replacement helper for this nix store." >&2
                echo "  $exec_path --mode-b-stage" >&2
                echo "  want helper pointing at ${wawona-macos}" >&2
                exit 1
              fi
              if [ ! -f "$helper_path" ] || ! grep -Fq "${wawona-macos}" "$helper_path" \
                || ! grep -Fq "WWN_MODEB_INSERT=compositor-only" "$helper_path" \
                || ! grep -Fq "WWN_MODEB_LOCK=helper-argv-only" "$helper_path" \
                || ! grep -Fq "WWN_MODEB_WD=iowatchdog-then-unload" "$helper_path"; then
                echo "Error: Desktop Replacement helper does not point at this nix store." >&2
                echo "  helper: $helper_path" >&2
                echo "  want: ${wawona-macos} + WWN_MODEB_WD=iowatchdog-then-unload" >&2
                exit 1
              fi
              echo "Mode B helper restaged (iowatchdog-then-unload): $helper_path"
            else
              echo "Skipping Mode B restage (set WAWONA_MODEB_STAGE=1 to force)."
              echo "  Classic Take Over still needs Path B claim-ok after reboot."
              echo "  Mode B dylib still ships in the app: $dylib_path"
            fi

            # Stop both jobs first so compositor-host cannot respawn the
            # menubar from an old bundle while we rewrite plists.
            # Drop leftover applaunch: it `open -a`s a GC'd store path
            # (2026-08-19 login after panic launched Documents/ahaha 0.2.2).
            launchctl bootout "$domain/$compositor_label" >/dev/null 2>&1 || true
            launchctl bootout "$domain/$menubar_label" >/dev/null 2>&1 || true
            launchctl bootout "$domain/$applaunch_label" >/dev/null 2>&1 || true
            launchctl remove "$applaunch_label" >/dev/null 2>&1 || true
            rm -f "$launch_agents_dir/$applaunch_label.plist"
            wait_unloaded "$domain/$compositor_label" || true
            wait_unloaded "$domain/$menubar_label" || true
            kill_matching_wawona
            rm -f "$runtime_dir/compositor-host.lock" "$runtime_dir/menubar.lock" "$runtime_dir/instance.lock"

            write_agent "$compositor_label" "--compositor-host" "wawona-compositor"
            write_agent "$menubar_label" "--menubar" "wawona-menubar"
            ensure_loaded "$compositor_label"
            ensure_loaded "$menubar_label"
            echo "Wawona launch agents installed and running this build:"
            echo "  $exec_path"
            verify_running "$compositor_label"
            verify_running "$menubar_label"
            echo "Mode B dylib: $dylib_path"
            file "$dylib_path" || true
          '';
          uninstall = let
            privileged = pkgs.writeShellScript "wawona-uninstall-privileged" ''
              set +e
              HELPER="/Library/Application Support/Wawona/run-modeb.sh"
              if [ -x "$HELPER" ]; then
                "$HELPER" --restore-aqua >/dev/null 2>&1
              fi
              /bin/launchctl bootout system/com.aspauldingcode.wawona.modeb >/dev/null 2>&1
              /bin/launchctl bootout system/com.aspauldingcode.wawona.ws-guard >/dev/null 2>&1
              /usr/bin/pkill -u 0 -x niri >/dev/null 2>&1
              /usr/bin/pkill -u 0 -x weston >/dev/null 2>&1
              /usr/bin/pkill -u 0 -x framebufferd >/dev/null 2>&1
              /usr/bin/pkill -u 0 -x inputd >/dev/null 2>&1
              /bin/rm -rf /Applications/Wawona.app
              /bin/rm -rf "/Library/Application Support/Wawona"
              /bin/rm -f /etc/sudoers.d/wawona-modeb
              /bin/rm -f /Library/LaunchDaemons/com.aspauldingcode.wawona.modeb.plist
              /bin/rm -f /Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist
              /bin/rm -f /tmp/libwayland-support/modeb-compositor.pid
              /bin/rm -rf /tmp/libwayland-support/modeb.lock
              /bin/launchctl enable system/com.apple.WindowServer >/dev/null 2>&1
              /bin/launchctl load -w /System/Library/LaunchDaemons/com.apple.WindowServer.plist >/dev/null 2>&1
              if ! /usr/bin/pgrep -x WindowServer >/dev/null 2>&1; then
                /bin/launchctl kickstart -k system/com.apple.WindowServer >/dev/null 2>&1
              fi
              exit 0
            '';
          in pkgs.writeShellScriptBin "uninstall" ''
            set -eu
            uid="$(id -u)"
            domain="gui/$uid"
            launch_agents_dir="$HOME/Library/LaunchAgents"
            compositor_label="com.aspauldingcode.wawona.compositorhost"
            menubar_label="com.aspauldingcode.wawona.menubar"
            applaunch_label="com.aspauldingcode.wawona.applaunch"
            modeb_login_label="com.aspauldingcode.wawona.modeb-login"
            app_path="/Applications/Wawona.app"
            modeb_helper="/Library/Application Support/Wawona/run-modeb.sh"

            unload_agent() {
              label="$1"
              target="$domain/$label"
              plist_path="$launch_agents_dir/$label.plist"
              launchctl bootout "$target" >/dev/null 2>&1 || true
              launchctl remove "$label" >/dev/null 2>&1 || true
              rm -f "$plist_path"
            }

            kill_wawona_app() {
              ps -axo pid=,args= | while read -r pid args; do
                case "$args" in
                  *"/Contents/MacOS/Wawona"*)
                    kill -TERM "$pid" >/dev/null 2>&1 || true
                    ;;
                esac
              done
              sleep 0.3
              ps -axo pid=,args= | while read -r pid args; do
                case "$args" in
                  *"/Contents/MacOS/Wawona"*)
                    kill -KILL "$pid" >/dev/null 2>&1 || true
                    ;;
                esac
              done
            }

            unload_agent "$compositor_label"
            unload_agent "$menubar_label"
            unload_agent "$applaunch_label"
            unload_agent "$modeb_login_label"
            kill_wawona_app

            if [ -x "$modeb_helper" ]; then
              /usr/bin/sudo -n "$modeb_helper" --restore-aqua >/dev/null 2>&1 || true
            fi

            need_admin=0
            if [ -e "$app_path" ]; then
              if /bin/rm -rf "$app_path" 2>/dev/null; then
                echo "Removed $app_path"
              else
                need_admin=1
              fi
            fi
            if [ -e "/Library/Application Support/Wawona" ] || \
               [ -e /etc/sudoers.d/wawona-modeb ] || \
               [ -e /Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist ]; then
              need_admin=1
            fi
            if [ "$need_admin" -eq 1 ]; then
              echo "Requesting administrator privileges to finish uninstall..."
              if ! /usr/bin/osascript -e "do shell script \"${privileged}\" with administrator privileges"; then
                echo "Error: administrator authorization is required to remove a root-owned Wawona.app (pkg or sudo copy) and Mode B files." >&2
                exit 1
              fi
            fi

            if [ -e "$app_path" ]; then
              echo "Error: $app_path is still present." >&2
              exit 1
            fi

            echo "Wawona launch agents removed:"
            echo "  - $compositor_label"
            echo "  - $menubar_label"
            echo "  - $applaunch_label"
            echo "Wawona.app and Mode B install files removed."
          '';
          wawona-macos = wawona-macos;
          # 3rd-party macOS ships Mode B. Same drv as default wawona-macos.
          wawona-macos-desktop-host = wawona-macos;

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
          wawona-visionos-app-device = wawona-visionos-app-device;
          wawona-ios-ipa = wawona-ios-ipa;
          wawona-ipados-ipa = wawona-ipados-ipa;
          wawona-tvos-ipa = wawona-tvos-ipa;
          wawona-visionos-ipa = wawona-visionos-ipa;
          wawona-watchos-ipa = wawona-watchos-ipa;
          wawona-ios-xcarchive = wawona-ios-xcarchive;
          wawona-ios-simulator = wawona-ios-simulator;
          wawona-macos-backend = backend-macos;
          wawona-macos-backend-desktop-host = backend-macos;

          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-ipados-backend = backend-ios;
          wawona-ipados-sim-backend = backend-ios-sim;
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
          xcodegen-ios-sim = xcodegenIosSimOutputs.app;
          xcodegen-macos = xcodegenMacosOutputs.app;
          xcodegen-apple = xcodegenAppleOutputs.app;
          xcodegen-fast = xcodegenAppleOutputs.app;
          xcodegen-novision = xcodegenNoVisionOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = weston-terminal-pkg;
          foot = (import ./dependencies/wawona/shell-wrappers.nix).footWrapper pkgs (toolchains.buildForMacOS "foot" {}) wawona-macos;
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          # anowaW app bridge. MacOS (+ Android) only (platform-targets matrix).
          anowaw-macos = toolchains.buildForMacOS "anowaw" { };
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
          iland-visionos = toolchains.buildForVisionOS "iland" { };
          iland-visionos-sim = toolchains.buildForVisionOS "iland" { simulator = true; };
          kmscube-ios = toolchains.buildForIOS "kmscube" { simulator = true; };
          kmscube-ios-device = toolchains.buildForIOS "kmscube" { simulator = false; };
          fastfetch-ios = toolchains.buildForIOS "fastfetch" { simulator = true; };
          fastfetch-ios-device = toolchains.buildForIOS "fastfetch" { simulator = false; };
          # fastfetch on the whole Apple family (#139). tvOS/watchOS follow the
          # zsh naming (plain = device, -sim = simulator); watchOS drops
          # Metal/VideoToolbox via wwn-fastfetch's per-platform framework list.
          fastfetch-tvos = toolchains.buildForTVOS "fastfetch" { simulator = false; };
          fastfetch-tvos-sim = toolchains.buildForTVOS "fastfetch" { simulator = true; };
          fastfetch-watchos = toolchains.buildForWatchOS "fastfetch" { simulator = false; };
          fastfetch-watchos-sim = toolchains.buildForWatchOS "fastfetch" { simulator = true; };
          fastfetch-macos = toolchains.buildForMacOS "fastfetch" { };
          neovim-ios = toolchains.buildForIOS "neovim" { simulator = true; };
          neovim-ios-device = toolchains.buildForIOS "neovim" { simulator = false; };
          neovim-macos = toolchains.buildForMacOS "neovim" { };
          "neovim-rootfs-ios" = toolchains.buildForIOS "neovim-rootfs" { };
          "neovim-rootfs-ios-sim" = toolchains.buildForIOS "neovim-rootfs" { simulator = true; };
          iland-gl-clients-ios = toolchains.buildForIOS "kmscube" { simulator = true; };
          iland-gl-clients-ios-device = toolchains.buildForIOS "kmscube" { simulator = false; };
          weston-ios-gl = toolchains.buildForIOS "weston" { enableGlClients = true; };
          weston-ios-gl-sim = toolchains.buildForIOS "weston" { simulator = true; enableGlClients = true; };
          "wawona-pty-ios" = toolchains.buildForIOS "wawona-pty" { };
          "wawona-pty-ios-sim" = toolchains.buildForIOS "wawona-pty" { simulator = true; };
          # Platform-matched PTY for Apple family (same ios.nix recipe; SDK from apple-mobile).
          "wawona-pty-tvos" = toolchains.buildForTVOS "wawona-pty" { };
          "wawona-pty-tvos-sim" = toolchains.buildForTVOS "wawona-pty" { simulator = true; };
          "wawona-pty-watchos" = toolchains.buildForWatchOS "wawona-pty" { };
          "wawona-pty-watchos-sim" = toolchains.buildForWatchOS "wawona-pty" { simulator = true; };
          "wawona-pty-visionos" = toolchains.buildForVisionOS "wawona-pty" { };
          "wawona-pty-visionos-sim" = toolchains.buildForVisionOS "wawona-pty" { simulator = true; };
          zsh-ios = toolchains.buildForIOS "zsh" { };
          zsh-ios-sim = toolchains.buildForIOS "zsh" { simulator = true; };
          # Platform-matched zsh for Apple family (ios.nix is apple-mobile-aware).
          zsh-tvos = toolchains.buildForTVOS "zsh" { };
          zsh-tvos-sim = toolchains.buildForTVOS "zsh" { simulator = true; };
          zsh-watchos = toolchains.buildForWatchOS "zsh" { };
          zsh-watchos-sim = toolchains.buildForWatchOS "zsh" { simulator = true; };
          zsh-visionos = toolchains.buildForVisionOS "zsh" { };
          zsh-visionos-sim = toolchains.buildForVisionOS "zsh" { simulator = true; };
          # Apple mobile: never ship OpenSSH / libssh-inprocess.a (libssh2 only).
          libssh2-ios = toolchains.buildForIOS "libssh2" { };
          libssh2-ios-sim = toolchains.buildForIOS "libssh2" { simulator = true; };
          niri-ios = toolchains.buildForIOS "niri" { };
          niri-ios-sim = toolchains.buildForIOS "niri" { simulator = true; };
          fuzzel-ios = toolchains.buildForIOS "fuzzel" { };
          fuzzel-ios-sim = toolchains.buildForIOS "fuzzel" { simulator = true; };
          # foot (Wayland client): privatized in xcode-prebuild.sh so its embedded
          # generated-protocol symbols stay local and never collide with weston /
          # fuzzel. Linked on every Apple-mobile target, hence platform-matched
          # builds (iOS attrs are reused for iPadOS/visionOS, mirroring neovim).
          foot-ios = toolchains.buildForIOS "foot" { };
          foot-ios-sim = toolchains.buildForIOS "foot" { simulator = true; };
          foot-tvos = toolchains.buildForTVOS "foot" { };
          foot-tvos-sim = toolchains.buildForTVOS "foot" { simulator = true; };
          foot-watchos = toolchains.buildForWatchOS "foot" { };
          foot-watchos-sim = toolchains.buildForWatchOS "foot" { simulator = true; };
          # phoon (clean-room Rust moon-phase utility, in-process shell tool).
          # Bundled on EVERY Apple target like foot/niri: rust-overlay stable
          # ships std for the tier-3 tvOS/watchOS/visionOS triples, so phoon
          # builds natively for each (iOS attrs reused for iPadOS/visionOS in
          # prebuild, matching foot). Pure Rust. No GPU/framework deps.
          phoon-ios = toolchains.buildForIOS "phoon" { };
          phoon-ios-sim = toolchains.buildForIOS "phoon" { simulator = true; };
          phoon-ios-device = toolchains.buildForIOS "phoon" { simulator = false; };
          phoon-tvos = toolchains.buildForTVOS "phoon" { };
          phoon-tvos-sim = toolchains.buildForTVOS "phoon" { simulator = true; };
          phoon-watchos = toolchains.buildForWatchOS "phoon" { };
          phoon-watchos-sim = toolchains.buildForWatchOS "phoon" { simulator = true; };
          phoon-visionos = toolchains.buildForVisionOS "phoon" { };
          phoon-visionos-sim = toolchains.buildForVisionOS "phoon" { simulator = true; };
          phoon-macos = toolchains.buildForMacOS "phoon" { };
          # Host-native alias: `nix run .#phoon` on Darwin → macOS CLI.
          # (Linux hosts get the same attr from the isLinuxHost block.)
          phoon = toolchains.buildForMacOS "phoon" { };
          # wwn-wasm: WASI P1/P2 interpreter (Pulley on mobile; Cranelift on macOS).
          # Cited: docs/wwn-repo-dag.md (L3′). Off on watchOS (size).
          wawona-wasm-ios = toolchains.buildForIOS "wawona-wasm" { };
          wawona-wasm-ios-sim = toolchains.buildForIOS "wawona-wasm" { simulator = true; };
          wawona-wasm-tvos = toolchains.buildForTVOS "wawona-wasm" { };
          wawona-wasm-tvos-sim = toolchains.buildForTVOS "wawona-wasm" { simulator = true; };
          wawona-wasm-visionos = toolchains.buildForVisionOS "wawona-wasm" { };
          wawona-wasm-visionos-sim = toolchains.buildForVisionOS "wawona-wasm" { simulator = true; };
          wawona-wasm-macos = toolchains.buildForMacOS "wawona-wasm" { };
          wawona-wasm = toolchains.buildForMacOS "wawona-wasm" { };
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
          pixman-android = toolchainsAndroid.buildForAndroid "pixman" { };
          glib-android = toolchainsAndroid.buildForAndroid "glib" { };
          harfbuzz-android = toolchainsAndroid.buildForAndroid "harfbuzz" { };
          cairo-android = toolchainsAndroid.buildForAndroid "cairo" { };
          pango-android = toolchainsAndroid.buildForAndroid "pango" { };
          libpng-android = toolchainsAndroid.buildForAndroid "libpng" { };
          weston-android = toolchainsAndroid.buildForAndroid "weston" { };
          weston-compositor-android = toolchainsAndroid.buildForAndroid "weston-compositor" { };
          weston-compositor-android-drm = toolchainsAndroid.buildForAndroid "weston-compositor-drm" { };
          iland-android = toolchainsAndroid.buildForAndroid "iland" { };
          zsh-android = toolchainsAndroid.buildForAndroid "zsh" { };
          foot-android = toolchainsAndroid.buildForAndroid "foot" { };
          fastfetch-android = toolchainsAndroid.buildForAndroid "fastfetch" { };
          phoon-android = toolchainsAndroid.buildForAndroid "phoon" { };
          wawona-wasm-android = toolchainsAndroid.buildForAndroid "wawona-wasm" { };
          neovim-android = toolchainsAndroid.buildForAndroid "neovim" { };
          waypipe-android = toolchainsAndroid.buildForAndroid "waypipe" { };
          # anowaW app bridge: native lib (libanowaw.so) linked into the Android
          # app; the Kotlin/JNI shims are staged into the generated project.
          anowaw-android = toolchainsAndroid.buildForAndroid "anowaw" { };
          # niri (wwn-niri): nested scrollable-tiling compositor; ships
          # bin/niri + lib/libniri_bin.so (jniLibs exec pattern).
          niri-android = toolchainsAndroid.buildForAndroid "niri" { };
          fuzzel-android = toolchainsAndroid.buildForAndroid "fuzzel" { };
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
        }) // (pkgs.lib.optionalAttrs (builtins.pathExists "${wwn-vms}/dependencies/vms/vz-launcher.nix") {
          # p26-vm-nixos: native Virtualization.framework launcher (vsock+waypipe
          # Wayland bridge). Pure build (compiles the Swift launcher on first run
          # via host xcrun, like the other wawona-* Apple wrappers). This is the
          # *in-app* track (embeddable in Wawona.app, no external hypervisor).
          # Sourced from the wwn-vms dependency (relocated out of Wawona).
          wawona-vz = pkgs.callPackage "${wwn-vms}/dependencies/vms/vz-launcher.nix" { inherit wawonaVersion; };
        }) // (pkgs.lib.optionalAttrs (builtins.pathExists "${wwn-vms}/dependencies/vms/microvm-guest.nix") (
          # p26-vm-nixos: microvm.nix + vfkit *developer* track. `wawona-microvm`
          # builds+boots the NixOS guest under Virtualization.framework;
          # `wawona-vm-bridge` relays its vsock Wayland session into Wawona.
          # The guest definition lives in the wwn-vms dependency.
          let
            microvmGuest = import "${wwn-vms}/dependencies/vms/microvm-guest.nix" {
              inherit nixpkgs;
              microvm = inputs.microvm;
              hostSystem = system;
            };
            vfkitRunner = microvmGuest.config.microvm.runner.vfkit;
          in {
            wawona-microvm = pkgs.writeShellApplication {
              name = "wawona-microvm";
              runtimeInputs = [ pkgs.coreutils pkgs.python3 ];
              text = ''
                # vfkit creates the overlay disk + restful socket in CWD; anchor
                # them in a stable per-user state dir. The guest vsock lands on the
                # host-side unix socket (vsockSocketPath in microvm-guest.nix),
                # which the bridge listens on. Default /tmp/wawona-guest-vsock.sock.
                STATEDIR="''${XDG_STATE_HOME:-$HOME/.local/state}/wawona-microvm"
                mkdir -p "$STATEDIR"
                cd "$STATEDIR"
                echo "[wawona-microvm] state dir: $STATEDIR" >&2
                echo "[wawona-microvm] guest vsock -> host unix socket: /tmp/wawona-guest-vsock.sock (the bridge listens here)" >&2
                # microvm.nix's vfkit runner attaches the guest console via
                # `--device virtio-serial,stdio`, which fails with "operation not
                # supported on socket" whenever stdio is not a real TTY. Exactly
                # the case when Wawona launches this via NSTask (no controlling
                # terminal). Allocate a pty with Python's pty.spawn (works even
                # with no parent TTY) so the stdio console has a terminal.
                exec python3 -c 'import pty,sys; sys.exit(pty.spawn(sys.argv[1:]) or 0)' \
                  ${vfkitRunner}/bin/microvm-run "$@"
              '';
            };
            wawona-vm-bridge = pkgs.writeShellApplication {
              name = "wawona-vm-bridge";
              runtimeInputs = [ pkgs.coreutils pkgs.socat commonPackages.waypipe ];
              text = ''
                # Relay the guest's vsock Wayland stream into Wawona. vfkit runs in
                # default "listen" mode (guest->host): when the guest waypipe server
                # connects to host CID 2:1024, vfkit connects to the host-side unix
                # socket, which THIS bridge must be LISTENING on. So:
                #   guest waypipe server --vsock -s 1024  ->  vfkit  ->
                #   socat UNIX-LISTEN:<vsock sock>  ->  waypipe client  ->  wayland-0
                # Must match microvm-guest.nix `vsockSocketPath`.
                VSOCK_SOCKET="''${WAWONA_VSOCK_SOCKET:-/tmp/wawona-guest-vsock.sock}"
                # Wawona's XDG_RUNTIME_DIR (where it advertises wayland-0). Override
                # via WAWONA_RUNTIME if Wawona uses a different dir.
                WAWONA_RUNTIME="''${WAWONA_RUNTIME:-/tmp/wawona-$(id -u)}"
                WAYPIPE_SOCKET="''${WAYPIPE_SOCKET:-/tmp/waypipe-wawona.sock}"

                if [ ! -d "$WAWONA_RUNTIME" ]; then
                  echo "wawona-vm-bridge: runtime dir $WAWONA_RUNTIME not found. Is Wawona running?" >&2
                  echo "  set WAWONA_RUNTIME=/path/to/wawona/xdg-runtime and retry." >&2
                  exit 1
                fi

                rm -f "$WAYPIPE_SOCKET" "$VSOCK_SOCKET"
                export XDG_RUNTIME_DIR="$WAWONA_RUNTIME"
                export WAYLAND_DISPLAY="wayland-0"
                echo "[wawona-vm-bridge] starting waypipe client on $WAYPIPE_SOCKET (-> $WAWONA_RUNTIME/wayland-0)" >&2
                waypipe --socket "$WAYPIPE_SOCKET" client &
                WAYPIPE_PID=$!
                trap 'kill "$WAYPIPE_PID" 2>/dev/null || true' EXIT

                # Wait for waypipe's client socket to come up, then listen on the
                # vfkit-facing socket. vfkit connects here when the guest dials out;
                # ,fork lets the guest session reconnect (waypipe/systemd restarts).
                for _ in $(seq 1 30); do
                  [ -S "$WAYPIPE_SOCKET" ] && break
                  sleep 1
                done
                echo "[wawona-vm-bridge] listening on $VSOCK_SOCKET, forwarding to $WAYPIPE_SOCKET" >&2
                exec socat "UNIX-LISTEN:$VSOCK_SOCKET,fork" "UNIX-CONNECT:$WAYPIPE_SOCKET"
              '';
            };
          }
        ))));
      in packages;

    getAppsForSystem = system: pkgs: systemPackages:
      let
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import applePath { inherit (pkgs) lib pkgs; nixXcodeenvtests = inputs."nix-xcodeenvtests"; };
        };
        hasAndroidCts = builtins.pathExists ./dependencies/libs/vulkan-cts/android.nix
          && builtins.pathExists ./dependencies/libs/vulkan-cts/gl-cts-android.nix;
      in {
        nom = { type = "app"; program = "${pkgs.nix-output-monitor}/bin/nom"; };
        local-runner = { type = "app"; program = "${systemPackages.local-runner}/bin/local-runner"; };
      } // (pkgs.lib.optionalAttrs (systemPackages ? wawona-android) {
        # Android apps are host-cross packages; only expose when the package set
        # actually provides them (avoids flake check forcing angle-android on
        # unsupported hostPlatform meta).
        wawona-android-provision = { type = "app"; program = "${systemPackages.wawona-android-provision}/bin/provision-android"; };
        wawona-android-project = { type = "app"; program = "${systemPackages.gradlegen}/bin/gradlegen"; };
        wawona-android = { type = "app"; program = "${systemPackages.wawona-android}/bin/wawona-android-run"; };
      }) // (pkgs.lib.optionalAttrs (hasAndroidCts && systemPackages ? vulkan-cts-android) {
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
      }) // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (
        # Parenthesize the // chain: function application binds tighter than //,
        # so without parens graphics-validate leaked onto linux flake check.
        {
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
        wawona-macos = { type = "app"; program = "${systemPackages.wawona}/bin/wawona"; };
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
        xcodegen-novision = { type = "app"; program = "${systemPackages.xcodegen-novision}/bin/xcodegen"; };
        wawona-ios-provision = { type = "app"; program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode"; };
      } // (pkgs.lib.optionalAttrs (systemPackages ? graphics-validate-macos) {
        graphics-validate-macos = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-macos"; };
        # Fast graphics driver-sanity smoke, runnable as `nix run .#graphics-smoke`.
        graphics-smoke = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-macos"; };
      }) // (pkgs.lib.optionalAttrs (systemPackages ? wawona-vz) {
        # p26-vm-nixos: `nix run .#wawona-vz -- --kernel ... --initrd ... --disk ...`
        wawona-vz = { type = "app"; program = "${systemPackages.wawona-vz}/bin/wawona-vz-run"; };
      }) // (pkgs.lib.optionalAttrs (systemPackages ? wawona-microvm) {
        # p26-vm-nixos (developer track): boot the NixOS guest under vfkit
        # (Virtualization.framework), then bridge its Wayland session into Wawona.
        #   term 1:  nix run .#wawona-microvm
        #   term 2:  nix run .#wawona-vm-bridge
        wawona-microvm = { type = "app"; program = "${systemPackages.wawona-microvm}/bin/wawona-microvm"; };
        wawona-vm-bridge = { type = "app"; program = "${systemPackages.wawona-vm-bridge}/bin/wawona-vm-bridge"; };
      })));

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system (pkgsFor system));
    # p26-vm-nixos: the NixOS guest as a first-class flake output, so it can be
    # built on a linux-builder / NixOS host and inspected. The vfkit runner
    # (config.microvm.runner.vfkit) is what `.#wawona-microvm` execs on the Mac.
    wawonaMicrovm = import "${wwn-vms}/dependencies/vms/microvm-guest.nix" {
      inherit nixpkgs;
      microvm = inputs.microvm;
    };
  in {
    wwnSdkConfigPath = androidConfigNix;
    packages = allSystemPackages;
    nixosConfigurations.wawona-microvm = wawonaMicrovm;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system (pkgsFor system) allSystemPackages.${system});
    overlays.default = final: prev: {
      wawona = self.packages.${prev.stdenv.hostPlatform.system}.wawona;
    };
    devShells = nixpkgs.lib.genAttrs systemsList (system:
      (import ./dependencies/wawona/devshells.nix {
        systems = [ system ];
        pkgsFor = pkgsFor;
      }).${system}
      // {
        # Legacy alias; prefer `nix develop` default from devshells.nix.
        wawona = (import ./dependencies/wawona/devshells.nix {
          systems = [ system ];
          pkgsFor = pkgsFor;
        }).${system}.default;
      }
    );
    checks = nixpkgs.lib.genAttrs systemsList (system: let pkgs = pkgsFor system; in pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin ({
      graphics-driver-policy = pkgs.runCommand "graphics-driver-policy" { } ''
        ${pkgs.clang}/bin/clang -U__APPLE__ -DTARGET_OS_IPHONE=0 \
          -I${./src/platform/macos} \
          ${./src/platform/macos/WWNSettings.c} \
          ${./dependencies/tests/graphics-driver-policy.c} \
          -o graphics-driver-policy
        ./graphics-driver-policy
        touch $out
      '';
    } // (pkgs.lib.optionalAttrs (builtins.pathExists ./dependencies/tests/graphics-validate.nix) {
        # Fast graphics driver-sanity gate (ci-graphics-cts). Runs the validator
        # produced by graphics-validate.nix; passes in the sandbox even without a
        # bundled ICD (software/SHM path) so it is a stable PR gate.
        graphics-validate-smoke = pkgs.runCommand "graphics-validate-smoke" { } ''
          ${allSystemPackages.${system}.graphics-validate-macos}/bin/graphics-validate-macos
          touch $out
        '';
      }))
    );
  };
}
