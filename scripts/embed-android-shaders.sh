#!/usr/bin/env bash
# Embed Android Vulkan shaders as C byte arrays for compilation into libwawona.so
# Usage: ./embed-android-shaders.sh <srcdir> <outdir>
# Compiles src/platform/android/rendering/shaders/android_quad.vert and .frag to SPIR-V,
# then generates shader_spv.h with unsigned char arrays.

set -e
SRCDIR="${1:-.}"
OUTDIR="${2:-.}"

# Prefer glslc (from glslang package), fallback to glslangValidator
GLSLC=""
if command -v glslc >/dev/null 2>&1; then
  GLSLC="glslc"
elif command -v glslangValidator >/dev/null 2>&1; then
  # glslangValidator -V compiles to SPIR-V
  GLSLC="glslangValidator"
elif [ -n "$NIX_GLSLANG_BIN" ] && [ -x "${NIX_GLSLANG_BIN}/glslc" ]; then
  GLSLC="${NIX_GLSLANG_BIN}/glslc"
elif [ -n "$NIX_GLSLANG_BIN" ] && [ -x "${NIX_GLSLANG_BIN}/glslangValidator" ]; then
  GLSLC="${NIX_GLSLANG_BIN}/glslangValidator"
fi

if [ -z "$GLSLC" ]; then
  echo "ERROR: glslc or glslangValidator not found. Install glslang (nix: pkgs.glslang)." >&2
  exit 1
fi

mkdir -p "$OUTDIR"
VERT_SPV="$OUTDIR/quad.vert.spv"
FRAG_SPV="$OUTDIR/quad.frag.spv"

if [ "$GLSLC" = "glslangValidator" ] || [[ "$GLSLC" == *"glslangValidator" ]]; then
  "$GLSLC" -V "$SRCDIR/src/platform/android/rendering/shaders/android_quad.vert" -o "$VERT_SPV"
  "$GLSLC" -V "$SRCDIR/src/platform/android/rendering/shaders/android_quad.frag" -o "$FRAG_SPV"
else
  "$GLSLC" "$SRCDIR/src/platform/android/rendering/shaders/android_quad.vert" -o "$VERT_SPV"
  "$GLSLC" "$SRCDIR/src/platform/android/rendering/shaders/android_quad.frag" -o "$FRAG_SPV"
fi

# Generate C header with byte arrays
cat > "$OUTDIR/shader_spv.h" << 'HEADER'
/* Auto-generated - do not edit */
#pragma once

#include <stddef.h>
#include <stdint.h>

HEADER

# Generate hex bytes for C array (works on Linux and macOS)
embed_hex() {
  if command -v xxd >/dev/null 2>&1; then
    # xxd -i: skip "unsigned char X[] = {" line and "};" line
    xxd -i -c 12 "$1" | sed '1d;$d' | sed 's/^/  /'
  else
    od -A n -t x1 -v "$1" | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i} END {print ""}' | sed 's/,$//'
  fi
}

{
  echo "static const unsigned char g_quad_vert_spv[] = {"
  embed_hex "$VERT_SPV"
  echo "};"
  echo "static const size_t g_quad_vert_spv_len = sizeof(g_quad_vert_spv);"
  echo ""
  echo "static const unsigned char g_quad_frag_spv[] = {"
  embed_hex "$FRAG_SPV"
  echo "};"
  echo "static const size_t g_quad_frag_spv_len = sizeof(g_quad_frag_spv);"
} >> "$OUTDIR/shader_spv.h"

echo "Embedded shaders: $VERT_SPV ($(wc -c < "$VERT_SPV") bytes), $FRAG_SPV ($(wc -c < "$FRAG_SPV") bytes)"
