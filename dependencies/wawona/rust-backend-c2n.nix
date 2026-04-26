# crate2nix-based Rust backend for Wawona.
#
# This replaces the monolithic buildRustPackage approach with per-crate
# derivations. Each Rust crate becomes its own Nix derivation, so changing
# one crate (e.g., waypipe) only rebuilds that crate and its dependents.
#
# Supports: macOS, iOS (device + simulator), Android
#
# Cross-compilation strategy (iOS/Android):
#   We override stdenv.hostPlatform in the cross buildRustCrate so that
#   nixpkgs' configure-crate.nix correctly sets TARGET, CARGO_CFG_TARGET_*,
#   and build-crate.nix automatically adds --target to rustc. This produces
#   correctly-tagged objects from the start (no binary patching needed).
#
#   Each crate is lazily built TWICE:
#     HOST build  — native compilation; supplies rlibs for build-script linking
#     CROSS build — crate compiled for iOS/Android via the cross stdenv
#   Build deps are swapped to their HOST versions (.hostLib). Proc-macro
#   crates are built entirely for host. The host build of each crate is
#   lazy — Nix only evaluates it when .hostLib is actually referenced.
#
{ pkgs
, lib
, crate2nix
, wawonaVersion
, workspaceSrc
, platform          # "macos" | "ios" | "android"
, simulator ? false # iOS only: build for simulator
, toolchains ? null # cross-compilation toolchains
, nativeDeps ? {}   # platform-specific native library derivations
, nixpkgs           # the nixpkgs source (used to build a clean cross pkgs)
, androidSDK ? null
, androidToolchain ? null
}:

