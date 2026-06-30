#!/usr/bin/env bash
# Select the newest Xcode on GitHub Actions macOS runners and export paths for
# fastlane, xcodebuild, and Nix impure Apple builds.
set -euo pipefail

XCODE_APP=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)
if [ -z "${XCODE_APP:-}" ]; then
  echo "::error::No Xcode installation found on this runner" >&2
  ls /Applications/ >&2 || true
  exit 1
fi

sudo xcode-select -s "$XCODE_APP"
DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
  echo "::error::xcodebuild missing under $DEVELOPER_DIR" >&2
  exit 1
fi

echo "Selected Xcode: $XCODE_APP"
"$DEVELOPER_DIR/usr/bin/xcodebuild" -version

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "DEVELOPER_DIR=$DEVELOPER_DIR"
    echo "XCODE_APP=$XCODE_APP"
    echo "PATH=$DEVELOPER_DIR/usr/bin:$PATH"
  } >> "$GITHUB_ENV"
else
  export DEVELOPER_DIR XCODE_APP
  export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
fi
