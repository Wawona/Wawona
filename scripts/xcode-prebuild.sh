#!/usr/bin/env bash
# Realize Nix Rust (and optional zsh) archives for the active Xcode target/SDK.
# Copies into $DERIVED_FILE_DIR so OTHER_LDFLAGS paths exist before linking.
# Static archives that carry colliding internal symbols (zsh, neovim, openssh)
# are privatised via nmedit so only the public dispatch entry points remain
# globally visible.  This avoids duplicate-symbol linker errors without
# resorting to -multiply_defined,suppress (unsupported by ld-prime) or dylibs
# (App Store non-compliant).
set -euo pipefail

# xcodebuild script phases reset HOME to the build user's pw_dir (/var/empty for
# nixbld). Nested `nix` then dies creating /var/empty/.cache. Relocate early.
if [ -z "${HOME:-}" ] || [ "$HOME" = "/var/empty" ] || [ ! -w "$HOME" ]; then
  HOME="${NIX_BUILD_TOP:-${TMPDIR:-/tmp}}/wawona-xcode-home"
  export HOME
  mkdir -p "$HOME"
fi
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

derived="${DERIVED_FILE_DIR:?DERIVED_FILE_DIR is unset — is this script running as an Xcode build phase?}"
mkdir -p "$derived"

# Local getprogname/setprogname for Apple mobile — force-loaded before weston /
# fontconfig so App Store Connect never sees libSystem's private ___progname.
case "${PLATFORM_NAME:-}" in
  iphoneos|iphonesimulator|appletvos|appletvsimulator|xros|xrsimulator)
    _stub_src="${SRCROOT:?}/src/platform/ios/WWNGetprognameStub.c"
    _stub_a="$derived/libwawona-getprogname.a"
    _stub_o="$derived/wawona-getprogname.o"
    _sdkroot="${SDKROOT:-$(xcrun --sdk "${PLATFORM_NAME}" --show-sdk-path)}"
    _arch="${ARCHS%% *}"
    _arch="${_arch:-arm64}"
    # No -m*-version-min: visionOS clang rejects -mxros-version-min, and this
    # stub has no SDK API surface that needs a deployment floor.
    xcrun --sdk "${PLATFORM_NAME}" clang -c "$_stub_src" \
      -isysroot "$_sdkroot" -arch "$_arch" \
      -fPIC -O2 -o "$_stub_o"
    xcrun --sdk "${PLATFORM_NAME}" libtool -static -o "$_stub_a" "$_stub_o"
    echo "Built $_stub_a (getprogname stub for App Store)"
    ;;
esac

wwn_find_nix() {
  if [ -n "${WAWONA_NIX:-}" ] && [ -x "${WAWONA_NIX}" ]; then
    echo "${WAWONA_NIX}"
    return 0
  fi
  if command -v nix >/dev/null 2>&1; then
    command -v nix
    return 0
  fi
  local candidate profile
  for candidate in \
    "${HOME}/.nix-profile/bin/nix" \
    "/nix/var/nix/profiles/default/bin/nix" \
    "/run/current-system/sw/bin/nix" \
    "/usr/local/bin/nix"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  for profile in \
    "${HOME}/.nix-profile/etc/profile.d/nix.sh" \
    "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" \
    "/etc/profile.d/nix.sh"; do
    if [ -f "$profile" ]; then
      # shellcheck disable=SC1090
      . "$profile"
      if command -v nix >/dev/null 2>&1; then
        command -v nix
        return 0
      fi
    fi
  done
  return 1
}

NIX="$(wwn_find_nix || true)"
if [ -z "$NIX" ]; then
  echo "error: nix not found. Run 'nix run .#xcodegen-ios' from the repo, then open Wawona.xcodeproj and build again." >&2
  echo "       Or launch Xcode from a shell where 'nix' works (e.g. 'nix develop')." >&2
  exit 1
fi

if [ "${WAWONA_SKIP_NIX_PREBUILD:-0}" = "1" ]; then
  echo "WAWONA_SKIP_NIX_PREBUILD=1; skipping Nix prebuild"
  exit 0
fi

