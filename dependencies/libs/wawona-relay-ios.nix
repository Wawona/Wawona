# iOS / Apple-mobile C ABI staticlib for Relay.
# Locked github Relay/recipes/relay-staticlib.nix is still host rustPlatform
# (macOS libwawona_relay.dylib). L4 builds the same L3' source with the
# cross recipe until Relay/development ships it. Cited: wawona-relay-wasm.
{
  pkgs,
  lib ? pkgs.lib,
  iosToolchain,
  src,
  simulator ? false,
}:

let
  isWatchOS = iosToolchain.isWatchOSToolchain or false;
  isTVOS = iosToolchain.isTVOSToolchain or false;
  isVisionOS = iosToolchain.isVisionOSToolchain or false;

  cargoTarget =
    if isWatchOS then
      (if simulator then "aarch64-apple-watchos-sim" else "aarch64-apple-watchos")
    else if isTVOS then
      (if simulator then "aarch64-apple-tvos-sim" else "aarch64-apple-tvos")
    else if isVisionOS then
      (if simulator then "aarch64-apple-visionos-sim" else "aarch64-apple-visionos")
    else if simulator then
      "aarch64-apple-ios-sim"
    else
      "aarch64-apple-ios";

  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ cargoTarget ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  srcFilter = path: type:
    let b = baseNameOf path;
    in !(b == "target" || b == ".git" || b == "import" || b == ".direnv");
in
rustPlatform.buildRustPackage {
  pname = "wawona-relay";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = src;
    filter = srcFilter;
  };
  cargoLock.lockFile = src + "/Cargo.lock";
  doCheck = false;
  cargoBuildFlags = [ "-p" "relay-ffi" ];
  CARGO_BUILD_TARGET = cargoTarget;
  cargoBuildTarget = cargoTarget;
  dontCargoInstall = true;
  buildPhase = ''
    runHook preBuild
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"
    cargo rustc \
      --jobs "''${NIX_BUILD_CORES}" \
      --offline \
      --release \
      --target ${cargoTarget} \
      -p relay-ffi \
      -- \
      --crate-type staticlib
  '';
  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"
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
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/include $out/lib
    cp crates/relay-ffi/include/wawona_relay.h $out/include/
    if [ -f target/${cargoTarget}/release/libwawona_relay.a ]; then
      cp target/${cargoTarget}/release/libwawona_relay.a $out/lib/
    else
      echo "ERROR: libwawona_relay.a not found" >&2
      find target -name 'libwawona_relay*' >&2 || true
      exit 1
    fi
    rm -f $out/lib/libwawona_relay.dylib $out/lib/libwawona_relay.so
    runHook postInstall
  '';
}
