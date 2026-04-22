# crate2nix-based Rust backend for Wawona.
#
# This replaces the monolithic buildRustPackage approach with per-crate
# derivations. Each Rust crate becomes its own Nix derivation, so changing
# one crate (e.g., waypipe) only rebuilds that crate and its dependents.
#
# Supports: macOS, iOS (device + simulator), visionOS (device + simulator), Android
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
, platform          # "macos" | "ios" | "ipados" | "tvos" | "visionos" | "watchos" | "android"
, simulator ? false # iOS/watchOS only: build for simulator
, toolchains ? null # cross-compilation toolchains
, nativeDeps ? {}   # platform-specific native library derivations
, nixpkgs           # the nixpkgs source (used to build a clean cross pkgs)
, androidSDK ? null
, androidToolchain ? null
}:

let
  # ── Target triple ──────────────────────────────────────────────────
  cargoTarget =
    if platform == "ios" || platform == "ipados" then
      (if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios")
    else if platform == "tvos" then
      (if simulator then "aarch64-apple-tvos-sim" else "aarch64-apple-tvos")
    else if platform == "visionos" then
      (if simulator then "aarch64-apple-visionos-sim" else "aarch64-apple-visionos")
    else if platform == "watchos" then
      (if simulator then "aarch64-apple-watchos-sim" else "aarch64-apple-watchos")
    else if platform == "android" then
      "aarch64-linux-android"
    else
      null; # macOS: native build, no cross-compilation target

  sdkPlatform =
    if platform == "ios" || platform == "ipados" then (if simulator then "iPhoneSimulator" else "iPhoneOS")
    else if platform == "tvos" then (if simulator then "AppleTVSimulator" else "AppleTVOS")
    else if platform == "visionos" then (if simulator then "XRSimulator" else "XROS")
    else if platform == "watchos" then (if simulator then "WatchSimulator" else "WatchOS")
    else (if simulator then "iPhoneSimulator" else "iPhoneOS");
  xcrunSdk =
    if platform == "ios" || platform == "ipados" then (if simulator then "iphonesimulator" else "iphoneos")
    else if platform == "tvos" then (if simulator then "appletvsimulator" else "appletvos")
    else if platform == "visionos" then (if simulator then "xrsimulator" else "xros")
    else if platform == "watchos" then (if simulator then "watchsimulator" else "watchos")
    else (if simulator then "iphonesimulator" else "iphoneos");
  linkerTarget =
    if platform == "ios" || platform == "ipados" then (if simulator then "arm64-apple-ios17.0-simulator" else "arm64-apple-ios17.0")
    else if platform == "tvos" then (if simulator then "arm64-apple-tvos17.0-simulator" else "arm64-apple-tvos17.0")
    else if platform == "visionos" then (if simulator then "arm64-apple-xros26.0-simulator" else "arm64-apple-xros26.0")
    else if platform == "watchos" then (if simulator then "arm64-apple-watchos10.0-simulator" else "arm64-apple-watchos10.0")
    else "arm64-apple-ios17.0";
  deploymentTarget =
    if platform == "watchos" then
      "10.0"
    else if platform == "visionos" then
      "26.0"
    else if platform == "tvos" then
      "17.0"
    else if platform == "ios" || platform == "ipados" then
      "17.0"
    else
      "26.0";
  deploymentFlag =
    if platform == "visionos" then
      (if simulator then "-mvisionos-simulator-version-min=26.0" else "-mvisionos-version-min=26.0")
    else if platform == "tvos" then
      (if simulator then "-mtvos-simulator-version-min=17.0" else "-mtvos-version-min=17.0")
    else if platform == "watchos" then
      (if simulator then "-mwatchos-simulator-version-min=10.0" else "-mwatchos-version-min=10.0")
    else if platform == "ios" || platform == "ipados" then
      (if simulator then "-mios-simulator-version-min=17.0" else "-miphoneos-version-min=17.0")
    else
      (if simulator then "-mios-simulator-version-min=26.0" else "-miphoneos-version-min=26.0");
  macosDeploymentTarget = "14.0";
  cargoEnvPrefix =
    if platform == "visionos" then
      (if simulator then "CARGO_TARGET_AARCH64_APPLE_VISIONOS_SIM" else "CARGO_TARGET_AARCH64_APPLE_VISIONOS")
    else if platform == "tvos" then
      (if simulator then "CARGO_TARGET_AARCH64_APPLE_TVOS_SIM" else "CARGO_TARGET_AARCH64_APPLE_TVOS")
    else if platform == "watchos" then
      (if simulator then "CARGO_TARGET_AARCH64_APPLE_WATCHOS_SIM" else "CARGO_TARGET_AARCH64_APPLE_WATCHOS")
    else
      (if simulator then "CARGO_TARGET_AARCH64_APPLE_IOS_SIM" else "CARGO_TARGET_AARCH64_APPLE_IOS");

  isIOS = platform == "ios" || platform == "ipados";
  isTVOS = platform == "tvos";
  isVisionOS = platform == "visionos";
  isWatchOS = platform == "watchos";
  isAndroid = platform == "android";
  isMacOS = platform == "macos";
  isCross = isIOS || isTVOS || isVisionOS || isWatchOS || isAndroid;
  isAppleCross = isIOS || isTVOS || isVisionOS || isWatchOS;

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

  # ── Xcode SDK detection (iOS/watchOS/macOS) ─────────────────────────
  ensureIosSDKHelpers = if isAppleCross then
    (import ../apple/default.nix { inherit (pkgs) lib pkgs; })
  else {};

  ensureIosSimSDKScript = if isAppleCross then
    (import ../utils/xcode-wrapper.nix { inherit (pkgs) lib; inherit pkgs; }).ensureIosSimSDK
  else null;

  # ── crate2nix: generate per-crate derivations ─────────────────────
  cargoNixDrv = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
    name = "wawona-${platform}${lib.optionalString (isAppleCross && simulator) "-sim"}";
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
        # Otherwise base.isDarwin stays true and build-rust-crate adds macOS libiconv
        # to every crate's buildInputs (wrong for iOS simulator/device objects).
        isDarwin = false;
        isIOS = true;
        isiOS = true;
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = { arch = "aarch64"; os = "ios"; vendor = "apple"; target-family = ["unix"]; };
        };
      }
    else if isTVOS then
      let base = pkgs.stdenv.hostPlatform; in
      base // {
        config = if simulator then "aarch64-apple-tvos-sim" else "aarch64-apple-tvos";
        system = if simulator then "aarch64-apple-tvos-sim" else "aarch64-apple-tvos";
        parsed = base.parsed // {
          kernel = base.parsed.kernel // { name = "tvos"; };
        };
        isDarwin = false;
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = { arch = "aarch64"; os = "tvos"; vendor = "apple"; target-family = ["unix"]; };
        };
      }
    else if isVisionOS then
      let base = pkgs.stdenv.hostPlatform; in
      base // {
        config = if simulator then "aarch64-apple-visionos-sim" else "aarch64-apple-visionos";
        system = if simulator then "aarch64-apple-visionos-sim" else "aarch64-apple-visionos";
        parsed = base.parsed // {
          kernel = base.parsed.kernel // { name = "visionos"; };
        };
        isDarwin = false;
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = { arch = "aarch64"; os = "visionos"; vendor = "apple"; target-family = ["unix"]; };
        };
      }
    else if isWatchOS then
      let base = pkgs.stdenv.hostPlatform; in
      base // {
        config = if simulator then "aarch64-apple-watchos-sim" else "aarch64-apple-watchos";
        system = if simulator then "aarch64-apple-watchos-sim" else "aarch64-apple-watchos";
        parsed = base.parsed // {
          kernel = base.parsed.kernel // { name = "watchos"; };
        };
        isDarwin = false;
        rust = (base.rust or {}) // {
          rustcTarget = cargoTarget;
          rustcTargetSpec = cargoTarget;
          platform = { arch = "aarch64"; os = "watchos"; vendor = "apple"; target-family = ["unix"]; };
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
      # explicit android linker wrapper. For Apple cross builds the Nix clang
      # wrapper targets macOS (MacOSX.sdk); iOS simulator/device need Xcode
      # clang with -isysroot to the iPhone* SDK. Linker comes from crossPreConfigure.
      hasCC = if isAndroid || isAppleCross then false else pkgs.stdenv.hasCC;
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
    if isAppleCross then
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

  appleLinkerOverrides =
    if isAppleCross then [
      # buildRustCrate drives rustc directly (not cargo), so target-specific
      # CARGO_TARGET_*_RUSTFLAGS are ignored. Force final linker target/min
      # version here to avoid rustc defaulting to tvOS 10.0.
      "-C" "link-arg=-target"
      "-C" "link-arg=${linkerTarget}"
    ] ++ lib.optionals (!isVisionOS) [
      "-C" "link-arg=${deploymentFlag}"
    ]
    else [];

  # preConfigure for cross builds:
  #  - Clear MACOSX_DEPLOYMENT_TARGET to prevent cc-rs from injecting macOS flags
  #  - Set target-specific CC_<target> so cc-rs uses our clang with -target
  #  - Set CRATE_CC_NO_DEFAULTS=1
  crossPreConfigure =
    if isAppleCross then ''
      unset MACOSX_DEPLOYMENT_TARGET
      ${if isWatchOS then ''
        # Locate the watchOS SDK manually (xcrun may not have a watch-specific helper)
        XCODE_APP=$(${(import ../utils/xcode-wrapper.nix { inherit (pkgs) lib; inherit pkgs; }).findXcodeScript}/bin/find-xcode || true)
        XCODE_DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        WOS_SDK_NAME="${if simulator then "WatchSimulator" else "WatchOS"}"
        export SDKROOT="$XCODE_DEVELOPER_DIR/Platforms/$WOS_SDK_NAME.platform/Developer/SDKs/$WOS_SDK_NAME.sdk"
        export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"
        export XCODE_CLANG="$XCODE_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export APPLE_DEPLOYMENT_FLAG="${deploymentFlag}"
      '' else if isVisionOS then ''
        ${ensureIosSDKHelpers.mkAppleEnv {
          sdkName = if simulator then "xrsimulator" else "xros";
          minVersion = deploymentTarget;
          simulator = simulator;
          platform = "visionos";
        }}
      '' else if isTVOS then ''
        ${ensureIosSDKHelpers.mkAppleEnv {
          sdkName = if simulator then "appletvsimulator" else "appletvos";
          minVersion = deploymentTarget;
          simulator = simulator;
          platform = "tvos";
        }}
      '' else ''
        export IPHONEOS_DEPLOYMENT_TARGET="${ensureIosSDKHelpers.deploymentTarget}"
        ${ensureIosSDKHelpers.mkIOSBuildEnv { inherit simulator; }}
      ''}

      # Target-specific variables for cc-rs
      export CC_${cargoTargetUnderscore}="$XCODE_CLANG -target ${linkerTarget} -isysroot $SDKROOT"
      export CFLAGS_${cargoTargetUnderscore}="-target ${linkerTarget} -isysroot $SDKROOT${lib.optionalString (!isVisionOS) " $APPLE_DEPLOYMENT_FLAG"} -fPIC"
      export CRATE_CC_NO_DEFAULTS="1"

      # Linker for cargo/rustc
      export CARGO_TARGET_${lib.toUpper cargoTargetUnderscore}_LINKER="$XCODE_CLANG"
      export CARGO_TARGET_${lib.toUpper cargoTargetUnderscore}_RUSTFLAGS="-C linker=$XCODE_CLANG -C link-arg=-target -C link-arg=${linkerTarget} -C link-arg=-isysroot -C link-arg=$SDKROOT${lib.optionalString (!isVisionOS) " -C link-arg=$APPLE_DEPLOYMENT_FLAG"}"

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
            extraRustcOpts = (crateAttrs.extraRustcOpts or []) ++ nativeLibSearchPaths ++ appleLinkerOverrides;
            preConfigure = (crateAttrs.preConfigure or "") + crossPreConfigure;
          } // lib.optionalAttrs isAppleCross {
            # Apple cross builds need host Xcode SDK access inside the sandbox.
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
    if isIOS then [ "waypipe-ssh" "smithay-protocols" ]
    else if isTVOS then [ "waypipe-ssh" "smithay-protocols" ]
    else if isVisionOS then [ "smithay-protocols" ]
    else if isWatchOS then [ "smithay-protocols" ] # watchOS: minimal feature set (no SSH/Waypipe)
    else if isAndroid then [ "waypipe" "smithay-protocols" ]
    else [ "smithay-protocols" "smithay-desktop" ]; # macOS desktop: enable smithay xwayland/backend_drm paths

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

    # Keep UniFFI runtime dependency minimal on cross-Apple targets.
    # The CLI feature drags in host-oriented tooling and has been flaky in crate2nix
    # cross builds; we only need derive/runtime support in target libs.
    uniffi = attrs: lib.optionalAttrs isAppleCross {
      features = [ "default" ];
    };

    # nixpkgs defaultCrateOverrides use host pkgs.zlib in extraLinkFlags; for iOS/watchOS
    # that injects macOS libz.dylib search paths into the final link.
    libz-sys = attrs:
      let
        zlibDep =
          if isAppleCross && nativeDeps ? zlib then nativeDeps.zlib else pkgs.zlib;
      in
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ zlibDep ];
        extraLinkFlags = [ "-L${zlibDep}/lib" ];
      };

    # ── wawona (root crate) ────────────────────────────────────────
    wawona = attrs: {
      preConfigure = (attrs.preConfigure or "") + lib.optionalString pkgs.stdenv.isDarwin ''
        export MACOSX_DEPLOYMENT_TARGET="${macosDeploymentTarget}"
      '';
      nativeBuildInputs = (attrs.nativeBuildInputs or []) ++ [
        pkgs.pkg-config
      ] ++ lib.optionals (isIOS || isTVOS || isVisionOS) [
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
        else if isAppleCross then [
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

      crateType = if isAppleCross then [ "lib" "staticlib" ]
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

    } // lib.optionalAttrs isAppleCross {
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
    wayland-backend = attrs: lib.optionalAttrs isAppleCross {
      postPatch = ''
        find . -name "*.rs" -exec sed -i \
          's/target_os[[:space:]]*=[[:space:]]*"macos"/any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos")/g' {} +
        find . -name "*.rs" -exec sed -i \
          's/not(target_os[[:space:]]*=[[:space:]]*"macos")/not(any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos"))/g' {} +
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
      preConfigure = (attrs.preConfigure or "") + lib.optionalString (isIOS || isTVOS || isVisionOS) ''
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
    }) // lib.optionalAttrs (isIOS || isTVOS || isVisionOS) {
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
    } // lib.optionalAttrs ((isIOS || isTVOS || isVisionOS) && nativeDeps ? ffmpeg) {
      preConfigure = (attrs.preConfigure or "") + ''
        IOS_BINDGEN_SYSROOT="$(xcrun --sdk ${xcrunSdk} --show-sdk-path)"
        IOS_BINDGEN_MIN_FLAG="${deploymentFlag}"
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
        export MACOSX_DEPLOYMENT_TARGET="${macosDeploymentTarget}"
      '';
    } // lib.optionalAttrs isTVOS {
      # waypipe gates pipe2/ppoll and other Unix helpers on iOS; tvOS uses the
      # same APIs but rustc reports target_os = "tvos". Two-phase replace avoids
      # re-expanding the `target_os = "ios"` inside the replacement text.
      postPatch = (attrs.postPatch or "") + ''
        if [ -d src ]; then
          while IFS= read -r f; do
            substituteInPlace "$f" --replace 'target_os = "ios"' '__WAWONA_TVOS_IOS__' || true
          done < <(find src -name '*.rs')
          while IFS= read -r f; do
            substituteInPlace "$f" --replace '__WAWONA_TVOS_IOS__' \
              'any(target_os = "ios", target_os = "tvos")' || true
          done < <(find src -name '*.rs')
        fi
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

    # ── calloop (watchOS rustix pipe_with compatibility) ───────────
    # calloop's ping source special-cases only macOS for `pipe()` + fcntl flags.
    # On watchOS, rustix does not expose pipe_with/PipeFlags, so we extend the
    # macOS branch to Apple mobile/watch targets as well.
    calloop = attrs: lib.optionalAttrs isAppleCross {
      postPatch = (attrs.postPatch or "") + ''
        if [ -f src/sources/ping/pipe.rs ]; then
          substituteInPlace src/sources/ping/pipe.rs \
            --replace '#[cfg(target_os = "macos")]' '#[cfg(any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos"))]' \
            --replace '#[cfg(not(target_os = "macos"))]' '#[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos")))]'
        fi
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
  pname = "wawona-${platform}-backend${lib.optionalString (isAppleCross && simulator) "-sim"}";
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
    description = "Wawona Rust backend (${platform}${lib.optionalString (isAppleCross && simulator) " simulator"}) — built with crate2nix per-crate caching";
    platforms = if isMacOS then lib.platforms.darwin
                else if isAppleCross then lib.platforms.darwin
                else lib.platforms.all;
  };
}
