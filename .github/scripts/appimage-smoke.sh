#!/usr/bin/env bash
# AppImage sanity gate: validate that the built artifact is a real type-2
# AppImage (ELF + "AI\x02" magic), stage it under dist/ with a stable,
# arch-tagged name for artifact upload, and attempt a FUSE-free
# --appimage-extract to confirm the embedded squashfs + AppRun + entrypoint
# are intact. The extract step is best-effort (runners may lack the kernel
# bits some runtimes want); the magic/size checks are authoritative.
set -euo pipefail

RESULT_LINK="${1:?usage: appimage-smoke.sh <result-symlink> <system>}"
SYSTEM="${2:?usage: appimage-smoke.sh <result-symlink> <system>}"

APPIMAGE="$(readlink -f "$RESULT_LINK")"
if [ ! -f "$APPIMAGE" ]; then
  echo "::error::AppImage not found at $RESULT_LINK -> $APPIMAGE"
  exit 1
fi

SIZE="$(stat -c%s "$APPIMAGE")"
echo "AppImage: $APPIMAGE (${SIZE} bytes)"
if [ "$SIZE" -lt 1000000 ]; then
  echo "::error::AppImage suspiciously small (${SIZE} bytes)"
  exit 1
fi

# Type-2 AppImage: ELF header (7f454c46) with magic bytes AI\x02 at offset 8.
ELF_MAGIC="$(dd if="$APPIMAGE" bs=1 count=4 2>/dev/null | xxd -p)"
AI_MAGIC="$(dd if="$APPIMAGE" bs=1 skip=8 count=3 2>/dev/null | xxd -p)"
echo "ELF magic=${ELF_MAGIC} AppImage magic=${AI_MAGIC}"
if [ "$ELF_MAGIC" != "7f454c46" ]; then
  echo "::error::Not an ELF executable (magic=${ELF_MAGIC})"
  exit 1
fi
if [ "$AI_MAGIC" != "414902" ]; then
  echo "::error::Not a type-2 AppImage (magic=${AI_MAGIC}, expected 414902)"
  exit 1
fi

# Product-build / Gate keep a short unversioned name. Ship: GitHub assets
# renames to Wawona-{calver}-Linux-{arch}.AppImage in release.yml (aarch64→arm64).
ARCH="${SYSTEM%%-*}"
mkdir -p dist
DEST="dist/Wawona-${ARCH}.AppImage"
cp "$APPIMAGE" "$DEST"
chmod +x "$DEST"
echo "Staged $DEST (ship boundary renames to CalVer+platform+arch)"

# Best-effort FUSE-free extraction sanity. The type-2 runtime self-extracts
# without FUSE; if the runner blocks even that, don't fail the gate.
WORK="$(mktemp -d)"
if ( cd "$WORK" && "$DEST" --appimage-extract >/dev/null 2>&1 ); then
  if [ -x "$WORK/squashfs-root/AppRun" ] && [ -e "$WORK/squashfs-root/entrypoint" ]; then
    echo "AppImage extract OK: AppRun + entrypoint present"
  else
    echo "::warning::AppImage extracted but AppRun/entrypoint missing"
  fi
else
  echo "::warning::--appimage-extract unavailable on this runner; relying on magic/size checks"
fi
rm -rf "$WORK"

echo "AppImage smoke passed for ${SYSTEM}"