FLAKE_REF="."
if [ -f "${SRCROOT:-.}/crates/Wawona/flake.nix" ]; then
  FLAKE_REF="${SRCROOT}/crates/Wawona"
elif [ -f "${SRCROOT:-.}/flake.nix" ]; then
  FLAKE_REF="${SRCROOT:-.}"
fi

_sdk="${PLATFORM_NAME:-}"
if [ -z "$_sdk" ] && [ -n "${SDKROOT:-}" ]; then
  _sdk="$(basename "$SDKROOT" .sdk)"
fi

_is_sim=0
case "$_sdk" in
  *simulator*) _is_sim=1 ;;
esac

_with_zsh=0
case "${TARGET_NAME:-}" in
  Wawona-iOS)
    BACKENDS=(wawona-ios-backend wawona-ios-sim-backend)
    _with_zsh=1
    ;;
  Wawona-iPadOS)
    BACKENDS=(wawona-ipados-backend wawona-ipados-sim-backend)
    _with_zsh=1
    ;;
  Wawona-macOS)
    BACKENDS=(wawona-macos-backend)
    ;;
  Wawona-tvOS)
    BACKENDS=(wawona-tvos-backend wawona-tvos-sim-backend)
    ;;
  Wawona-visionOS)
    BACKENDS=(wawona-visionos-backend wawona-visionos-sim-backend)
    ;;
  Wawona-watchOS)
    BACKENDS=(wawona-watchos-backend wawona-watchos-sim-backend)
    ;;
  *)
    echo "Unknown TARGET_NAME=${TARGET_NAME:-}; skipping Nix prebuild"
    exit 0
    ;;
esac

if [ "$_is_sim" = "1" ] && [ "${#BACKENDS[@]}" -ge 2 ]; then
  _active_backend="${BACKENDS[1]}"
else
  _active_backend="${BACKENDS[0]}"
fi

echo "Realizing Nix backend(s) for ${TARGET_NAME} (sdk=${_sdk:-unknown}, active=${_active_backend}, nix=$NIX)"

# By default, build only the active backend matching the current SDK.
# Set WAWONA_WARM_BOTH_BACKENDS=1 for release builds that need both.
build_args=()
if [ "${WAWONA_WARM_BOTH_BACKENDS:-0}" = "1" ]; then
  for backend in "${BACKENDS[@]}"; do
    build_args+=("$FLAKE_REF#$backend")
  done
else
  build_args+=("$FLAKE_REF#$_active_backend")
fi
_nix_flags=(--impure)
if [ -n "${WAWONA_NIX_FLAGS:-}" ]; then
  # shellcheck disable=SC2206
  _nix_flags+=(${WAWONA_NIX_FLAGS})
fi
"$NIX" build --no-link "${_nix_flags[@]}" "${build_args[@]}"

active_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_active_backend")"
# Copy (don't symlink): auto-GC can delete the store path between this script
# exiting and the final link step, leaving a dangling symlink that fails clang.
rm -f "$derived/libwawona.a"
cp -f "$active_out/lib/libwawona.a" "$derived/libwawona.a"
echo "Copied $derived/libwawona.a <- $active_out/lib/libwawona.a"

# Realize link-only native deps that the app links by absolute /nix/store path
# (OTHER_LDFLAGS), but that are NOT in the Rust backend's build closure. These
# impure (__noChroot) derivations are not in the binary cache, so unless they
# are built here the linker fails with "Library not found" (e.g. kmscube-macos).
LINK_DEPS=()
case "${TARGET_NAME:-}" in
  Wawona-macOS)
    LINK_DEPS=(kmscube)
    ;;
esac
for _dep in "${LINK_DEPS[@]:-}"; do
  echo "Realizing link-only dep: $_dep"
  "$NIX" build --no-link "${_nix_flags[@]}" "$FLAKE_REF#$_dep"
done