let
  # ── Target triple ──────────────────────────────────────────────────
  cargoTarget =
    if platform == "ios" then
      (if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios")
    else if platform == "android" then
      "aarch64-linux-android"
    else
      null; # macOS: native build, no cross-compilation target

  sdkPlatform = if simulator then "iPhoneSimulator" else "iPhoneOS";
  xcrunSdk = if simulator then "iphonesimulator" else "iphoneos";
  linkerTarget = if simulator then "arm64-apple-ios26.0-simulator" else "arm64-apple-ios26.0";
  cargoEnvPrefix = if simulator then "CARGO_TARGET_AARCH64_APPLE_IOS_SIM" else "CARGO_TARGET_AARCH64_APPLE_IOS";

  isIOS = platform == "ios";
  isAndroid = platform == "android";
  isMacOS = platform == "macos";
  isCross = isIOS || isAndroid;

  # ── Android toolchain ──────────────────────────────────────────────
  androidToolchainEffective = if androidToolchain != null then androidToolchain 
    else if isAndroid then import ../toolchains/android.nix { inherit lib pkgs androidSDK; }
    else null;

  NDK_SYSROOT = if isAndroid then
    androidToolchainEffective.androidNdkSysroot
  else null;

  NDK_LIB_PATH = if isAndroid then
    androidToolchainEffective.androidNdkAbiLibDir
  else null;

  androidLinkerWrapper = if isAndroid then
    pkgs.writeShellScript "android-linker-wrapper" ''
      exec ${androidToolchainEffective.androidCC} \
        --target=${androidToolchainEffective.androidTarget} \
        --sysroot=${NDK_SYSROOT} \
        -L${NDK_LIB_PATH} \
        -L${NDK_SYSROOT}/usr/lib/aarch64-linux-android \
        "$@"
    ''
  else null;

  # ── Xcode SDK detection (iOS/macOS) ────────────────────────────────
  ensureIosSDKHelpers = if isIOS then
    (import ../apple/default.nix { inherit (pkgs) lib pkgs; })
  else {};

  # ── crate2nix: generate per-crate derivations ─────────────────────
  cargoNixDrv = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
    name = "wawona-${platform}${lib.optionalString (isIOS && simulator) "-sim"}";
    src = workspaceSrc;
  };

  # ── Cross-compilation via stdenv.hostPlatform override ─────────────
  #
  # The key insight: nixpkgs' configure-crate.nix sets TARGET, CARGO_CFG_*,
  # and other env vars from stdenv.hostPlatform. build-crate.nix adds
  # --target when hostPlatform != buildPlatform. By overriding hostPlatform
  # to iOS/Android, we get correct env vars for build scripts (cc-rs reads
  # TARGET to decide the C compiler target) and correct --target for rustc,
  # all without binary patching.

  rawClang = "${pkgs.stdenv.cc.cc}/bin/clang";
  cargoTargetUnderscore = builtins.replaceStrings ["-"] ["_"] (if cargoTarget != null then cargoTarget else "");
  androidRustToolchain =
    if isAndroid && pkgs ? rustToolchainAndroid then
      pkgs.rustToolchainAndroid
    else if isAndroid && pkgs ? rust-bin then
      pkgs.rust-bin.stable.latest.default.override {
        targets = [ cargoTarget ];
      }
    else null;

  toolchainOverrides = {
    cargo = if androidRustToolchain != null then androidRustToolchain
            else if pkgs ? rustToolchain then pkgs.rustToolchain else pkgs.cargo;
    rustc = if androidRustToolchain != null then androidRustToolchain
            else if pkgs ? rustToolchain then pkgs.rustToolchain else pkgs.rustc;
  };

  # Host buildRustCrate: compiles for macOS (build scripts, proc-macros)
  hostBRC = pkgs.buildRustCrate.override toolchainOverrides;

  # Cross hostPlatform: surgically override the fields that configure-crate.nix
  # and build-crate.nix read, keeping everything else from the macOS stdenv.
  crossHostPlatform =
    if isIOS then
      let base = pkgs.stdenv.hostPlatform; in
      base // {
        config = if simulator then "aarch64-apple-ios-simulator" else "aarch64-apple-ios";
        system = if simulator then "aarch64-apple-ios-simulator" else "aarch64-apple-ios";
        parsed = base.parsed // {
          kernel = base.parsed.kernel // { name = "ios"; };
        };
        isIOS = true;
        isiOS = true;
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = { arch = "aarch64"; os = "ios"; vendor = "apple"; target-family = ["unix"]; };
        };
      }
    else if isAndroid then
      let base = pkgs.stdenv.hostPlatform; in
      base // {
        config = "aarch64-unknown-linux-android";
        system = "aarch64-unknown-linux-android";
        isLinux = true;
        isAndroid = true;
        isUnix = true;
        isDarwin = false;
        parsed = base.parsed // {
          kernel = base.parsed.kernel // { name = "linux"; };
          abi = base.parsed.abi // { name = "android"; };
        };
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = {
            arch = "aarch64";
            os = "android";
            vendor = "unknown";
            target-family = ["unix"];
          };
        };
      }
    else null;

  crossStdenv = if isCross then
    pkgs.stdenv // {
      hostPlatform = crossHostPlatform;
      # build-rust-crate appends `-C linker=${stdenv.cc}/bin/...cc` when hasCC=true.
      # For Android cross builds this forces host gcc-wrapper and overrides our
      # explicit android linker wrapper. Disable that implicit linker injection.
      hasCC = if isAndroid then false else pkgs.stdenv.hasCC;
    }
  else null;

  # Cross buildRustCrate: hostPlatform is iOS/Android, so configure-crate.nix
  # sets TARGET correctly and build-crate.nix adds --target automatically.
  crossBRC = if isCross then
    pkgs.buildRustCrate.override (toolchainOverrides // {
      stdenv = crossStdenv;
    })
  else null;

  # Native library search paths (still needed for cross builds)
  nativeLibSearchPaths =
    if isIOS then
      lib.optional (nativeDeps ? xkbcommon)  "-L native=${nativeDeps.xkbcommon}/lib"
      ++ lib.optional (nativeDeps ? libffi)     "-L native=${nativeDeps.libffi}/lib"
      ++ lib.optional (nativeDeps ? libwayland)  "-L native=${nativeDeps.libwayland}/lib"
      ++ lib.optional (nativeDeps ? zstd)        "-L native=${nativeDeps.zstd}/lib"
      ++ lib.optional (nativeDeps ? lz4)         "-L native=${nativeDeps.lz4}/lib"
      ++ lib.optional (nativeDeps ? libssh2)     "-L native=${nativeDeps.libssh2}/lib"
      ++ lib.optional (nativeDeps ? mbedtls)     "-L native=${nativeDeps.mbedtls}/lib"
      ++ lib.optional (nativeDeps ? openssl)     "-L native=${nativeDeps.openssl}/lib"
      ++ lib.optional (nativeDeps ? kosmickrisp)  "-L native=${nativeDeps.kosmickrisp}/lib"
      ++ lib.optional (nativeDeps ? ffmpeg)      "-L native=${nativeDeps.ffmpeg}/lib"
      ++ lib.optional (nativeDeps ? epoll-shim)  "-L native=${nativeDeps.epoll-shim}/lib"
      ++ lib.optional (nativeDeps ? zlib)        "-L native=${nativeDeps.zlib}/lib"
      ++ [ "-L native=${pkgs.vulkan-loader}/lib" ]
    else if isAndroid then [
      "-C" "linker=${androidLinkerWrapper}"
    ]
    else [];

  # preConfigure for cross builds:
  #  - Clear MACOSX_DEPLOYMENT_TARGET to prevent cc-rs from injecting macOS flags
  #  - Set target-specific CC_<target> so cc-rs uses our clang with -target
  #  - Set CRATE_CC_NO_DEFAULTS=1
  crossPreConfigure =
    if isIOS then ''
      unset MACOSX_DEPLOYMENT_TARGET
      export IPHONEOS_DEPLOYMENT_TARGET="${ensureIosSDKHelpers.deploymentTarget}"
      ${ensureIosSDKHelpers.mkIOSBuildEnv { inherit simulator; }}

      # Target-specific variables for cc-rs
      export CC_${cargoTargetUnderscore}="$XCODE_CLANG -target ${linkerTarget} -isysroot $SDKROOT"
      export CFLAGS_${cargoTargetUnderscore}="-target ${linkerTarget} -isysroot $SDKROOT $APPLE_DEPLOYMENT_FLAG -fPIC"
      export CRATE_CC_NO_DEFAULTS="1"

      # Also set the linker for cargo/rustc
      export CARGO_TARGET_${lib.toUpper cargoTargetUnderscore}_LINKER="$XCODE_CLANG"
      export CARGO_TARGET_${lib.toUpper cargoTargetUnderscore}_RUSTFLAGS="-C linker=$XCODE_CLANG -C link-arg=-target -C link-arg=${linkerTarget} -C link-arg=-isysroot -C link-arg=$SDKROOT -C link-arg=$APPLE_DEPLOYMENT_FLAG"

      # Unset SDKROOT and DEVELOPER_DIR so the Nix clang wrapper uses its own
      # built-in apple-sdk for host-side builds (build.rs, proc-macros).
      # Target compilations use the iOS sysroot already baked into CC_<target>.
      unset SDKROOT
      unset DEVELOPER_DIR
    '' else if isAndroid then ''
      unset MACOSX_DEPLOYMENT_TARGET
      # Plain compiler path + flags only in CFLAGS: avoids cc-rs duplicating --target and fixes NDK headers on Linux.
      export CC_${cargoTargetUnderscore}="${androidToolchainEffective.androidCC}"
      export CXX_${cargoTargetUnderscore}="${androidToolchainEffective.androidCXX}"
      export CFLAGS_${cargoTargetUnderscore}="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
      export CXXFLAGS_${cargoTargetUnderscore}="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
      export BINDGEN_EXTRA_CLANG_ARGS="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android ${androidToolchainEffective.androidNdkCflags}"
      export CRATE_CC_NO_DEFAULTS="1"
      export AR="${androidToolchainEffective.androidAR}"
    '' else "";

  swapBuildDepsToHost = attrs: attrs // {
    buildDependencies = map (d: d.hostLib or d) (attrs.buildDependencies or []);
  };

  # mkCrossBRC creates a callable attrset with .override support via __functor.
  # For each crate, it produces:
  #   - crossBuild: compiled for the target platform (via cross stdenv)
  #   - hostBuild: compiled for macOS (for build script deps and proc-macros)
  mkCrossBRC = overrideArgs:
    let
      innerHostBRC = hostBRC.override overrideArgs;
      innerCrossBRC = crossBRC.override overrideArgs;

      fn = crateAttrs:
        let
          isProcMacro = crateAttrs.procMacro or false;

          hostBuild = innerHostBRC (swapBuildDepsToHost (crateAttrs // {
            dependencies = map (d: d.hostLib or d) (crateAttrs.dependencies or []);
          }));

          crossBuild = innerCrossBRC (swapBuildDepsToHost (crateAttrs // {
            extraRustcOpts = (crateAttrs.extraRustcOpts or []) ++ nativeLibSearchPaths;
            preConfigure = (crateAttrs.preConfigure or "") + crossPreConfigure;
          } // lib.optionalAttrs isIOS {
            # iOS builds need host Xcode SDK access inside the sandbox.
            __noChroot = true;
          }));
        in
          if isProcMacro then
            hostBuild // { lib = hostBuild.lib // { completeDeps = []; }; }
          else
            crossBuild // { hostLib = hostBuild.lib or hostBuild; };
    in {
      __functor = self: fn;
      override = newArgs: mkCrossBRC (overrideArgs // newArgs);
    };

  buildRustCrateForTarget = p:
    if !isCross then
      hostBRC
    else
      mkCrossBRC {};

  # Import the generated Cargo.nix with our custom buildRustCrateForPkgs.
  # For cross builds, override pkgs.stdenv.hostPlatform so that the generated
  # Cargo.nix evaluates target conditions (cfg(target_os = "linux"), etc.)
  # against the CROSS platform. Without this, Linux/Android-specific deps
  # like linux_raw_sys and android_system_properties are excluded.
  cargoNixPkgs = if isCross then
    pkgs // { stdenv = crossStdenv; }
  else pkgs;

  cargoNix = import cargoNixDrv {
    pkgs = cargoNixPkgs;
    buildRustCrateForPkgs = buildRustCrateForTarget;
  };

  # ── Features to enable ─────────────────────────────────────────────
  features =
    if isIOS then [ "waypipe-ssh" ]
    else if isAndroid then [ "waypipe" ]
    else []; # macOS: no waypipe integration in backend

  # ── Per-crate build overrides ──────────────────────────────────────
  crateOverrides = pkgs.defaultCrateOverrides // {
    linux-raw-sys = attrs: {
      features = lib.unique ((attrs.features or []) ++ [ "errno" ]);
    };

    weedle2 = attrs: {
      # Crates are gzipped tarballs; `.crate` is not always recognized by stdenv unpack on Linux CI.
      src = pkgs.fetchurl {
        name = "weedle2-5.0.0.tar.gz";
        url = "https://crates.io/api/v1/crates/weedle2/5.0.0/download";
        hash = "sha256-mY0sJOwJmofa+UZ4CIWfnYK2Hx2clwElGuoDf1FOrg4=";
      };
    };

    # ── wawona (root crate) ────────────────────────────────────────
    wawona = attrs: {
      preConfigure = (attrs.preConfigure or "") + lib.optionalString pkgs.stdenv.isDarwin ''
        export MACOSX_DEPLOYMENT_TARGET="14.0"
      '';
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [
        pkgs.pkg-config
      ] ++ lib.optionals isIOS [
        pkgs.python3
        pkgs.rust-bindgen
      ];

      buildInputs = (attrs.buildInputs or []) ++
        (if isMacOS then [
          pkgs.libxkbcommon
          pkgs.libffi
          pkgs.openssl
          pkgs.vulkan-loader
          pkgs.libiconv
          (nativeDeps.libwayland or toolchains.macos.libwayland)
        ]
        else if isIOS then [
          (nativeDeps.xkbcommon or null)
          (nativeDeps.libffi or null)
          (nativeDeps.libwayland or null)
          (nativeDeps.zstd or null)
          (nativeDeps.lz4 or null)
          (nativeDeps.libssh2 or null)
          (nativeDeps.mbedtls or null)
          (nativeDeps.openssl or null)
          (nativeDeps.kosmickrisp or null)
          (nativeDeps.ffmpeg or null)
          (nativeDeps.epoll-shim or null)
          pkgs.vulkan-loader
        ]
        else if isAndroid then [
          (nativeDeps.xkbcommon or null)
          (nativeDeps.libwayland or null)
          (nativeDeps.zstd or null)
          (nativeDeps.lz4 or null)
          (nativeDeps.pixman or null)
          (nativeDeps.openssl or null)
          (nativeDeps.libffi or null)
          (nativeDeps.expat or null)
          (nativeDeps.libxml2 or null)
          pkgs.vulkan-loader
        ]
        else []);

      crateType = if isIOS then [ "lib" "staticlib" ]
                  else if isAndroid then [ "lib" "staticlib" "cdylib" ]
                  else [ "lib" "staticlib" "cdylib" ];

      CARGO_CRATE_NAME = "wawona";
      CARGO_PKG_NAME = "wawona";
      CARGO_MANIFEST_DIR = "";

      rustc = if pkgs ? rustToolchain then pkgs.rustToolchain else null;
      cargo = if pkgs ? rustToolchain then pkgs.rustToolchain else null;

      CARGO_BUILD_TARGET = if isCross then cargoTarget else null;
      
      # For iOS and Android, wawona is purely a shared/static library
      buildBin = if isMacOS then true else false;

    } // lib.optionalAttrs isIOS {
      __noChroot = true;
      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_SYSROOT_DIR = "/";
      PKG_CONFIG_PATH = lib.concatStringsSep ":" (
        lib.optional (nativeDeps ? libwayland) "${nativeDeps.libwayland}/lib/pkgconfig"
        ++ lib.optional (nativeDeps ? zstd) "${nativeDeps.zstd}/lib/pkgconfig"
        ++ lib.optional (nativeDeps ? lz4) "${nativeDeps.lz4}/lib/pkgconfig"
        ++ lib.optional (nativeDeps ? libssh2) "${nativeDeps.libssh2}/lib/pkgconfig"
        ++ lib.optional (nativeDeps ? xkbcommon) "${nativeDeps.xkbcommon}/lib/pkgconfig"
        ++ lib.optional (nativeDeps ? ffmpeg) "${nativeDeps.ffmpeg}/lib/pkgconfig"
      );
    } // lib.optionalAttrs isAndroid ({
      # Use plain clang + CFLAGS from crossPreConfigure for cc-rs; linker wrapper is rustc-only.
      CC_aarch64_linux_android = "${androidToolchainEffective.androidCC}";
      CXX_aarch64_linux_android = "${androidToolchainEffective.androidCXX}";
      AR_aarch64_linux_android = androidToolchainEffective.androidAR;
      AR = androidToolchainEffective.androidAR;
      CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";
      dontStrip = true;
    } // lib.optionalAttrs (nativeDeps ? openssl) {
      OPENSSL_DIR = "${nativeDeps.openssl}";
      OPENSSL_STATIC = "1";
      OPENSSL_NO_VENDOR = "1";
    });

    # ── wayland-backend (needs iOS/macOS patches) ──────────────────
    wayland-backend = attrs: lib.optionalAttrs (isIOS) {
      postPatch = ''
        find . -name "*.rs" -exec sed -i \
          's/target_os[[:space:]]*=[[:space:]]*"macos"/any(target_os = "macos", target_os = "ios")/g' {} +
        find . -name "*.rs" -exec sed -i \
          's/not(target_os[[:space:]]*=[[:space:]]*"macos")/not(any(target_os = "macos", target_os = "ios"))/g' {} +
      '';
    };

    # ── wayland-sys ────────────────────────────────────────────────
    wayland-sys = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? libwayland) nativeDeps.libwayland;
    } // lib.optionalAttrs (nativeDeps ? libwayland) {
      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_PATH = "${nativeDeps.libwayland}/lib/pkgconfig";
    };

    # ── ssh2 (native libssh2 dependency) ───────────────────────────
    ssh2 = attrs: {
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? libssh2) nativeDeps.libssh2 ++
        lib.optional (nativeDeps ? openssl) nativeDeps.openssl ++
        lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
    } // lib.optionalAttrs (nativeDeps ? libssh2) {
      PKG_CONFIG_PATH = lib.concatStringsSep ":" [
        "${nativeDeps.libssh2}/lib/pkgconfig"
        (lib.optionalString (nativeDeps ? openssl) "${nativeDeps.openssl}/lib/pkgconfig")
      ];
    };

    # ── libssh2-sys (compiles C code via cc-rs, needs zlib + openssl) ──
    libssh2-sys = attrs:
      let
        zlibDep = if nativeDeps ? zlib then nativeDeps.zlib else pkgs.zlib;
        opensslDep = if nativeDeps ? openssl then nativeDeps.openssl else pkgs.openssl;
      in {
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? libssh2) nativeDeps.libssh2 ++
        [ zlibDep opensslDep ] ++
        lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
      preConfigure = (attrs.preConfigure or "") + lib.optionalString isIOS ''
        export C_INCLUDE_PATH="${lib.optionalString (nativeDeps ? zlib) "${nativeDeps.zlib}/include"}:${lib.optionalString (nativeDeps ? openssl) "${nativeDeps.openssl}/include"}:$C_INCLUDE_PATH"
      '';
      DEP_Z_INCLUDE = if nativeDeps ? zlib then "${nativeDeps.zlib}/include" else "${pkgs.zlib.dev}/include";
    } // (if nativeDeps ? openssl then {
      OPENSSL_DIR = "${nativeDeps.openssl}";
      OPENSSL_STATIC = "1";
      OPENSSL_NO_VENDOR = "1";
      DEP_OPENSSL_INCLUDE = "${nativeDeps.openssl}/include";
    } else {
      OPENSSL_DIR = "${pkgs.openssl.dev}";
      OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
      OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
      DEP_OPENSSL_INCLUDE = "${pkgs.openssl.dev}/include";
    }) // lib.optionalAttrs isIOS {
      __noChroot = true;
    };

    # ── openssl-sys ────────────────────────────────────────────────
    openssl-sys = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional isMacOS pkgs.openssl ++
        lib.optional (nativeDeps ? openssl) nativeDeps.openssl;
    } // lib.optionalAttrs (nativeDeps ? openssl) {
      OPENSSL_DIR = "${nativeDeps.openssl}";
      OPENSSL_STATIC = "1";
      OPENSSL_NO_VENDOR = "1";
      DEP_OPENSSL_INCLUDE = "${nativeDeps.openssl}/include";
    } // lib.optionalAttrs isMacOS {
      OPENSSL_DIR = "${pkgs.openssl.dev}";
      OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
      OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
    };

    # ── waypipe wrapper crates (build scripts use pkg-config) ──────
    waypipe-ffmpeg-wrapper = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [
        pkgs.pkg-config
        pkgs.rust-bindgen
        pkgs.llvmPackages.clang
      ];
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? ffmpeg) nativeDeps.ffmpeg;
    } // lib.optionalAttrs (nativeDeps ? ffmpeg) {
      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_PATH = "${nativeDeps.ffmpeg}/lib/pkgconfig";
      BINDGEN_EXTRA_CLANG_ARGS = "-I${nativeDeps.ffmpeg}/include -I${pkgs.vulkan-headers}/include";
    } // lib.optionalAttrs (isIOS && nativeDeps ? ffmpeg) {
      preConfigure = (attrs.preConfigure or "") + ''
        IOS_BINDGEN_SYSROOT="$(${
          if simulator
          then "${ensureIosSDKHelpers.ensureIosSimSDK}/bin/ensure-ios-sim-sdk"
          else "${ensureIosSDKHelpers.ensureIosSDK}/bin/ensure-ios-sdk"
        })"
        IOS_BINDGEN_MIN_FLAG="${
          if simulator
          then "-mios-simulator-version-min=${ensureIosSDKHelpers.deploymentTarget}"
          else "-miphoneos-version-min=${ensureIosSDKHelpers.deploymentTarget}"
        }"
        export BINDGEN_EXTRA_CLANG_ARGS="$BINDGEN_EXTRA_CLANG_ARGS --target=${linkerTarget} -isysroot $IOS_BINDGEN_SYSROOT $IOS_BINDGEN_MIN_FLAG"
      '';
    };

    waypipe-lz4-wrapper = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? lz4) nativeDeps.lz4;
    } // lib.optionalAttrs (nativeDeps ? lz4) {
      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_PATH = "${nativeDeps.lz4}/lib/pkgconfig";
    };

    waypipe-zstd-wrapper = attrs: {
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
      buildInputs = (attrs.buildInputs or []) ++
        lib.optional (nativeDeps ? zstd) nativeDeps.zstd;
    } // lib.optionalAttrs (nativeDeps ? zstd) {
      PKG_CONFIG_ALLOW_CROSS = "1";
      PKG_CONFIG_PATH = "${nativeDeps.zstd}/lib/pkgconfig";
    };

    # ── waypipe (needs libiconv on macOS) ───────────────────────────
    waypipe = attrs: {
      buildInputs = (attrs.buildInputs or []) ++
        lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
      preConfigure = (attrs.preConfigure or "") + lib.optionalString pkgs.stdenv.isDarwin ''
        export MACOSX_DEPLOYMENT_TARGET="14.0"
      '';
    };

    # ── iana-time-zone (cross-compilation fix for Android) ─────────
    # crate2nix resolves deps on macOS, so `android_system_properties`
    # (behind cfg(target_os = "android")) is missing.  Stub out the
    # Android impl so the crate compiles without that dependency.
    iana-time-zone = attrs: lib.optionalAttrs isAndroid {
      postPatch = ''
        cat > src/tz_android.rs <<'STUB'
        pub(crate) fn get_timezone_inner() -> Result<String, crate::GetTimezoneError> {
            std::env::var("TZ")
                .or_else(|_| Ok::<_, std::env::VarError>("UTC".to_string()))
                .map_err(|_| crate::GetTimezoneError::FailedParsingString)
        }
        STUB
      '';
    };

    # ── xkbcommon ───────────────────────────────────────────────────
    xkbcommon = attrs: {
      buildInputs = (attrs.buildInputs or []) ++
        (if isMacOS then [ pkgs.libxkbcommon ]
         else lib.optional (nativeDeps ? xkbcommon) nativeDeps.xkbcommon);
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [ pkgs.pkg-config ];
    };
  };

  # ── Build the root crate ───────────────────────────────────────────
  rootBuild = cargoNix.rootCrate.build.override ({
    inherit crateOverrides;
    runTests = false;
  } // lib.optionalAttrs (features != []) {
    inherit features;
  });

