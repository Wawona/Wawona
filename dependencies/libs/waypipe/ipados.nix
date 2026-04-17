{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain,
}:

let
  xcodeUtils = iosToolchain;
  cargoTarget = if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios";
  # Use aarch64-apple-ios target for iPadOS device/App Store builds
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
  libwayland = buildModule.buildForIPadOS "libwayland" { inherit simulator; };
  # Compression libraries
  zstd = buildModule.buildForIPadOS "zstd" { inherit simulator; };
  lz4 = buildModule.buildForIPadOS "lz4" { inherit simulator; };
  # libssh2 for SSH tunnels (replaces openssh process spawn on iPadOS)
  libssh2 = buildModule.buildForIPadOS "libssh2" { inherit simulator; };
  mbedtls = buildModule.buildForIPadOS "mbedtls" { inherit simulator; };
  # OpenSSL for iPadOS - required by libssh2-sys's openssl-sys backend
  openssl-ipados = buildModule.buildForIPadOS "openssl" { inherit simulator; };
  # FFmpeg for video encoding/decoding
  ffmpeg = buildModule.buildForIPadOS "ffmpeg" { inherit simulator; };
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
            echo "✓ Waypipe source prepared for iPadOS"
      '';

  patches = [ ];
  # Pre-patch: Minimal - Cargo.toml already modified in src
  # Cargo.lock will be written in postPatch after cargoLock is available
  prePatch = ''
    echo "=== Pre-patching waypipe for iPadOS ==="
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
    openssl-ipados # iPadOS cross-compiled OpenSSL for libssh2-sys openssl-sys backend
  ];

  # compression, in-process ssh, and video (static-only FFmpeg path)
  buildFeatures = [ "lz4" "zstd" "with_libssh2" "video" ];

  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"
    
    # Isolate environment from Nix wrapper flags to prevent linker conflicts
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    
    # App Store build target: arm64 iPhoneOS
    IOS_TARGET="aarch64-apple-ios"
    ${if simulator then ''
      IOS_TARGET="aarch64-apple-ios-sim"
    '' else ""}

    # Use target-specific variables so host builds (build-dependencies) use the Nix SDK
    # .cargo/config.toml will handle the target build.

    # Clean up environment for host tools: CC/LDFLAGS are NOT desired for build.rs!
    # Target-specific variables (above) and .cargo/config.toml will handle the target build.
    # We MUST keep SDKROOT and DEVELOPER_DIR so cc-rs can find the SDK via xcrun!
  
    # FFmpeg and Vulkan paths for wrap-ffmpeg build.rs
    export FFMPEG_DIR="${ffmpeg}"
    export FFMPEG_PREFIX="${ffmpeg}"
    export VULKAN_HEADERS_INCLUDE="${pkgs.vulkan-headers}/include"

    # Set iPadOS deployment target for device
    export IPHONEOS_DEPLOYMENT_TARGET="${iosToolchain.deploymentTarget}"
    
    # Set up library search paths
    export LIBRARY_PATH="${vulkan-loader}/lib:${libwayland}/lib:${zstd}/lib:${lz4}/lib:${libssh2}/lib:${mbedtls}/lib:${openssl-ipados}/lib:${ffmpeg}/lib:$LIBRARY_PATH"
    
    # Use Rust's built-in target
    export CARGO_BUILD_TARGET="${cargoTarget}"
    
    # Configure Rust flags for iPadOS target
    export RUSTFLAGS="-A warnings -C linker=$XCODE_CLANG -C link-arg=-isysroot -C link-arg=$IOS_SDK -C link-arg=$APPLE_DEPLOYMENT_FLAG -L native=${vulkan-loader}/lib -L native=${libssh2}/lib -L native=${mbedtls}/lib -L native=${openssl-ipados}/lib -L native=${ffmpeg}/lib $RUSTFLAGS"
    
    # Configure C compiler for target specific variables
    target_underscore=$(echo "${cargoTarget}" | tr '-' '_')
    export "CC_''${target_underscore}"="$XCODE_CLANG"
    export "CXX_''${target_underscore}"="$XCODE_CLANGXX"
    export "CFLAGS_''${target_underscore}"="-target $APPLE_LINKER_TARGET -isysroot $IOS_SDK $APPLE_DEPLOYMENT_FLAG"
    export "AR_''${target_underscore}"="ar"
    
    # Set PKG_CONFIG_PATH
    export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${zstd}/lib/pkgconfig:${lz4}/lib/pkgconfig:${libssh2}/lib/pkgconfig:${ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    
    # Set up include paths for bindgen (wrap-zstd, wrap-lz4, wrap-ffmpeg)
    export C_INCLUDE_PATH="${zstd}/include:${lz4}/include:${libssh2}/include:${openssl-ipados}/include:${ffmpeg}/include:${pkgs.vulkan-headers}/include:$C_INCLUDE_PATH"
    export CPP_INCLUDE_PATH="${zstd}/include:${lz4}/include:${libssh2}/include:${openssl-ipados}/include:${ffmpeg}/include:${pkgs.vulkan-headers}/include:$CPP_INCLUDE_PATH"
    
    # Configure bindgen for wrap-ffmpeg (FFmpeg headers)
    export BINDGEN_EXTRA_CLANG_ARGS="-I${zstd}/include -I${lz4}/include -I${libssh2}/include -I${openssl-ipados}/include -I${ffmpeg}/include -I${pkgs.vulkan-headers}/include -isysroot $IOS_SDK $APPLE_DEPLOYMENT_FLAG -target $APPLE_LINKER_TARGET"
    export BINDGEN="${pkgs.rust-bindgen}/bin/bindgen"
    export PATH="${pkgs.rust-bindgen}/bin:$PATH"

    # Set up cargo config to ensure these variables are used
    mkdir -p .cargo
    cat > .cargo/config.toml <<CARGO_EOF
[target.${cargoTarget}]
linker = "$XCODE_CLANG"
rustflags = [
  "-C", "linker=$XCODE_CLANG",
  "-C", "link-arg=-arch", "-C", "link-arg=$IOS_ARCH",
  "-C", "link-arg=-isysroot", "-C", "link-arg=$IOS_SDK",
  "-C", "link-arg=$APPLE_DEPLOYMENT_FLAG"
]
CARGO_EOF

    # Set target linker environmental variable (highest precedence)
    export "CARGO_TARGET_''${target_underscore^^}_LINKER"="$XCODE_CLANG"

    # Set host variables to ensure build scripts use host SDK (prevents SDKROOT poisoning)
    export MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    export HOST_CC="/usr/bin/clang"
    export HOST_CFLAGS="-isysroot $MACOS_SDK"
    export HOST_LDFLAGS="-isysroot $MACOS_SDK"

    # Host-side build scripts still need a macOS SDK for Darwin binaries.
    export SDKROOT="$MACOS_SDK"
  '';

  buildPhase = ''
    runHook preBuild
    echo "Building Waypipe Static Library for ${cargoTarget}..."
    
    # Ensure correct crate-type in Cargo.toml if not already patched
    # (The python script in src derivation already does this, but being safe)
    
    # We ensure SDKROOT and DEVELOPER_DIR are set so host-side builds (proc-macros, build scripts) can find SDKs.

    # with_libssh2 is CRITICAL for iPadOS - enables in-process SSH (no subprocess spawn)
    cargo build --lib --target ${cargoTarget} --release --no-default-features --features "lz4,zstd,with_libssh2,video"
    
    runHook postBuild
  '';

  # Attribute version
  # CARGO_BUILD_TARGET = cargoTarget; # Already set above as attribute

  # Patch waypipe for iPadOS compatibility
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
    # iPadOS build produces static library (--lib)
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
