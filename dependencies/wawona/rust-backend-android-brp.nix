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
  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchainEffective.androidCC} \
      --target=${androidToolchainEffective.androidTarget} \
      --sysroot=${NDK_SYSROOT} \
      -L${NDK_LIB_PATH} \
      -L${NDK_SYSROOT}/usr/lib/aarch64-linux-android \
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
  pname = "wawona-android-backend";
  version = wawonaVersion;

  src = workspaceSrc;

  cargoLock = {
    lockFile = workspaceSrc + "/Cargo.lock";
  };

  cargoBuildFlags = [
    "--target" "aarch64-linux-android"
    "--lib"
    "--no-default-features"
  ];
  cargoTestFlags = cargoBuildFlags;
  doCheck = false;

  CARGO_BUILD_TARGET = "aarch64-linux-android";
  CC_aarch64_linux_android = "${androidToolchainEffective.androidCC}";
  CXX_aarch64_linux_android = androidToolchainEffective.androidCXX;
  AR_aarch64_linux_android = androidToolchainEffective.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";
  WAWONA_ANDROID_XKBCOMMON_LIBDIR = "${nativeDeps.xkbcommon}/lib";

  buildInputs = lib.filter (x: x != null) [
    pkgs.libxkbcommon
    (nativeDeps.xkbcommon or null)
    (nativeDeps.libwayland or null)
    (nativeDeps.zstd or null)
    (nativeDeps.lz4 or null)
    (nativeDeps.pixman or null)
    (nativeDeps.openssl or null)
    (nativeDeps.libffi or null)
    (nativeDeps.expat or null)
    (nativeDeps.libxml2 or null)
    (nativeDeps.ffmpeg or null)
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
    export PKG_CONFIG_PATH="${lib.concatStringsSep ":" (
      lib.optional (nativeDeps ? libwayland) "${nativeDeps.libwayland}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? xkbcommon) "${nativeDeps.xkbcommon}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? openssl) "${nativeDeps.openssl}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? zstd) "${nativeDeps.zstd}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? lz4) "${nativeDeps.lz4}/lib/pkgconfig"
      ++ lib.optional (nativeDeps ? ffmpeg) "${nativeDeps.ffmpeg}/lib/pkgconfig"
    )}:$PKG_CONFIG_PATH"
    export LIBRARY_PATH="${lib.concatStringsSep ":" (
      lib.optional (nativeDeps ? xkbcommon) "${nativeDeps.xkbcommon}/lib"
      ++ lib.optional (nativeDeps ? zstd) "${nativeDeps.zstd}/lib"
      ++ lib.optional (nativeDeps ? lz4) "${nativeDeps.lz4}/lib"
      ++ lib.optional (nativeDeps ? ffmpeg) "${nativeDeps.ffmpeg}/lib"
    )}:$LIBRARY_PATH"
    export C_INCLUDE_PATH="${lib.concatStringsSep ":" (
      lib.optional (nativeDeps ? zstd) "${nativeDeps.zstd}/include"
      ++ lib.optional (nativeDeps ? lz4) "${nativeDeps.lz4}/include"
      ++ lib.optional (nativeDeps ? ffmpeg) "${nativeDeps.ffmpeg}/include"
    )}:$C_INCLUDE_PATH"
    export CRATE_CC_NO_DEFAULTS=1
    export CFLAGS_aarch64_linux_android="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
    export CXXFLAGS_aarch64_linux_android="--target=${androidToolchainEffective.androidTarget} --sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android -fPIC ${androidToolchainEffective.androidNdkCflags}"
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=${NDK_SYSROOT} -isystem ${NDK_SYSROOT}/usr/include -isystem ${NDK_SYSROOT}/usr/include/aarch64-linux-android --target=${androidToolchainEffective.androidTarget} ${androidToolchainEffective.androidNdkCflags}"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-L native=${nativeDeps.xkbcommon}/lib -l xkbcommon"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${nativeDeps.xkbcommon}/lib -lxkbcommon"
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    find target/aarch64-linux-android/release -name "libwawona*.a" -exec cp {} $out/lib/libwawona.a \;
    find target/aarch64-linux-android/release -name "libwawona*.so" -exec cp {} $out/lib/libwawona_core.so \;
    if [ -f "$out/lib/libwawona.a" ]; then
      # Repack with Android llvm-ar so lld accepts the archive members.
      repack_dir="$(mktemp -d)"
      cp "$out/lib/libwawona.a" "$repack_dir/original.a"
      (cd "$repack_dir" && "${androidToolchainEffective.androidAR}" x original.a)
      rm -f "$out/lib/libwawona.a"
      (cd "$repack_dir" && "${androidToolchainEffective.androidAR}" qc libwawona.a ./*.o)
      "${androidToolchainEffective.androidRANLIB}" "$repack_dir/libwawona.a"
      cp "$repack_dir/libwawona.a" "$out/lib/libwawona.a"
    fi
    if [ ! -f $out/lib/libwawona.a ] && [ ! -f $out/lib/libwawona_core.so ]; then
      echo "No library found - checking target dir:"
      find target -name "*.a" -o -name "*.so" | head -20
      exit 1
    fi
  '';

  meta.platforms = lib.platforms.all;
}