in
pkgs.stdenvNoCC.mkDerivation {
  pname = "wawona-${platform}-backend${lib.optionalString (isIOS && simulator) "-sim"}";
  version = wawonaVersion;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out/lib $out/include

    ln -s ${rootBuild} $out/rootBuild
    ln -s ${rootBuild.lib or rootBuild} $out/rootBuildLib

    find ${rootBuild.lib or rootBuild}/lib -name "libwawona*.a" -exec cp {} $out/lib/libwawona.a \;
    find ${rootBuild.lib or rootBuild}/lib -name "libwawona*.so" -exec cp {} $out/lib/libwawona_core.so \;

    if [ -d "${rootBuild}/bin" ]; then
      mkdir -p $out/bin
      cp -r ${rootBuild}/bin/* $out/bin/ || true
    fi

    ${lib.optionalString isMacOS ''
      mkdir -p $out/uniffi/swift
      if [ -f "$out/bin/uniffi-bindgen" ] && [ -f "${workspaceSrc}/src/wawona.udl" ]; then
        $out/bin/uniffi-bindgen generate \
          ${workspaceSrc}/src/wawona.udl \
          --language swift \
          --out-dir $out/uniffi/swift 2>&1 | tee $out/uniffi/generation.log || true
      fi
      cp ${workspaceSrc}/src/wawona.udl $out/uniffi/ 2>/dev/null || true
    ''}
  '';

  meta = {
    description = "Wawona Rust backend (${platform}${lib.optionalString (isIOS && simulator) " simulator"}) — built with crate2nix per-crate caching";
    platforms = if isMacOS then lib.platforms.darwin
                else if isIOS then lib.platforms.darwin
                else lib.platforms.all;
  };
}
