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
    systemsList = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];

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
          (self: super: 
            if (super.stdenv.hostPlatform.isDarwin) then {
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
            } else {}
          )
        ];
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
            name = builtins.baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./.) (toString path);
          in 
            !(name == ".git" || name == "result" || name == ".direnv" || name == "target" || 
              name == ".gemini" || name == "Inspiration" || name == ".idea" || name == ".vscode" ||
              name == ".DS_Store") &&
            (
              name == "Cargo.toml" || name == "Cargo.lock" || name == "VERSION" || name == "build.rs" ||
              pkgs.lib.hasPrefix "/src" relPath ||
              pkgs.lib.hasPrefix "src" relPath ||
              pkgs.lib.hasPrefix "/protocols" relPath ||
              pkgs.lib.hasPrefix "/scripts" relPath ||
              pkgs.lib.hasPrefix "/include" relPath
            );
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
        isLinuxHost = (system == "x86_64-linux" || system == "aarch64-linux");
        
        # Clean package set for Android — only the rust-overlay is included
        # to provide pkgs.rust-bin for waypipe/android.nix. The second and third
        # host overlays are excluded to prevent cargo → libsecret → gjs → 
        # spidermonkey → cbindgen recursive evaluation chains.
        androidPkgs = if isLinuxHost then (import nixpkgs {
          inherit system;
          config = { allowUnfree = true; android_sdk.accept_license = true; };
          overlays = [ (import rust-overlay) ];
        }) else pkgs;

        pkgsIos = if !isLinuxHost then pkgs.pkgsCross.iphone64 else null;
        
        # Define a clean cross-set
        pkgsAndroidCross = if isLinuxHost then androidPkgs.pkgsCross.aarch64-android else pkgs;

        src = srcFor pkgs;
        wawonaSrc = ./.;

        toolchains = import ./dependencies/toolchains {
          inherit (pkgs) lib pkgs stdenv buildPackages;
          inherit wawonaSrc androidSDK;
          pkgsAndroid = pkgsAndroidCross;
          inherit pkgsIos;
        };

        # On Linux, create a separate toolchains instance using the overlay-free
        # androidPkgs to prevent rust-overlay from triggering recursive evaluation
        # chains through cargo → libsecret → gjs → spidermonkey → cbindgen.
        toolchainsAndroid = if isLinuxHost then import ./dependencies/toolchains {
          lib = androidPkgs.lib; pkgs = androidPkgs;
          stdenv = androidPkgs.stdenv; buildPackages = androidPkgs.buildPackages;
          inherit wawonaSrc androidSDK;
          pkgsAndroid = pkgsAndroidCross;
          pkgsIos = null;
        } else toolchains;
        
        androidSDK = androidPkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0"; buildToolsVersions = [ "36.0.0" ];
          platformToolsVersion = "35.0.2"; platformVersions = [ "36" ];
          abiVersions = [ "arm64-v8a" ]; systemImageTypes = [ "google_apis_playstore" ];
          includeEmulator = true; emulatorVersion = "35.1.4"; includeSystemImages = true;
          useGoogleAPIs = false; includeNDK = true; ndkVersions = ["27.0.12077973"];
        };

        androidUtils = import ./dependencies/utils/android-wrapper.nix { 
          lib = androidPkgs.lib; pkgs = androidPkgs; inherit androidSDK; 
        };

        vulkan-cts-android = import ./dependencies/libs/vulkan-cts/android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
        };
        gl-cts-android = import ./dependencies/libs/vulkan-cts/gl-cts-android.nix {
          inherit (pkgs) lib buildPackages stdenv;
          pkgs = androidPkgs;
          inherit androidSDK;
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
          androidToolchain = if isLinuxHost then toolchainsAndroid.androidToolchain else null;
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
          inherit (androidPkgs) lib stdenv clang pkg-config jdk17 gradle unzip zip patchelf file util-linux glslang mesa;
          pkgs = androidPkgs;
          buildModule = toolchainsAndroid; inherit wawonaSrc wawonaVersion androidSDK androidUtils;
          androidToolchain = toolchainsAndroid.androidToolchain;
          targetPkgs = androidPkgs; waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
          rustBackend = backend-android;
        };

        gradlegenPkg = pkgs.callPackage ./dependencies/generators/gradlegen.nix ({
          wawonaSrc = if isLinuxHost then ./. else src;
          inherit wawonaVersion;
        } // (pkgs.lib.optionalAttrs isLinuxHost {
          iconAssets = null;
        }) // (pkgs.lib.optionalAttrs (!isLinuxHost) {
          wawonaAndroidProject = wawonaAndroidPkg.project;
        }));

        packages = {
          nom = pkgs.nix-output-monitor;
          local-runner = pkgs.callPackage ./scripts/local-runner.nix { };
          wawona-android = wawonaAndroidPkg;
          wawona-android-backend = backend-android;
          gradlegen = gradlegenPkg.generateScript;
          wawona-android-project = gradlegenPkg.generateScript;
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
          wawona-android-provision = androidUtils.provisionAndroidScript;
        } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          waypipe-patched-macos = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh; platform = "macos";
          };
          waypipe-patched-ios = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-source.sh; platform = "ios";
          };
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
             inherit wawonaVersion wawonaSrc; buildModule = toolchains; targetPkgs = pkgs; 
             rustPlatform = pkgs.rustPlatform; inherit iosDeps iosSimDeps macosDeps;
             macosWeston = toolchains.buildForMacOS "weston" { };
          };
          wawona-macos = pkgs.callPackage ./dependencies/wawona/macos.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion;
            waypipe = toolchains.buildForMacOS "waypipe" { }; weston = toolchains.buildForMacOS "weston" { };
            rustBackend = backend-macos; xcodeProject = xcodegenOutputs.project;
          };
          wawona-ios = pkgs.callPackage ./dependencies/wawona/ios.nix {
            buildModule = toolchains; inherit wawonaSrc wawonaVersion; targetPkgs = pkgsIos;
            weston = toolchains.buildForIOS "weston" { simulator = true; };
            rustBackend = backend-ios; rustBackendSim = backend-ios-sim; xcodeProject = xcodegenOutputs.project;
          };
        in {
          wawona-macos = wawona-macos;
          wawona-ios = wawona-ios;
          wawona-macos-backend = backend-macos;
          wawona-macos-xcode-env = backend-macos;
          wawona-ios-backend = backend-ios;
          wawona-ios-xcode-env = backend-ios;
          wawona-ios-sim-backend = backend-ios-sim;
          wawona-ios-sim-xcode-env = backend-ios-sim;
          wawona-macos-project = xcodegenOutputs.app;
          wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).provisionXcodeScript;
          xcodegen = xcodegenOutputs.app;
          xcodegenProject = xcodegenOutputs.project;
          graphics-validate-macos = pkgs.callPackage ./dependencies/tests/graphics-validate.nix { };
          vulkan-cts = toolchains.buildForMacOS "vulkan-cts" { };
          vulkan-cts-ios = toolchains.buildForIOS "vulkan-cts" { };
          gl-cts = toolchains.buildForMacOS "gl-cts" { };
          gl-cts-ios = toolchains.buildForIOS "gl-cts" { };
          weston = toolchains.buildForMacOS "weston" {};
          weston-debug = toolchains.buildForMacOS "weston" { debug = true; };
          weston-simple-shm = toolchains.buildForMacOS "weston-simple-shm" {};
          weston-terminal = toolchains.buildForMacOS "weston-terminal" {};
          waypipe = toolchains.buildForMacOS "waypipe" { };
          waypipe-ios = toolchains.buildForIOS "waypipe" { };
          waypipe-ios-sim = toolchains.buildForIOS "waypipe" { simulator = true; };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
          wawona = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
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
