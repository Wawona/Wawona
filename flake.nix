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
    systemsList = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

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

    wawonaVersion = let p = pkgsFor "x86_64-linux"; in p.lib.removeSuffix "\n" (p.lib.fileContents (srcFor p + "/VERSION"));
    waypipe-src = let p = pkgsFor "x86_64-linux"; in p.fetchFromGitLab {
      owner = "mstoeckl"; repo = "waypipe"; rev = "v0.11.0";
      sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
    };

    getPackagesForSystem = system:
      let
        pkgs = pkgsFor system;
        isLinuxHost = (system == "x86_64-linux" || system == "aarch64-linux");
        pkgsIos = pkgs.pkgsCross.iphone64;
        src = srcFor pkgs;
        wawonaSrc = ./.;

        toolchains = import ./dependencies/toolchains {
          inherit (pkgs) lib pkgs stdenv buildPackages;
          inherit wawonaSrc;
          pkgsAndroid = pkgs;
          inherit pkgsIos;
        };

        toolchainsAndroid = if isLinuxHost
          then import ./dependencies/toolchains {
            inherit (pkgs) lib pkgs stdenv buildPackages;
            inherit wawonaSrc;
            pkgsAndroid = pkgs;
            inherit pkgsIos;
          }
          else toolchains;
        
        androidHostPkgs = import nixpkgs {
          inherit system;
          config = { allowUnfree = true; android_sdk.accept_license = true; };
        };

        androidSDK = androidHostPkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0"; buildToolsVersions = [ "36.0.0" ];
          platformToolsVersion = "35.0.2"; platformVersions = [ "36" ];
          abiVersions = [ "arm64-v8a" ]; systemImageTypes = [ "google_apis_playstore" ];
          includeEmulator = true; emulatorVersion = "35.1.4"; includeSystemImages = true;
          useGoogleAPIs = false; includeNDK = true; ndkVersions = ["27.0.12077973"];
        };

        androidUtils = import ./dependencies/utils/android-wrapper.nix { inherit (pkgs) lib pkgs; inherit androidSDK; };

        vulkan-cts-android = pkgs.callPackage ./dependencies/libs/vulkan-cts/android.nix {
          lib = pkgs.lib; buildPackages = pkgs.buildPackages;
        };
        gl-cts-android = pkgs.callPackage ./dependencies/libs/vulkan-cts/gl-cts-android.nix {
          lib = pkgs.lib; buildPackages = pkgs.buildPackages;
        };

        waypipe-patched-android = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
          inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-android.sh; platform = "android";
        };

        workspace-src-android = pkgs.callPackage ./dependencies/wawona/workspace-src.nix {
          wawonaSrc = src; waypipeSrc = waypipe-patched-android; platform = "android"; inherit wawonaVersion;
        };

        backend-android = pkgs.callPackage ./dependencies/wawona/rust-backend-c2n.nix {
          inherit crate2nix wawonaVersion nixpkgs androidSDK;
          toolchains = if isLinuxHost then toolchainsAndroid else toolchains;
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

        wawona-android = pkgs.callPackage ./dependencies/wawona/android.nix {
          buildModule = toolchainsAndroid; inherit wawonaSrc wawonaVersion androidSDK androidUtils;
          targetPkgs = pkgs; waypipe = toolchainsAndroid.buildForAndroid "waypipe" { };
          rustBackend = backend-android;
        };

        gradlegen = pkgs.callPackage ./dependencies/generators/gradlegen.nix ({
          wawonaSrc = if isLinuxHost then ./. else src;
          inherit wawonaVersion;
        } // (pkgs.lib.optionalAttrs isLinuxHost {
          iconAssets = null;
        }) // (pkgs.lib.optionalAttrs (!isLinuxHost) {
          wawonaAndroidProject = wawona-android.project;
        }));

        packages = {
          nom = pkgs.nix-output-monitor;
          wawona-android = wawona-android;
          wawona-android-backend = backend-android;
          gradlegen = gradlegen.generateScript;
          wawona-android-project = gradlegen.generateScript;
          vulkan-cts-android = vulkan-cts-android;
          gl-cts-android = gl-cts-android;
          wawona-android-provision = androidUtils.provisionAndroidScript;
        } // (pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin (let
          waypipe-patched-macos = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-macos.sh; platform = "macos";
          };
          waypipe-patched-ios = pkgs.callPackage ./dependencies/libs/waypipe/waypipe-patched-src.nix {
            inherit waypipe-src; patchScript = ./dependencies/libs/waypipe/patch-waypipe-ios.sh; platform = "ios";
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
            weston = toolchains.buildForIOS "weston" {}; pixman = toolchains.buildForIOS "pixman" {};
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
          wawona-macos = wawona-macos; wawona-ios = wawona-ios; 
          wawona-macos-project = xcodegenOutputs.app; wawona-ios-project = xcodegenOutputs.app;
          wawona-ios-provision = (import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; }).provisionXcodeScript;
          graphics-validate-macos = pkgs.callPackage ./dependencies/validation/ios.nix { inherit wawonaSrc wawonaVersion; wawonaIos = wawona-ios; };
          default = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
          wawona = (import ./dependencies/wawona/shell-wrappers.nix).macosWrapper pkgs wawona-macos;
        }));
      in packages;

    getAppsForSystem = system: systemPackages:
      let
        pkgs = pkgsFor system;
        appPrograms = import ./dependencies/wawona/app-programs.nix {
          inherit pkgs systemPackages;
          xcodeUtils = import ./dependencies/utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; };
        };
      in {
        nom = { type = "app"; program = "${pkgs.nix-output-monitor}/bin/nom"; };
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
        graphics-validate-macos = { type = "app"; program = "${systemPackages.graphics-validate-macos}/bin/graphics-validate-ios"; };
      });

    allSystemPackages = nixpkgs.lib.genAttrs systemsList (system: getPackagesForSystem system);
  in {
    packages = allSystemPackages;
    apps = nixpkgs.lib.genAttrs systemsList (system: getAppsForSystem system allSystemPackages.${system});
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
