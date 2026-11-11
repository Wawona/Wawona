#!/usr/bin/env bash
# Build the Wawona Rust backend (libwawona) for one slice:
#   scripts/build-backend.sh <slice>
# slice: an Xcode PLATFORM_NAME (macosx, iphoneos, iphonesimulator, appletvos,
# appletvsimulator, xros, xrsimulator, watchos, watchsimulator),
# iphoneos-modeb, android or linux.
#
# dependencies/wawona/backend.nix runs this file with the environment it
# writes to $out/env. In a checkout the script reads that file from
# .deps/<slice>/backend/env (`nix run .#deps -- <slice>`), builds the working
# tree into target/, and stages .build/backend/<slice>, which
# scripts/xcode-prebuild.sh links instead of the Nix build until the next
# `nix run .#deps -- <slice>`.
set -euo pipefail

slice=${1:?usage: build-backend.sh <slice>}
root=${WWN_SRC:-$(cd "$(dirname "$0")/.." && pwd)}
if [ -z "${WWN_VENDOR:-}" ]; then
  envfile="$root/.deps/$slice/backend/env"
  [ -f "$envfile" ] || { echo "error: $envfile missing. Run: nix run .#deps -- $slice" >&2; exit 1; }
  # shellcheck source=/dev/null
  . "$envfile"
fi
out=${WWN_OUT:-$root/.build/backend/$slice}
export PATH="$PATH_PREPEND:$PATH"

min=$WWN_MIN_OS sim=
case $slice in
  macosx)           triple=aarch64-apple-darwin;       clang=arm64-apple-macos;   sdk=macosx;      dvar=MACOSX_DEPLOYMENT_TARGET ;;
  iphoneos|iphoneos-modeb)
                    triple=aarch64-apple-ios;          clang=arm64-apple-ios;     sdk=iphoneos;    dvar=IPHONEOS_DEPLOYMENT_TARGET ;;
  iphonesimulator)  triple=aarch64-apple-ios-sim;      clang=arm64-apple-ios;     sdk=$slice;      dvar=IPHONEOS_DEPLOYMENT_TARGET sim=-simulator ;;
  appletvos)        triple=aarch64-apple-tvos;         clang=arm64-apple-tvos;    sdk=$slice;      dvar=TVOS_DEPLOYMENT_TARGET ;;
  appletvsimulator) triple=aarch64-apple-tvos-sim;     clang=arm64-apple-tvos;    sdk=$slice;      dvar=TVOS_DEPLOYMENT_TARGET sim=-simulator ;;
  xros)             triple=aarch64-apple-visionos;     clang=arm64-apple-xros;    sdk=$slice;      dvar=XROS_DEPLOYMENT_TARGET ;;
  xrsimulator)      triple=aarch64-apple-visionos-sim; clang=arm64-apple-xros;    sdk=$slice;      dvar=XROS_DEPLOYMENT_TARGET sim=-simulator ;;
  watchos)          triple=aarch64-apple-watchos;      clang=arm64-apple-watchos; sdk=$slice;      dvar=WATCHOS_DEPLOYMENT_TARGET ;;
  watchsimulator)   triple=aarch64-apple-watchos-sim;  clang=arm64-apple-watchos; sdk=$slice;      dvar=WATCHOS_DEPLOYMENT_TARGET sim=-simulator ;;
  android)          triple=aarch64-linux-android ;;
  linux)            triple=$(rustc -vV | sed -n 's/^host: //p') ;;
  *) echo "error: unknown slice $slice" >&2; exit 1 ;;
esac
u=${triple//-/_}
U=$(tr '[:lower:]' '[:upper:]' <<<"$u")
# Apple-mobile archives are linked by Xcode; a cdylib would need every
# framework the app links.
case $slice in macosx|android|linux) types=staticlib,cdylib ;; *) types=staticlib ;; esac

cflags_var=CFLAGS_$u
cflags="${!cflags_var:-} $WWN_CFLAGS"
rustflags="${WWN_RUSTFLAGS:-}"
for d in $WWN_LIB_DIRS; do rustflags+=" -L native=$d"; done

if [ -n "${sdk:-}" ]; then
  # Xcode's SDKs, never the Nix stdenv's: its SDKROOT and DEVELOPER_DIR name
  # the macOS SDK it ships, and cc-rs passes them to the first xcrun on PATH.
  unset SDKROOT DEVELOPER_DIR
  mkdir -p "$root/target/wawona-xcrun"
  ln -sf /usr/bin/xcrun "$root/target/wawona-xcrun/xcrun"
  PATH="$root/target/wawona-xcrun:$PATH"
  sdkroot=$(/usr/bin/xcrun --sdk "$sdk" --show-sdk-path)
  cc=$(/usr/bin/xcrun --sdk "$sdk" -f clang)
  target="$clang$min$sim"
  export "$dvar=$min"
  export "CC_$u=$cc" "CARGO_TARGET_${U}_LINKER=$cc"
  cflags+=" -isysroot $sdkroot"
  rustflags+=" -C link-arg=-target -C link-arg=$target -C link-arg=-isysroot -C link-arg=$sdkroot"
  export "BINDGEN_EXTRA_CLANG_ARGS_$u=--target=$target -isysroot $sdkroot $WWN_CFLAGS"
else
  export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:-} $WWN_CFLAGS"
fi
export "CFLAGS_$u=$cflags" "CARGO_TARGET_${U}_RUSTFLAGS=$rustflags"

# Path crates the checkout does not carry (gitignored; Nix's are platform-patched).
for c in waypipe coreutils; do
  [ -e "$root/$c" ] || ln -s "$WWN_PATH_CRATES/$c" "$root/$c"
done

target_dir=$root/target
export CARGO_HOME=$target_dir/wawona-cargo-home CARGO_NET_OFFLINE=true
mkdir -p "$CARGO_HOME"
sed "s|\"cargo-vendor-dir\"|\"$WWN_VENDOR\"|" "$WWN_VENDOR/.cargo/config.toml" >"$CARGO_HOME/config.toml"

cd "$root"
cargo rustc --lib --crate-type "$types" --target "$triple" --target-dir "$target_dir" \
  --profile "$WWN_PROFILE" --locked --no-default-features --features "$WWN_FEATURES" \
  ${NIX_BUILD_CORES:+--jobs "$NIX_BUILD_CORES"}

built=$target_dir/$triple/$([ "$WWN_PROFILE" = dev ] && echo debug || echo "$WWN_PROFILE")
rm -rf "$out"
mkdir -p "$out/lib" "$out/uniffi/swift" "$out/uniffi/kotlin"
cp "$built/libwawona.a" "$out/lib/"
lib=$out/lib/libwawona.a
if [ -f "$built/libwawona.dylib" ]; then cp "$built/libwawona.dylib" "$out/lib/"; lib=$out/lib/libwawona.dylib; fi
if [ -f "$built/libwawona.so" ]; then cp "$built/libwawona.so" "$out/lib/libwawona_core.so"; lib=$out/lib/libwawona_core.so; fi
case $slice in android) langs=kotlin ;; linux) langs="swift kotlin" ;; *) langs=swift ;; esac
for lang in $langs; do
  "$WWN_UNIFFI_BINDGEN" generate --library "$lib" --language "$lang" --out-dir "$out/uniffi/$lang" \
    || echo "warning: uniffi $lang bindings not generated from $lib" >&2
done
[ -n "${WWN_OUT:-}" ] || echo "Built $out. Xcode links it until: nix run .#deps -- $slice"
