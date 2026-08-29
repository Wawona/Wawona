#!/usr/bin/env bash
# Pin host Xcode for GitHub Actions macOS runners (impure Apple builds).
#
# Default pin matches the macos-26 image used in CI. Override for local repro:
#   WAWONA_XCODE_APP=/Applications/Xcode_26.6.0.app
#   WAWONA_XCODE_VERSION=26.6.0   # resolves to /Applications/Xcode_${VERSION}.app
#
# Bumping the pin is a deliberate PR. Silent "newest Xcode" churn invalidates
# impure weston/backend/product hashes. See docs/ci.md.
set -euo pipefail

# CI pin (macos-26 image, Xcode 26.6 / 17F113 as of 2026-07).
DEFAULT_XCODE_APP="/Applications/Xcode_26.6.0.app"

resolve_xcode_app() {
  if [[ -n "${WAWONA_XCODE_APP:-}" ]]; then
    printf '%s\n' "$WAWONA_XCODE_APP"
    return 0
  fi
  if [[ -n "${WAWONA_XCODE_VERSION:-}" ]]; then
    printf '/Applications/Xcode_%s.app\n' "$WAWONA_XCODE_VERSION"
    return 0
  fi
  printf '%s\n' "$DEFAULT_XCODE_APP"
}

XCODE_APP="$(resolve_xcode_app)"

if [[ ! -d "$XCODE_APP" ]]; then
  echo "::error::Pinned Xcode not found: $XCODE_APP" >&2
  echo "Installed under /Applications:" >&2
  ls -d /Applications/Xcode*.app 2>/dev/null >&2 || echo "(none)" >&2
  echo "Override with WAWONA_XCODE_APP or WAWONA_XCODE_VERSION, or bump the pin in select-xcode.sh." >&2
  exit 1
fi

# Resolve symlinks (runner images often symlink Xcode_26.6.0.app -> RC bundle).
XCODE_APP="$(cd "$XCODE_APP" && pwd -P)"

sudo xcode-select -s "$XCODE_APP"
DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "::error::xcodebuild missing under $DEVELOPER_DIR" >&2
  exit 1
fi

echo "Selected Xcode (pinned): $XCODE_APP"
# Capture once. Piping a live xcodebuild into awk can SIGPIPE/abort on
# Xcode 26 ("Broken pipe" / NSFileHandleOperationException).
XCODE_VERSION_OUT="$("$DEVELOPER_DIR/usr/bin/xcodebuild" -version)"
printf '%s\n' "$XCODE_VERSION_OUT"
XCODE_VER="$(printf '%s\n' "$XCODE_VERSION_OUT" | awk '/Xcode/{print $2; exit}')"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "DEVELOPER_DIR=$DEVELOPER_DIR"
    echo "XCODE_APP=$XCODE_APP"
    echo "PATH=$DEVELOPER_DIR/usr/bin:$PATH"
    echo "TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault"
  } >> "$GITHUB_ENV"
else
  export DEVELOPER_DIR XCODE_APP
  export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
  export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$XCODE_VER"
    echo "developer_dir=$DEVELOPER_DIR"
    echo "xcode_app=$XCODE_APP"
  } >> "$GITHUB_OUTPUT"
fi
