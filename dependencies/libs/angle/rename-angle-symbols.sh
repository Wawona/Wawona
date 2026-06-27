#!/usr/bin/env bash
# Rename public ANGLE EGL entry points so iland's ILAND_ANGLE_STATIC wrappers can
# link without duplicate _egl* symbols (iland exports egl*; ANGLE becomes angle_*).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <input-lib> <output-lib>" >&2
  exit 1
fi

in="$1"
out="$2"

OBJCOPY="${LLVM_OBJCOPY:-llvm-objcopy}"
if ! command -v "$OBJCOPY" >/dev/null 2>&1; then
  OBJCOPY="$(xcrun --find llvm-objcopy 2>/dev/null || true)"
fi
if [ -z "$OBJCOPY" ] || ! command -v "$OBJCOPY" >/dev/null 2>&1; then
  echo "ERROR: llvm-objcopy not found (set LLVM_OBJCOPY)" >&2
  exit 1
fi

cp "$in" "$out"

SYMS=(
  eglGetDisplay eglInitialize eglTerminate eglGetError eglQueryString
  eglGetConfigs eglChooseConfig eglGetConfigAttrib eglCreateContext
  eglDestroyContext eglCreateWindowSurface eglDestroySurface eglMakeCurrent
  eglSwapBuffers eglBindAPI eglWaitGL eglSwapInterval eglCreatePbufferSurface
  eglCreatePbufferFromClientBuffer eglGetCurrentContext
)

args=()
for sym in "${SYMS[@]}"; do
  args+=(--redefine-sym "_${sym}=_angle_${sym}")
done

"$OBJCOPY" "${args[@]}" "$out"
