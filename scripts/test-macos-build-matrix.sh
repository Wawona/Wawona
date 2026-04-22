#!/usr/bin/env bash
set -euo pipefail

# Compile-validation matrix for Apple-family targets from a macOS host.
# This script intentionally uses `nix build` to validate compilation output
# without launching simulator/device runners.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS hosts." >&2
  exit 1
fi

targets=(
  ".#wawona-macos"
  ".#wawona-ios"
  ".#wawona-ipados"
  ".#wawona-tvos"
  ".#wawona-watchos"
  ".#wawona-visionos"
  ".#wawona-ios-app-sim"
  ".#wawona-ios-app-device"
  ".#wawona-ipados-app-sim"
  ".#wawona-ipados-app-device"
  ".#wawona-tvos-app-sim"
  ".#wawona-tvos-app-device"
  ".#wawona-watchos-app-sim"
  ".#wawona-watchos-app-device"
  ".#wawona-visionos-app-sim"
  ".#wawona-ios-backend"
  ".#wawona-ios-sim-backend"
  ".#wawona-ipados-backend"
  ".#wawona-ipados-sim-backend"
  ".#wawona-tvos-backend"
  ".#wawona-tvos-sim-backend"
  ".#wawona-watchos-backend"
  ".#wawona-watchos-sim-backend"
  ".#wawona-visionos-backend"
  ".#wawona-visionos-sim-backend"
  ".#wawona-macos-backend"
)

echo "[wawona] Validating macOS-host target compilation matrix..."
for target in "${targets[@]}"; do
  echo "  - building ${target}"
  nix build --print-build-logs "${target}"
done

echo "[wawona] macOS-host compile matrix passed."
