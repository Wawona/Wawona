{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  cargoTarget = if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios";
  # Use aarch64-apple-ios target for iOS device/App Store builds
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ cargoTarget ];
  };
  myRustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  fetchSource = common.fetchSource;
  waypipeSource = {
    source = "gitlab";
    owner = "mstoeckl";
    repo = "waypipe";
    tag = "v0.10.6";
    sha256 = "sha256-Tbd/yY90yb2+/ODYVL3SudHaJCGJKatZ9FuGM2uAX+8=";
  };
  src = fetchSource waypipeSource;
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  # Compression libraries
  zstd = buildModule.buildForIOS "zstd" { inherit simulator; };
  lz4 = buildModule.buildForIOS "lz4" { inherit simulator; };
  # libssh2 for SSH tunnels (replaces openssh process spawn on iOS)
  libssh2 = buildModule.buildForIOS "libssh2" { inherit simulator; };
  mbedtls = buildModule.buildForIOS "mbedtls" { inherit simulator; };
  # OpenSSL for iOS - required by libssh2-sys's openssl-sys backend
  openssl-ios = buildModule.buildForIOS "openssl" { inherit simulator; };
  # FFmpeg for video encoding/decoding
  ffmpeg = buildModule.buildForIOS "ffmpeg" { inherit simulator; };
  # Vulkan loader (required to load the ICD)
  vulkan-loader = pkgs.vulkan-loader;

  # Use pre-generated Cargo.lock that includes bindgen for reproducible builds
  # This file was generated once and committed to the repository to avoid
  # network access during builds (which breaks Nix reproducibility)
  updatedCargoLockFile = ./Cargo.lock.patched;

  patches = [ ];
