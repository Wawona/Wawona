# Android Rust backend using buildRustPackage (cargo).
# Crate2nix cross-compilation builds build scripts for the target, which then
# can't run on the host. buildRustPackage uses cargo which correctly builds
# build-deps for host. Use this for Android until crate2nix gains host-dep support.
#
{
  pkgs,
  lib,
  workspaceSrc,
  nativeDeps,
  wawonaVersion,
  backendName ? "wawona-android-backend",
  androidSDK ? null,
  androidToolchain ? null,
}:

let
  androidToolchainEffective =
    if androidToolchain != null then
      androidToolchain
    else
      import ../toolchains/android.nix { inherit lib pkgs androidSDK; };
  NDK_SYSROOT = androidToolchainEffective.androidNdkSysroot;
  NDK_LIB_PATH = androidToolchainEffective.androidNdkAbiLibDir;
  NDK_FALLBACK_LIB_PATH = androidToolchainEffective.androidNdkAbiLibDirFallback;
  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchainEffective.androidCC} \
      -L${NDK_LIB_PATH} \
      -L${NDK_FALLBACK_LIB_PATH} \
      "$@"
  '';
  rustPlatform = pkgs.makeRustPlatform {
    cargo =
      if pkgs ? rustToolchainAndroid then
        pkgs.rustToolchainAndroid
      else
        (pkgs.rustToolchain or pkgs.cargo);
    rustc =
      if pkgs ? rustToolchainAndroid then
        pkgs.rustToolchainAndroid
      else
        (pkgs.rustToolchain or pkgs.rustc);
  };
in
rustPlatform.buildRustPackage rec {
  pname = backendName;
  version = wawonaVersion;

  src = workspaceSrc;

  cargoLock = {
    lockFile = workspaceSrc + "/Cargo.lock";
  };

  cargoBuildFlags = [
    "--lib"
    "--no-default-features"
    "--features"
    "smithay-protocols"
  ];
  cargoTestFlags = [
    "--target" "aarch64-linux-android"
    "--lib"
    "--no-default-features"
    "--features"
    "smithay-protocols"
  ];
  doCheck = false;

  cargoBuildTarget = "aarch64-linux-android";
  CC_aarch64_linux_android = "${androidToolchainEffective.androidCC}";
  CXX_aarch64_linux_android = androidToolchainEffective.androidCXX;
  AR_aarch64_linux_android = androidToolchainEffective.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";
  WAWONA_ANDROID_XKBCOMMON_LIBDIR = "${nativeDeps.xkbcommon}/lib";

  buildInputs = lib.filter (x: x != null) [
    (nativeDeps.libwayland or null)
    (nativeDeps.xkbcommon or null)
  ];

  nativeBuildInputs = [ pkgs.pkg-config pkgs.rust-bindgen ];

  OPENSSL_DIR = nativeDeps.openssl;
  OPENSSL_STATIC = "1";
  OPENSSL_NO_VENDOR = "1";
  PKG_CONFIG_PATH = lib.concatStringsSep ":" (
    lib.optional (nativeDeps ? libwayland) "${nativeDeps.libwayland}/lib/pkgconfig"
    ++ lib.optional (nativeDeps ? xkbcommon) "${nativeDeps.xkbcommon}/lib/pkgconfig"
  );

  preConfigure = ''
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG_PATH_aarch64_linux_android="${lib.concatStringsSep ":" (
      lib.optional (nativeDeps ? libwayland) "${nativeDeps.libwayland}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? xkbcommon) "${nativeDeps.xkbcommon}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? openssl) "${nativeDeps.openssl}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? zstd) "${nativeDeps.zstd}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? lz4) "${nativeDeps.lz4}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? ffmpeg) "${nativeDeps.ffmpeg}/lib/pkgconfig"
    )}"
    export CRATE_CC_NO_DEFAULTS=1
    export CFLAGS_aarch64_linux_android="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
    export CXXFLAGS_aarch64_linux_android="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android --target=${androidToolchainEffective.androidTarget} ${androidToolchainEffective.androidNdkCflags}"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-L native=${nativeDeps.xkbcommon}/lib -L native=${nativeDeps.libwayland}/lib -l xkbcommon -l wayland-client"
  '';

  buildPhase = ''
    runHook preBuild
    cargo build \
      --jobs "''${NIX_BUILD_CORES:-1}" \
      --offline \
      --profile release \
      --target aarch64-linux-android \
      --lib \
      --no-default-features \
      --features smithay-protocols
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    find target/aarch64-linux-android/release -name "libwawona*.a" -exec cp {} $out/lib/libwawona.a \;
    find target/aarch64-linux-android/release -name "libwawona*.so" -exec cp {} $out/lib/libwawona_core.so \;
    if [ ! -f $out/lib/libwawona.a ] && [ ! -f $out/lib/libwawona_core.so ]; then
      echo "No library found - checking target dir:"
      find target -name "*.a" -o -name "*.so" | head -20
      exit 1
    fi
  '';

  # The default fixup can run host archive tooling on target static archives,
  # which corrupts Android .a symbol table members for lld.
  dontFixup = true;

  meta.platforms = lib.platforms.all;
}
