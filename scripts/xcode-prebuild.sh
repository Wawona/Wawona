#!/usr/bin/env bash
# Realize Nix Rust (and optional zsh) archives for the active Xcode target/SDK.
# Symlinks into $DERIVED_FILE_DIR so OTHER_LDFLAGS paths exist before linking.
set -euo pipefail

derived="${DERIVED_FILE_DIR:?DERIVED_FILE_DIR is unset — is this script running as an Xcode build phase?}"
mkdir -p "$derived"

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
    _with_zsh=0
    ;;
  Wawona-iPadOS)
    BACKENDS=(wawona-ipados-backend wawona-ipados-sim-backend)
    _with_zsh=0
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
ln -sfn "$active_out/lib/libwawona.a" "$derived/libwawona.a"
echo "Linked $derived/libwawona.a -> $active_out/lib/libwawona.a"

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
for _dep in "${LINK_DEPS[@]}"; do
  echo "Realizing link-only dep: $_dep"
  "$NIX" build --no-link "${_nix_flags[@]}" "$FLAKE_REF#$_dep"
done

if [ "$_with_zsh" = "1" ]; then
  _zsh_attr="zsh-ios"
  case "$_sdk" in
    *simulator*) _zsh_attr="zsh-ios-sim" ;;
  esac
  zsh_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_zsh_attr")"
  ln -sfn "$zsh_out/lib/libwawona-zsh.a" "$derived/libwawona-zsh.a"
  echo "Linked $derived/libwawona-zsh.a -> $zsh_out/lib/libwawona-zsh.a"

  _nvim_attr="neovim-ios-device"
  case "$_sdk" in
    *simulator*) _nvim_attr="neovim-ios" ;;
  esac
  nvim_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_nvim_attr")"
  ln -sfn "$nvim_out/lib/libwawona-neovim.a" "$derived/libwawona-neovim.a"
  echo "Linked $derived/libwawona-neovim.a -> $nvim_out/lib/libwawona-neovim.a"

  _ff_attr="fastfetch-ios-device"
  case "$_sdk" in
    *simulator*) _ff_attr="fastfetch-ios" ;;
  esac
  ff_out="$("$NIX" build --no-link --print-out-paths "${_nix_flags[@]}" "$FLAKE_REF#$_ff_attr")"
  ln -sfn "$ff_out/lib/libfastfetch.a" "$derived/libfastfetch.a"
  echo "Linked $derived/libfastfetch.a -> $ff_out/lib/libfastfetch.a"
fi
