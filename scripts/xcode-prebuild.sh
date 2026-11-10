#!/usr/bin/env bash
# Stage what the link step reads from $DERIVED_FILE_DIR, out of the
# .deps/<sdk> slice `nix run .#deps -- <sdk>` linked: libwawona.a, and on
# Apple mobile zsh and fastfetch with every symbol but their entry point made
# private. Those archives collide with each other and with OpenSSH; ld-prime
# has no -multiply_defined suppress and a dylib is not App Store compliant.
set -euo pipefail

bash "$SRCROOT/.github/scripts/verify-calver-today.sh"

derived=${DERIVED_FILE_DIR:?run this as an Xcode build phase}
slice=$PLATFORM_NAME
if [ "$TARGET_NAME" = Wawona-iOS-ModeB ] && [ "$slice" = iphoneos ]; then
  slice=iphoneos-modeb
fi
deps="$SRCROOT/.deps/$slice"
if [ ! -d "$deps" ]; then
  echo "error: $deps is missing. Run: nix run .#deps -- $slice" >&2
  exit 1
fi
mkdir -p "$derived"
# Copy, never link: the store path can be collected before the link step.
cp -f "$deps/backend/lib/libwawona.a" "$derived/libwawona.a"

if [ "$slice" = macosx ]; then
  # TerminalMetalPresent paints unless WAWONA_LINK_LIBGHOSTTY=1 and
  # `nix run .#deps -- libghostty-macos` staged Zig GhosttyLib. Bridge.c reads
  # the define from a header because a DERIVED_FILE_DIR xcconfig is read too
  # late; the link flags go under .build/, which wwn-version.xcconfig includes.
  lg="$SRCROOT/.deps/libghostty-macos"
  mkdir -p "$SRCROOT/.build"
  if [ "${WAWONA_LINK_LIBGHOSTTY:-0}" = 1 ] && [ -f "$lg/lib/libghostty-internal.a" ]; then
    cp -f "$lg/include/ghostty.h" "$derived/ghostty.h"
    printf '#define WAWONA_HAS_LIBGHOSTTY 1\n#define GHOSTTY_STATIC 1\n' >"$derived/wwn_ghostty_host_config.h"
    {
      echo "HEADER_SEARCH_PATHS = \$(inherited) $lg/include"
      echo "OTHER_LDFLAGS = \$(inherited) -force_load $lg/lib/libghostty-internal.a -lc++ -lz -lbz2 -framework Metal -framework MetalKit -framework QuartzCore -framework CoreText -framework CoreGraphics -framework CoreVideo -framework CoreImage -framework IOKit -framework Security -framework UniformTypeIdentifiers -framework Carbon -framework GameController -framework IOSurface -framework SystemConfiguration -framework Network"
    } | tee "$derived/wwn-libghostty-link.xcconfig" >"$SRCROOT/.build/wwn-libghostty-link.xcconfig"
  else
    : >"$derived/wwn_ghostty_host_config.h"
    : | tee "$derived/wwn-libghostty-link.xcconfig" >"$SRCROOT/.build/wwn-libghostty-link.xcconfig"
  fi
  exit 0
fi

# App Store Connect rejects libSystem's private ___progname, which weston and
# fontconfig reach; device builds force-load this replacement first.
case $PLATFORM_NAME in
  iphoneos | appletvos | xros)
    # No -m*-version-min: visionOS clang rejects it, and the stub uses no SDK API.
    xcrun --sdk "$PLATFORM_NAME" clang -c "$SRCROOT/src/platform/ios/WWNGetprognameStub.c" \
      -isysroot "$SDKROOT" -arch "${ARCHS%% *}" -fPIC -O2 -o "$derived/wawona-getprogname.o"
    xcrun --sdk "$PLATFORM_NAME" libtool -static -o "$derived/libwawona-getprogname.a" "$derived/wawona-getprogname.o"
    ;;
esac

# The merged object carries the app's floor: an SDK-default one makes clang
# emit _objc_release_xN, which dyld before iOS 16 cannot bind.
case $PLATFORM_NAME in
  iphone*) platform=ios min=$IPHONEOS_DEPLOYMENT_TARGET ;;
  appletv*) platform=tvos min=$TVOS_DEPLOYMENT_TARGET ;;
  watch*) platform=watchos min=$WATCHOS_DEPLOYMENT_TARGET ;;
  xr*) platform=xros min=$XROS_DEPLOYMENT_TARGET ;;
esac
case $PLATFORM_NAME in *simulator) platform=$platform-simulator ;; esac

# privatize <src.a> <dst.a> <exported symbol>
privatize() {
  local tmp
  tmp=$(mktemp -d)
  ld -r -arch arm64 -platform_version "$platform" "$min" "$min" -all_load "$1" -o "$tmp/merged.o"
  echo "$3" >"$tmp/exports"
  nmedit -s "$tmp/exports" "$tmp/merged.o"
  libtool -static "$tmp/merged.o" -o "$2"
  rm -rf "$tmp"
}
privatize "$deps/zsh/lib/libwawona-zsh.a" "$derived/libwawona-zsh.a" _wawona_zsh_main
privatize "$deps/fastfetch/lib/libfastfetch.a" "$derived/libfastfetch.a" _fastfetch_main