in
myRustPlatform.buildRustPackage {
  pname = "waypipe";
  version = "v0.10.6";
  # Modify source to include bindgen in wrap-ffmpeg/Cargo.toml before vendoring
  # This ensures Cargo.lock includes bindgen when cargoSetupHook runs
  src =
    pkgs.runCommand "waypipe-src-with-bindgen"
      {
        src = fetchSource waypipeSource;
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
            # Copy source
            if [ -d "$src" ]; then
              cp -r "$src" $out
            else
              mkdir $out
              tar -xf "$src" -C $out --strip-components=1
            fi
            chmod -R u+w $out
            echo "✓ Waypipe source prepared for iOS"
      '';

  patches = [ ];
  # Pre-patch: Minimal - Cargo.toml already modified in src
  # Cargo.lock will be written in postPatch after cargoLock is available
  prePatch = ''
    echo "=== Pre-patching waypipe for iOS ==="
    # Cargo.toml modifications are already done in src derivation
    echo "✓ Cargo.toml already includes bindgen and pkg-config"
  '';

  # Use cargoLock with the generated lock file
  cargoHash = "";
  cargoLock = {
    lockFile = updatedCargoLockFile;
  };
  cargoDeps = null; # Will be generated from cargoLock

  cargoBuildTarget = cargoTarget;
  CARGO_BUILD_TARGET = cargoTarget;

  nativeBuildInputs = with pkgs; [
    pkg-config
    python3 # Needed for pipe2 patching script
    rustPlatform.bindgenHook # Provides bindgen for build.rs scripts
    rust-bindgen # Provides bindgen CLI used by wrap-ffmpeg/build.rs
    vulkan-headers # Vulkan headers for FFmpeg's Vulkan support
  ];

  # No SSH library dependencies - waypipe will use OpenSSH binary
  # Allow access to Xcode SDKs
  __noChroot = true;

  buildInputs = [
    vulkan-loader
    libwayland
    zstd
    lz4
    libssh2
    mbedtls
    ffmpeg
    openssl-ios # iOS cross-compiled OpenSSL for libssh2-sys openssl-sys backend
  ];

  # compression, in-process ssh, and video (static-only FFmpeg path)
  buildFeatures = [ "lz4" "zstd" "with_libssh2" "video" ];

  preConfigure = ''
        # Strip Nix stdenv's DEVELOPER_DIR to bypass the apple-sdk-14.4 fallback
        unset DEVELOPER_DIR

        ${if simulator then ''
          # Ensure the iOS Simulator SDK is downloaded if missing and get its path.
          IOS_SDK=$(${xcodeUtils.ensureIosSimSDK}/bin/ensure-ios-sim-sdk) || {
            echo "Error: Failed to ensure iOS Simulator SDK."
            exit 1
          }
        '' else ''
          # For device, find the latest iPhoneOS SDK path.
          XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode) || {
            echo "Error: Xcode not found."
            exit 1
          }
          IOS_SDK="$XCODE_APP/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        ''}

        export SDKROOT="$IOS_SDK"
        export IOS_SDK

        # Find the Developer dir associated with this SDK without using -oP
        export DEVELOPER_DIR=$(echo "$IOS_SDK" | sed -E 's|^(.*\.app/Contents/Developer)/.*$|\1|')
        [ "$DEVELOPER_DIR" = "$IOS_SDK" ] && export DEVELOPER_DIR=$(/usr/bin/xcode-select -p)

        echo "Using iOS SDK: $IOS_SDK"
        echo "Using Developer Dir: $DEVELOPER_DIR"
        
        # FFmpeg and Vulkan paths for wrap-ffmpeg build.rs
        export FFMPEG_DIR="${ffmpeg}"
        export FFMPEG_PREFIX="${ffmpeg}"
        export VULKAN_HEADERS_INCLUDE="${pkgs.vulkan-headers}/include"

        # Set iOS deployment target for device
        export IPHONEOS_DEPLOYMENT_TARGET="26.0"
        # Prevent Nix cc-wrapper from adding macOS flags
        export NIX_CFLAGS_COMPILE=""
        export NIX_LDFLAGS=""
        # Override CC/CXX to use Xcode clang directly to avoid cc-wrapper conflicts
        export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
        # Configure Rust to use Xcode linker directly
        export RUSTC_LINKER="$CC"

        # Set up library search paths
        export LIBRARY_PATH="${vulkan-loader}/lib:${libwayland}/lib:${zstd}/lib:${lz4}/lib:${libssh2}/lib:${mbedtls}/lib:${openssl-ios}/lib:${ffmpeg}/lib:$LIBRARY_PATH"
        
        # Use Rust's built-in target
        export CARGO_BUILD_TARGET="${cargoTarget}"
        
        # Configure Rust flags for iOS target
        export RUSTFLAGS="-A warnings -C linker=$CC -C link-arg=-isysroot -C link-arg=$IOS_SDK -C link-arg=-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0 -L native=${vulkan-loader}/lib -L native=${libssh2}/lib -L native=${mbedtls}/lib -L native=${openssl-ios}/lib -L native=${ffmpeg}/lib $RUSTFLAGS"
        
        # Configure C compiler for target
        target_underscore=$(echo "${cargoTarget}" | tr '-' '_')
        export "CC_''${target_underscore}"="$CC"
        export "CXX_''${target_underscore}"="$CXX"
        export "CFLAGS_''${target_underscore}"="-target ${if simulator then "arm64-apple-ios26.0-simulator" else "arm64-apple-ios26.0"} -isysroot $IOS_SDK -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
        export "AR_''${target_underscore}"="ar"
        
        # Set PKG_CONFIG_PATH
        export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${zstd}/lib/pkgconfig:${lz4}/lib/pkgconfig:${libssh2}/lib/pkgconfig:${ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
        export PKG_CONFIG_ALLOW_CROSS=1
        
        # Set up include paths for bindgen (wrap-zstd, wrap-lz4, wrap-ffmpeg)
        export C_INCLUDE_PATH="${zstd}/include:${lz4}/include:${libssh2}/include:${openssl-ios}/include:${ffmpeg}/include:${pkgs.vulkan-headers}/include:$C_INCLUDE_PATH"
        export CPP_INCLUDE_PATH="${zstd}/include:${lz4}/include:${libssh2}/include:${openssl-ios}/include:${ffmpeg}/include:${pkgs.vulkan-headers}/include:$CPP_INCLUDE_PATH"
        
        # Configure bindgen for wrap-ffmpeg (FFmpeg headers)
        export BINDGEN_EXTRA_CLANG_ARGS="-I${zstd}/include -I${lz4}/include -I${libssh2}/include -I${openssl-ios}/include -I${ffmpeg}/include -I${pkgs.vulkan-headers}/include -isysroot $IOS_SDK -miphoneos-version-min=26.0 -target arm64-apple-ios26.0"
        export BINDGEN="${pkgs.rust-bindgen}/bin/bindgen"
        export PATH="${pkgs.rust-bindgen}/bin:$PATH"
        
        
  mkdir -p .cargo
  cat > .cargo/config.toml <<CARGO_CONFIG
[target.${cargoTarget}]
linker = "$CC"
rustflags = [
  "-C", "link-arg=-isysroot",
  "-C", "link-arg=$IOS_SDK",
  "-C", "link-arg=-m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0",
]
CARGO_CONFIG
  '';

  buildPhase = ''
    runHook preBuild
    echo "Building Waypipe Static Library for ${cargoTarget}..."
    
    # Ensure correct crate-type in Cargo.toml if not already patched
    # (The python script in src derivation already does this, but being safe)
    
    # Unset SDKROOT so it doesn't leak into host-side build scripts/proc-macros via bindgen etc.
    unset SDKROOT

    # with_libssh2 is CRITICAL for iOS - enables in-process SSH (no subprocess spawn)
    cargo build --lib --target ${cargoTarget} --release --no-default-features --features "lz4,zstd,with_libssh2,video"
    
    runHook postBuild
  '';

  # Attribute version
  # CARGO_BUILD_TARGET = cargoTarget; # Already set above as attribute

  # Patch waypipe for iOS compatibility
  # kosmickrisp provides Vulkan with VK_EXT_external_memory_dma_buf support for DMABUF
  # This enables GPU-accelerated buffer sharing for nested compositors like Weston
  # Also patch other wrappers that may be built unconditionally
  postPatch = ''
    # Run common patching script
    ${pkgs.bash}/bin/bash ${./patch-waypipe-source.sh}

    # Write Cargo.lock to source directory to match cargoLock.lockFile
    echo "Writing Cargo.lock to source directory..."
    cp ${updatedCargoLockFile} Cargo.lock
    echo "✓ Cargo.lock written to match cargoLock"

    echo "✓ Waypipe configured to use libssh2"
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    # iOS build produces static library (--lib)
    if [ -f target/${cargoTarget}/release/libwaypipe.a ]; then
      cp target/${cargoTarget}/release/libwaypipe.a $out/lib/
      echo "Copied libwaypipe.a"
    else
      echo "Error: libwaypipe.a not found. Contents of target:"
      find target/ -name "*.a" -o -name "waypipe" 2>/dev/null || true
      exit 1
    fi
    # Optionally copy binary if built (e.g. for testing)
    if [ -f target/${cargoTarget}/release/waypipe ]; then
      mkdir -p $out/bin
      cp target/${cargoTarget}/release/waypipe $out/bin/
    fi
  '';

  doCheck = false;
}
