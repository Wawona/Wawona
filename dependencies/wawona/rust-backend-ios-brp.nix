# iOS Rust backend using buildRustPackage (cargo).
# Crate2nix builds build scripts for the target (iOS), which then can't run on
# the host (macOS). buildRustPackage uses cargo which correctly builds
# host build-deps for build scripts. Use this for iOS device + simulator.
#
{ pkgs, lib, workspaceSrc, nativeDeps, wawonaVersion, wawonaSrc, simulator ? false }:

let
  cargoTarget = if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios";
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ cargoTarget ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
  buildModule = import ../toolchains/default.nix {
    inherit (pkgs) lib pkgs stdenv buildPackages;
    inherit wawonaSrc;
  };
  xcodeUtils = import ../utils/xcode-wrapper.nix { inherit (pkgs) lib pkgs; };
in
rustPlatform.buildRustPackage rec {
  pname = "wawona-ios-backend" + (if simulator then "-sim" else "");
  version = wawonaVersion;

  src = workspaceSrc;

  cargoLock = {
    lockFile = workspaceSrc + "/Cargo.lock";
  };

  cargoBuildFlags = [
    "--target" cargoTarget
    "--lib"
    "--no-default-features"
    "--features" "waypipe-ssh"
  ];
  doCheck = false;

  CARGO_BUILD_TARGET = cargoTarget;

  nativeBuildInputs = with pkgs; [
    pkg-config
    python3
    rust-bindgen
    vulkan-headers
  ];

  buildInputs = lib.filter (x: x != null) [
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
  ];

  __noChroot = true;

  # Patch vendored wayland-backend to treat target_os="ios" like "macos".
  # wayland-backend gates dispatch_all_clients and other server APIs behind
  # target_os = "macos" (since Wayland is Linux/macOS). iOS needs the same
  # code paths. The crate2nix build had per-crate overrides for this; with
  # buildRustPackage we patch the vendor directory after cargo sets it up.
  preBuild = ''
    echo "=== Patching vendored wayland-backend for iOS ==="
    VENDOR_DIR="../cargo-vendor-dir"
    if [ ! -d "$VENDOR_DIR" ]; then
      VENDOR_DIR=$(grep -oP 'directory\s*=\s*"\K[^"]+' .cargo/config.toml 2>/dev/null || echo "")
    fi
    if [ -d "$VENDOR_DIR/wayland-backend-0.3.12" ]; then
      chmod -R u+w "$VENDOR_DIR/wayland-backend-0.3.12"
      find "$VENDOR_DIR/wayland-backend-0.3.12" -name "*.rs" -exec sed -i \
        's/target_os[[:space:]]*=[[:space:]]*"macos"/any(target_os = "macos", target_os = "ios")/g' {} +
      find "$VENDOR_DIR/wayland-backend-0.3.12" -name "*.rs" -exec sed -i \
        's/not(target_os[[:space:]]*=[[:space:]]*"macos")/not(any(target_os = "macos", target_os = "ios"))/g' {} +
      echo "✓ Patched wayland-backend for iOS"
    else
      echo "Warning: wayland-backend vendor dir not found at $VENDOR_DIR/wayland-backend-0.3.12"
      echo "Looking for vendor dir..."
      find .. -maxdepth 2 -name "wayland-backend-*" -type d 2>/dev/null || true
    fi
  '';

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

    # Find the Developer dir associated with this SDK
    export DEVELOPER_DIR=$(echo "$IOS_SDK" | grep -oP '.*?\.app/Contents/Developer')
    # Find Developer SDK
    [ -z "$DEVELOPER_DIR" ] && DEVELOPER_DIR=$(/usr/bin/xcode-select -p)
    export DEVELOPER_DIR

    echo "Using iOS SDK: $IOS_SDK"
    echo "Using Developer Dir: $DEVELOPER_DIR"

    export FFMPEG_DIR="${nativeDeps.ffmpeg}"
    export FFMPEG_PREFIX="${nativeDeps.ffmpeg}"
    export VULKAN_HEADERS_INCLUDE="${pkgs.vulkan-headers}/include"
    export IPHONEOS_DEPLOYMENT_TARGET="26.0"

    export NIX_CFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
    export RUSTC_LINKER="$CC"

    export LIBRARY_PATH="${nativeDeps.kosmickrisp}/lib:${pkgs.vulkan-loader}/lib:${nativeDeps.libwayland}/lib:${nativeDeps.zstd}/lib:${nativeDeps.lz4}/lib:${nativeDeps.libssh2}/lib:${nativeDeps.mbedtls}/lib:${nativeDeps.openssl}/lib:${nativeDeps.ffmpeg}/lib:$LIBRARY_PATH"

    export CARGO_BUILD_TARGET="${cargoTarget}"
    target_underscore=$(echo "${cargoTarget}" | tr '-' '_')
    export "CC_''${target_underscore}"="$CC"
    export "CXX_''${target_underscore}"="$CXX"
    export "CFLAGS_''${target_underscore}"="-target ${if simulator then "arm64-apple-ios26.0-simulator" else "arm64-apple-ios26.0"} -isysroot $IOS_SDK -m${if simulator then "ios-simulator" else "iphoneos"}-version-min=26.0"
    export "AR_''${target_underscore}"="ar"

    export PKG_CONFIG_PATH="${nativeDeps.libwayland}/lib/pkgconfig:${nativeDeps.zstd}/lib/pkgconfig:${nativeDeps.lz4}/lib/pkgconfig:${nativeDeps.libssh2}/lib/pkgconfig:${nativeDeps.ffmpeg}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1

    export C_INCLUDE_PATH="${nativeDeps.zstd}/include:${nativeDeps.lz4}/include:${nativeDeps.libssh2}/include:${nativeDeps.openssl}/include:${nativeDeps.ffmpeg}/include:${pkgs.vulkan-headers}/include:$C_INCLUDE_PATH"
    export CPP_INCLUDE_PATH="${nativeDeps.zstd}/include:${nativeDeps.lz4}/include:${nativeDeps.libssh2}/include:${nativeDeps.openssl}/include:${nativeDeps.ffmpeg}/include:${pkgs.vulkan-headers}/include:$CPP_INCLUDE_PATH"

    export BINDGEN_EXTRA_CLANG_ARGS="-I${nativeDeps.zstd}/include -I${nativeDeps.lz4}/include -I${nativeDeps.libssh2}/include -I${nativeDeps.openssl}/include -I${nativeDeps.ffmpeg}/include -I${pkgs.vulkan-headers}/include -isysroot $IOS_SDK -miphoneos-version-min=26.0 -target arm64-apple-ios26.0"
    export BINDGEN="${pkgs.rust-bindgen}/bin/bindgen"

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

  installPhase = ''
    mkdir -p $out/lib $out/include
    find target/${cargoTarget}/release -name "libwawona*.a" -exec cp {} $out/lib/libwawona.a \;
    if [ ! -f $out/lib/libwawona.a ]; then
      echo "libwawona.a not found. Contents of target:"
      find target -name "*.a" | head -20
      exit 1
    fi
  '';

  meta.platforms = lib.platforms.darwin;
}
