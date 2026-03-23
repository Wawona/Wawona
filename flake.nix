{
  description = "Wawona Compositor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    hiahkernel.url = "github:aspauldingcode/HIAHKernel";

    crate2nix.url = "github:nix-community/crate2nix";
  };

  outputs = { self, nixpkgs, rust-overlay, hiahkernel, crate2nix }:
  let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    pkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [
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
        ];

        config = {
          allowUnfree = true;
          allowUnsupportedSystem = true;
        };
      };

    srcFor = pkgs:
      pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let 
            name = builtins.baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./.) (toString path);
            ext = pkgs.lib.last (pkgs.lib.splitString "." name);
          in 
            # Exclude obvious non-build directories
            !(name == ".git" || name == "result" || name == ".direnv" || name == "target" || 
              name == ".gemini" || name == "Inspiration" || name == ".idea" || name == ".vscode" ||
              name == ".DS_Store") &&
            # Include only what Cargo actually needs:
            #   - Cargo.toml, Cargo.lock, VERSION, build.rs (top-level build files)
            #   - src/          (Rust source code)
            #   - protocols/    (Wayland protocol XML for wayland-scanner)
            #   - scripts/      (build helper scripts referenced by build.rs)
            #   - include/      (C headers if any)
            # EXCLUDED: dependencies/ (Nix modules, .nix/.sh — injected separately by Nix)
            (
              name == "Cargo.toml" || name == "Cargo.lock" || name == "VERSION" || name == "build.rs" ||
              pkgs.lib.hasPrefix "/src" relPath ||
              pkgs.lib.hasPrefix "src" relPath ||
              pkgs.lib.hasPrefix "/protocols" relPath ||
              pkgs.lib.hasPrefix "/scripts" relPath ||
              pkgs.lib.hasPrefix "/include" relPath
            );
      };

    shellWrappers = import ./dependencies/wawona/shell-wrappers.nix;


    # Calculate wawonaVersion once at the top level
    # Use a default system to get lib and src for version calculation
    defaultSystem = "x86_64-linux";
    defaultPkgs = pkgsFor defaultSystem;
    globalSrc = srcFor defaultPkgs;
    wawonaVersion = defaultPkgs.lib.removeSuffix "\n" (defaultPkgs.lib.fileContents (globalSrc + "/VERSION"));

    # Centralized waypipe source
    waypipe-src = defaultPkgs.fetchFromGitLab {
      owner = "mstoeckl";
      repo = "waypipe";
      rev = "v0.11.0";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };

  in
  let
    allPackages = builtins.listToAttrs (map (system:
      let
        pkgs = pkgsFor system;
        cleanPkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            allowUnsupportedSystem = true;
          };
          overlays = [
            (self: super: {
              # Fix linuxHeaders build on macOS (expects gcc, but macOS has cc/clang)
              linuxHeaders = super.linuxHeaders.overrideAttrs (old: {
                makeFlags = (old.makeFlags or []) ++ [ "HOSTCC=cc" ];
              });

              # Fix Android-specific bionic headers on macOS (also expects gcc)
              # bionic-prebuilt dynamically calls makeLinuxHeaders, so we must intercept the function
              makeLinuxHeaders = args: (super.makeLinuxHeaders args).overrideAttrs (old: {
                preConfigure = (old.preConfigure or "") + ''
                  mkdir -p $TMPDIR/gcc-shim
                  ln -s $(command -v cc) $TMPDIR/gcc-shim/gcc
                  ln -s $(command -v c++) $TMPDIR/gcc-shim/g++
                  export PATH=$TMPDIR/gcc-shim:$PATH
                '';
              });

              # Fix LLVM 21's compiler-rt not compiling on Android due to missing pthread.h
              llvmPackages_21 = if super.stdenv.targetPlatform.isAndroid then super.llvmPackages_21 // {
                compiler-rt = super.llvmPackages_21.compiler-rt.overrideAttrs (old: {
                  postPatch = (old.postPatch or "") + ''
                    sed -i 's|#include <pthread.h>|typedef int pthread_once_t; int pthread_once(pthread_once_t *, void (*)(void));|' lib/builtins/os_version_check.c || true
                  '';
                });
              } else super.llvmPackages_21;
            })
          ];
        };
        pkgsAndroid = androidHostPkgs;
        pkgsIos = cleanPkgs.pkgsCross.iphone64;
        src  = srcFor pkgs;

        # Wawona system module (macOS/iOS/Android)
        wawonaSrc = ./.;

        # Toolchains for cross-compilation
        toolchains = import ./dependencies/toolchains {
          inherit (pkgs) lib pkgs stdenv buildPackages;
          inherit wawonaSrc pkgsAndroid pkgsIos;
        };
        
        androidHostPkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidSDK = androidHostPkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0";
          buildToolsVersions = [ "36.0.0" ];
          platformToolsVersion = "35.0.2";
          platformVersions = [ "36" ];
          abiVersions = [ "arm64-v8a" ];
          systemImageTypes = [ "google_apis_playstore" ];
          includeEmulator = true;
          emulatorVersion = "35.1.4";
          includeSystemImages = true;
          useGoogleAPIs = false;
          includeNDK = true;
          ndkVersions = ["27.0.12077973"];
        };

        androidUtils = import ./dependencies/utils/android-wrapper.nix { inherit (pkgs) lib; inherit pkgs androidSDK; };

        # Android needs full src/ including platform C files; use cleanSource for that
        androidSrc = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let name = builtins.baseNameOf path;
            in !(name == ".git" || name == "result" || name == ".direnv" || name == "target" ||
                 name == ".gemini" || name == "Inspiration" || name == ".idea" || name == ".vscode" ||
                 name == ".DS_Store");
        };

        # Vulkan CTS (Conformance Test Suite)
        vulkan-cts-android = pkgs.callPackage ./dependencies/libs/vulkan-cts/android.nix {
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
        };

        gl-cts-android = pkgs.callPackage ./dependencies/libs/vulkan-cts/gl-cts-android.nix {
          lib = pkgs.lib;
          buildPackages = pkgs.buildPackages;
        };

        # ── Pre-patched waypipe source derivations ──
        waypipe-patched-android = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
          inherit waypipe-src;
          patchScript = ./dependencies/libs/waypipe/patch-waypipe-android.sh;
          platform = "android";
        };

        workspace-src-android = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src;
          waypipeSrc = waypipe-patched-android;
          platform = "android";
          inherit wawonaVersion;
        };

        backend-android = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
          inherit crate2nix wawonaVersion toolchains nixpkgs;
          workspaceSrc = workspace-src-android;
          platform = "android";
          nativeDeps = {
            xkbcommon = toolchains.buildForAndroid "xkbcommon" {};
            libwayland = toolchains.buildForAndroid "libwayland" {};
            zstd = toolchains.buildForAndroid "zstd" {};
            lz4 = toolchains.buildForAndroid "lz4" {};
            pixman = toolchains.buildForAndroid "pixman" {};
            openssl = toolchains.buildForAndroid "openssl" {};
            libffi = toolchains.buildForAndroid "libffi" {};
            expat = toolchains.buildForAndroid "expat" {};
            libxml2 = toolchains.buildForAndroid "libxml2" {};
          };
        };

        wawona-android = pkgs.callPackage ./dependencies/wawona/android.nix {
          buildModule = toolchains;
          inherit wawonaSrc wawonaVersion androidSDK androidUtils;
          targetPkgs = pkgsAndroid;
          waypipe = toolchains.buildForAndroid "waypipe" { };
          rustBackend = backend-android;
        };

        # Define the main package based on platform
        mainPackage = if pkgs.stdenv.isDarwin then null else pkgs.hello;

        gradlegen = (pkgs.callPackage ./dependencies/generators/gradlegen.nix {
          wawonaSrc = src;
          wawonaAndroidProject = wawona-android.project;
        }).generateScript;

        packagesForSystem = {
          nom = pkgs.nix-output-monitor;
          default = mainPackage;
          wawona = mainPackage;
          wawona-android = wawona-android;
          wawona-android-backend = backend-android;
          gradlegen = gradlegen;
          wawona-android-project = gradlegen;
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
        } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          # ── Pre-patched waypipe source derivations (cached separately) ──
          # Changing the patch script only invalidates these + their dependents,
          # NOT the entire Rust build.
          waypipe-patched-ios = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src;
            patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh;
            platform = "ios";
          };

          waypipe-patched-macos = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src;
            patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh;
            platform = "macos";
          };



          # ── Workspace source assembly (wawona src + waypipe) ──
          # iOS device and simulator share the same workspace source (same waypipe patches).
          workspace-src-ios = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src;
            waypipeSrc = waypipe-patched-ios;
            platform = "ios";
            inherit wawonaVersion;
          };

          workspace-src-macos = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
            wawonaSrc = src;
            waypipeSrc = waypipe-patched-macos;
            platform = "macos";
            inherit wawonaVersion;
          };



          macosDeps = {
            libwayland = toolchains.buildForMacOS "libwayland" { };
            xkbcommon = toolchains.buildForMacOS "xkbcommon" { };
            waypipe = toolchains.buildForMacOS "waypipe" { };
            sshpass = toolchains.buildForMacOS "sshpass" { };
          };

          # ── crate2nix Rust backends (per-crate caching!) ──
          backend-macos = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-macos;
            platform = "macos";
            nativeDeps = macosDeps;
          };

          iosDeps = {
            xkbcommon = toolchains.buildForIOS "xkbcommon" {};
            libffi = toolchains.buildForIOS "libffi" {};
            libwayland = toolchains.buildForIOS "libwayland" {};
            zstd = toolchains.buildForIOS "zstd" {};
            lz4 = toolchains.buildForIOS "lz4" {};
            zlib = toolchains.buildForIOS "zlib" {};
            libssh2 = toolchains.buildForIOS "libssh2" {};
            mbedtls = toolchains.buildForIOS "mbedtls" {};
            openssl = toolchains.buildForIOS "openssl" {};
            ffmpeg = toolchains.buildForIOS "ffmpeg" {};
            epoll-shim = toolchains.buildForIOS "epoll-shim" {};
            waypipe = toolchains.buildForIOS "waypipe" {};
            weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" {};
            weston = toolchains.buildForIOS "weston" {};
            pixman = toolchains.buildForIOS "pixman" {};
            sshpass = toolchains.buildForIOS "sshpass" {};
          };

          backend-ios = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios;
            platform = "ios";
            nativeDeps = iosDeps;
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
            weston-simple-shm = toolchains.buildForIOS "weston-simple-shm" { simulator = true; };
            weston = toolchains.buildForIOS "weston" { simulator = true; };
            pixman = toolchains.buildForIOS "pixman" { simulator = true; };
            sshpass = toolchains.buildForIOS "sshpass" { simulator = true; };
          };

          backend-ios-sim = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
            inherit crate2nix wawonaVersion toolchains nixpkgs;
            workspaceSrc = workspace-src-ios;
            platform = "ios";
            simulator = true;
            nativeDeps = iosSimDeps;
          };



          libwayland-macos = toolchains.buildForMacOS "libwayland" { };
          libwayland-android = toolchains.buildForAndroid "libwayland" { };
          libwayland-ios = toolchains.buildForIOS "libwayland" { };

          waypipe-macos = toolchains.buildForMacOS "waypipe" { };
          waypipe-android = toolchains.buildForAndroid "waypipe" { };
          waypipe-ios = toolchains.buildForIOS "waypipe" { };

          weston = pkgs.callPackage ./dependencies/clients/weston/macos.nix {
            wayland = libwayland-macos;
            wayland-scanner = libwayland-macos;
          };

          # Central app builds and generators
          # App Store bundles
          wawona-ios = pkgs.callPackage ./dependencies/wawona/ios.nix {
            buildModule = toolchains;
            inherit wawonaSrc wawonaVersion;
            targetPkgs = pkgsIos;
            weston = toolchains.buildForIOS "weston" { simulator = true; };
            rustBackend = backend-ios;
            rustBackendSim = backend-ios-sim;
            xcodeProject = xcodegenProject;
          };



          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains;
            inherit wawonaSrc wawonaVersion;
            waypipe = waypipe-macos;
            weston = weston;
            rustBackend = backend-macos;
            xcodeProject = xcodegenProject;
          };

          # Keyboard test client wrapper
          keyboard-test-client-macos = pkgs.writeShellScriptBin "keyboard-test-client" ''
            export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
            export WAYLAND_DISPLAY="wayland-0"
            echo "[CLIENT] Connecting to $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
            exec ${backend-macos}/bin/keyboard-test-client "$@"
          '';

          # Generic keyboard test client (wrapper handles env vars)
          keyboardTestClient = keyboard-test-client-macos; 

          # Vulkan CTS (Conformance Test Suite)
          vulkanCtsMacOS = pkgs.callPackage ./dependencies/libs/vulkan-cts/macos.nix {
            lib = pkgs.lib;
          };
          vulkanCtsIOS = pkgs.callPackage ./dependencies/libs/vulkan-cts/ios.nix {
            lib = pkgs.lib;
            buildPackages = pkgs.buildPackages;
            buildModule = toolchains;
          };
          glCtsMacOS = pkgs.callPackage ./dependencies/libs/vulkan-cts/gl-cts-macos.nix {
            lib = pkgs.lib;
          };
          graphicsSmokeMacOS = pkgs.writeShellScriptBin "graphics-smoke" ''
            export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
            export WAYLAND_DISPLAY="wayland-0"
            exec ${backend-macos}/bin/graphics-smoke "$@"
          '';
          graphics-validate = pkgs.callPackage ./dependencies/tests/graphics-validate.nix {
            vulkanCts = vulkanCtsMacOS;
            glCts = glCtsMacOS;
            vulkanCtsAndroid = vulkan-cts-android;
            glCtsAndroid = gl-cts-android;
            vulkanCtsIos = vulkanCtsIOS;
            graphicsSmoke = graphicsSmokeMacOS;
          };
          # ── Xcode Project Generation ──
          xcodegenOutputs = pkgs.callPackage ./dependencies/generators/xcodegen.nix {
             inherit wawonaVersion wawonaSrc;
             buildModule = toolchains;
             targetPkgs = pkgs; # For full project, use host pkgs (macOS)
             rustPlatform = pkgs.rustPlatform;
             inherit iosDeps iosSimDeps macosDeps;
             macosWeston = weston;
          };
          xcodegen = xcodegenOutputs.app;
          xcodegenProject = xcodegenOutputs.project;

        in {
          wawona-ios-provision = (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).provisionXcodeScript;
          wawona-macos = wawona-macos;
          wawona-macos-backend = backend-macos;

          wawona-macos-xcode-env = pkgs.buildEnv {
            name = "wawona-macos-xcode-env";
            paths = [ backend-macos ] ++ builtins.attrValues macosDeps;
          };
          
          # Clients
          keyboard-test-client = keyboardTestClient;
          
          default = shellWrappers.macosWrapper pkgs wawona-macos;
          wawona = shellWrappers.macosWrapper pkgs wawona-macos;
          wawona-ios = wawona-ios;
          wawona-ios-backend = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-xcode-env = pkgs.buildEnv {
            name = "wawona-ios-xcode-env";
            paths = [ backend-ios ] ++ builtins.attrValues iosDeps;
          };
          wawona-ios-sim-xcode-env = pkgs.buildEnv {
            name = "wawona-ios-sim-xcode-env";
            paths = [ backend-ios-sim ] ++ builtins.attrValues iosSimDeps;
          };

          # Full Xcode project with both iOS + macOS targets
          xcodegen = xcodegen;
          wawona-ios-project = xcodegen;
          xcodegenProject = xcodegenProject;
          # iOS-only Xcode project (disabled: pkgsCross.iphone64 triggers infinite recursion in nixpkgs)
          # xcodegen-ios = (pkgs.callPackage ./dependencies/generators/xcodegen.nix {
          #   inherit wawonaVersion wawonaSrc;
          #   buildModule = toolchains;
          #   targetPkgs = pkgsIos;
          #   ...
          # }).app;
          waypipe = shellWrappers.waypipeWrapper pkgs (toolchains.buildForMacOS "waypipe" { });
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          foot = shellWrappers.footWrapper pkgs (toolchains.buildForMacOS "foot" { });
          weston = shellWrappers.westonAppWrapper pkgs weston "weston";
          weston-terminal = shellWrappers.westonAppWrapper pkgs weston "weston-terminal";
          weston-debug = shellWrappers.westonAppWrapper pkgs weston "weston-debug";
          weston-simple-shm = shellWrappers.westonAppWrapper pkgs weston "weston-simple-shm";

          # Graphics smoke (Vulkan driver probe)
          graphics-smoke = graphicsSmokeMacOS;

          # Vulkan CTS for macOS (uses KosmicKrisp Vulkan driver)
          vulkan-cts = vulkanCtsMacOS;

          # Vulkan CTS for iOS
          vulkan-cts-ios = vulkanCtsIOS;

          # GL CTS for macOS
          gl-cts = glCtsMacOS;

          # Graphics validation orchestrator (runs Vulkan + GL CTS with manifests)
          graphics-validate = graphics-validate;
        }));


      in
      {
        name = system;
        value = packagesForSystem;
      }) systems);

  in {
    packages = allPackages;

    apps = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      systemPackages = allPackages.${system};
      appPrograms = import ./dependencies/wawona/app-programs.nix {
        inherit pkgs systemPackages;
        xcodeUtils = import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; };
      };
      cleanPkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      
      androidHostPkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      androidSDK = androidHostPkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "8.0";
        buildToolsVersions = [ "36.0.0" ];
        platformToolsVersion = "35.0.2";
        platformVersions = [ "36" ];
        abiVersions = [ "arm64-v8a" ];
        systemImageTypes = [ "google_apis_playstore" ];
        includeEmulator = true;
        emulatorVersion = "35.1.4";
        includeSystemImages = true;
        useGoogleAPIs = false;
        includeNDK = true;
        ndkVersions = ["27.0.12077973"];
      };

      androidUtils = import ./dependencies/utils/android-wrapper.nix { inherit (pkgs) lib; inherit pkgs androidSDK; };
      
      src = srcFor pkgs;
      wv = wawonaVersion; # Use centralization
      

    in {
      name = system;
      value = {
      } // {
        nom = {
          type = "app";
          program = "${systemPackages.nom}/bin/nom";
        };

        wawona-android-provision = {
          type = "app";
          program = "${androidUtils.provisionAndroidScript}/bin/provision-android";
        };

        wawona-android = {
          type = "app";
          program = "${systemPackages.wawona-android}/bin/wawona-android-run";
        };

        wawona-android-project = {
          type = "app";
          program = "${systemPackages.gradlegen}/bin/gradlegen";
        };

        vulkan-cts-android = {
          type = "app";
          program = "${systemPackages.vulkan-cts-android}/bin/vulkan-cts-android-run";
        };

        gl-cts-android = {
          type = "app";
          program = "${systemPackages.gl-cts-android}/bin/gl-cts-android-run";
        };
      } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        wawona-android-project = {
          type = "app";
          program = "${systemPackages.gradlegen}/bin/gradlegen";
        };

        wawona-macos = {
          type = "app";
          program = "${systemPackages.default}/bin/wawona";
        };

        wawona-macos-project = {
          type = "app";
          program = "${systemPackages.xcodegen}/bin/xcodegen";
        };

        foot = {
          type = "app";
          program = "${systemPackages.foot}/bin/foot";
        };

        weston-terminal = {
          type = "app";
          program = "${systemPackages.weston-terminal}/bin/weston-terminal";
        };

        weston-debug = {
          type = "app";
          program = "${systemPackages.weston-debug}/bin/weston-debug";
        };

        weston-simple-shm = {
          type = "app";
          program = "${systemPackages.weston-simple-shm}/bin/weston-simple-shm";
        };

        vulkan-cts = {
          type = "app";
          program = "${systemPackages.vulkan-cts}/bin/deqp-vk";
        };

        graphics-smoke = {
          type = "app";
          program = "${systemPackages.graphics-smoke}/bin/graphics-smoke";
        };

        graphics-validate = {
          type = "app";
          program = "${systemPackages.graphics-validate}/bin/graphics-validate";
        };


        
        wawona-ios-provision = {
          type = "app";
          program = "${systemPackages.wawona-ios-provision}/bin/provision-xcode";
        };
        
        # Run Nix-built iOS app in simulator (avoids recursion from automationScript -> xcodegen)
        wawona-ios = {
          type = "app";
          program = appPrograms.wawonaIos;
        };

        wawona-ios-project = {
          type = "app";
          program = "${systemPackages.xcodegen}/bin/xcodegen";
        };

        vulkan-cts-ios = {
          type = "app";
          program = "${systemPackages.vulkan-cts-ios}/bin/vulkan-cts-ios-run";
        };

        gl-cts = {
          type = "app";
          program = "${systemPackages.gl-cts}/bin/glcts";
        };

        graphics-validate-macos = {
          type = "app";
          program = "${systemPackages.graphics-validate}/bin/graphics-validate-macos";
        };

        graphics-validate-ios = {
          type = "app";
          program = "${systemPackages.graphics-validate}/bin/graphics-validate-ios";
        };

        graphics-validate-android = {
          type = "app";
          program = "${systemPackages.graphics-validate}/bin/graphics-validate-android";
        };

        graphics-validate-all = {
          type = "app";
          program = "${systemPackages.graphics-validate}/bin/graphics-validate-all";
        };
      });
    }) systems);
    devShells = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      
      linuxShell = pkgs.mkShell {
        buildInputs = [
          pkgs.hello
          pkgs.nix-output-monitor
        ];
        shellHook = ''
          echo "nix-output-monitor enabled: use 'nom build', 'nom develop', or aliases 'nb', 'nd', 'ns'."
          alias nb='nom build'
          alias nd='nom develop'
          alias ns='nom shell'
        '';
      };

      darwinShell = pkgs.mkShell {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.nix-output-monitor
          pkgs.rustToolchain
          pkgs.libxkbcommon
          pkgs.libffi
          pkgs.wayland-protocols
          pkgs.openssl
        ] ++ (if pkgs.stdenv.isDarwin then [
          (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).ensureIosSimSDK
          (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).findXcodeScript
        ] else []);

        shellHook = ''
          export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
          export WAYLAND_DISPLAY="wayland-0"
          mkdir -p $XDG_RUNTIME_DIR
          chmod 700 $XDG_RUNTIME_DIR

          export NIX_SSL_CERT_FILE="/etc/ssl/cert.pem"
          export SSL_CERT_FILE="/etc/ssl/cert.pem"

          if [ -f .envrc ]; then
            TEAM_ID=$(grep '^export TEAM_ID=' .envrc | cut -d'=' -f2 | tr -d '"')
            if [ -n "$TEAM_ID" ]; then
              export TEAM_ID="$TEAM_ID"
            fi
          fi

          echo "nix-output-monitor enabled: use 'nom build', 'nom develop', or aliases 'nb', 'nd', 'ns'."
          alias nb='nom build'
          alias nd='nom develop'
          alias ns='nom shell'
        '';
      };
    in {
      name = system;
      value = {
        default = if pkgs.stdenv.isDarwin then darwinShell else linuxShell;
      };
    }) systems);

    checks = builtins.listToAttrs (map (system: let
      pkgs = pkgsFor system;
      systemPackages = allPackages.${system};
    in {
      name = system;
      value = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
        graphics-validate-smoke = pkgs.runCommand "graphics-validate-smoke" {
          nativeBuildInputs = [ pkgs.coreutils ];
        } ''
          echo "Graphics validation smoke check (builds CTS packages)"
          test -n "${systemPackages.vulkan-cts}"
          test -n "${systemPackages.gl-cts}"
          echo "Vulkan CTS: ${systemPackages.vulkan-cts}"
          echo "GL CTS: ${systemPackages.gl-cts}"
          touch $out
        '';
      };
    }) systems);
  };
}
