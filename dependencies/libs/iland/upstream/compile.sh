#!/bin/bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

cmake -B "$BUILD_DIR" -S .
cmake --build "$BUILD_DIR" --parallel "$JOBS" "$@"