# ---------------------------------------------------------------------------
# privatize_lib — merge a static archive into a single relocatable .o, strip
# all global symbols except the listed exports, and repackage as .a.
# This prevents duplicate-symbol collisions when linking multiple UNIX
# toolchains (zsh, neovim, openssh) into a single iOS binary.
#
# Usage: privatize_lib <src.a> <dst.a> <arch> <platform> <min_ver> <export_sym> [<export_sym> ...]
# ---------------------------------------------------------------------------
privatize_lib() {
  local src="$1" dst="$2" arch="$3" platform="$4" min_ver="$5"
  shift 5

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local merged_o="$tmp_dir/merged.o"
  local exports="$tmp_dir/exports.txt"

  for sym in "$@"; do
    echo "$sym" >> "$exports"
  done

  # Merge every .o in the archive into a single relocatable
  ld -r -arch "$arch" -platform_version "$platform" "$min_ver" "$min_ver" \
    -all_load "$src" -o "$merged_o" 2>/dev/null || \
  ld -r -arch "$arch" -platform_version "$platform" "$min_ver" "$min_ver" \
    -all_load "$src" -o "$merged_o"

  # Make everything private except the public API
  nmedit -s "$exports" "$merged_o"

  # Repackage
  libtool -static "$merged_o" -o "$dst"

  rm -rf "$tmp_dir"
  echo "Privatized $(basename "$src") -> $(basename "$dst") (exports: $*)"
}

# ---------------------------------------------------------------------------
# Determine arch and platform for ld -r / nmedit
# ---------------------------------------------------------------------------
_arch="arm64"
_ld_platform="ios"
_min_ver="17.0"
case "$_sdk" in
  iphonesimulator*)
    _ld_platform="ios-simulator"
    ;;
  iphoneos*)
    _ld_platform="ios"
    ;;
  *)
    _ld_platform="ios"
    ;;
esac

if [ "$_with_zsh" = "1" ]; then
  _zsh_attr="zsh-ios"
  case "$_sdk" in
    *simulator*) _zsh_attr="zsh-ios-sim" ;;
  esac
  zsh_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_zsh_attr")"
  privatize_lib "$zsh_out/lib/libwawona-zsh.a" "$derived/libwawona-zsh.a" \
    "$_arch" "$_ld_platform" "$_min_ver" \
    _wawona_zsh_main
  echo "Privatized $derived/libwawona-zsh.a (from $zsh_out)"

  _nvim_attr="neovim-ios-device"
  case "$_sdk" in
    *simulator*) _nvim_attr="neovim-ios" ;;
  esac
  nvim_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_nvim_attr")"
  privatize_lib "$nvim_out/lib/libwawona-neovim.a" "$derived/libwawona-neovim.a" \
    "$_arch" "$_ld_platform" "$_min_ver" \
    _wawona_nvim_main
  echo "Privatized $derived/libwawona-neovim.a (from $nvim_out)"

  _ff_attr="fastfetch-ios-device"
  case "$_sdk" in
    *simulator*) _ff_attr="fastfetch-ios" ;;
  esac
  ff_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_ff_attr")"
  privatize_lib "$ff_out/lib/libfastfetch.a" "$derived/libfastfetch.a" \
    "$_arch" "$_ld_platform" "$_min_ver" \
    _fastfetch_main
  echo "Privatized $derived/libfastfetch.a (from $ff_out)"

  # openssh: privatize libssh-inprocess.a to avoid collisions with libssh2 and
  # neovim (_chachapoly_*, _xmalloc, _xcalloc, _log_init, _match_user, etc.)
  _ssh_attr="openssh-ios"
  case "$_sdk" in
    *simulator*) _ssh_attr="openssh-ios-sim" ;;
  esac
  if ssh_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_ssh_attr" 2>/dev/null)" \
     && [ -f "$ssh_out/lib/libssh-inprocess.a" ]; then
    privatize_lib "$ssh_out/lib/libssh-inprocess.a" "$derived/libssh-inprocess.a" \
      "$_arch" "$_ld_platform" "$_min_ver" \
      _ssh_main _ssh_keygen_main _scp_main _wwn_openssh_keygen_real_main
    echo "Privatized $derived/libssh-inprocess.a (from $ssh_out)"
  else
    echo "error: failed to realize $FLAKE_REF#$_ssh_attr (libssh-inprocess.a required for iOS link)" >&2
    exit 1
  fi
fi
