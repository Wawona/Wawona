# macOS GL test clients built against iland (GBM/EGL/DRM over IOSurface) + ANGLE.
#
# Produces standalone GL clients that exercise the iland userland graphics path:
#   kmscube   pure gbm/drm/egl spinning cube (vendored in iland upstream/test)
#
# These run *nested inside Wawona* via the Mode A present-redirect
# (iland_drm_set_present_callback): kmscube's drmModePageFlip hands its IOSurface
# to Wawona's in-window CAMetalLayer compositor. Standalone (no callback) they
# fall back to the Mode B framebufferd path.
#
# es2gears (mesa-demos) and weston-simple-egl are built by their own recipes
# (mesa-demos / weston suite); kmscube is the canonical gbm/drm/egl smoke test
# and is self-contained here.
{
  lib,
  pkgs,
  buildModule,
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  iland = buildModule.buildForMacOS "iland" { };
  angle = buildModule.buildForMacOS "angle" { };
in
pkgs.stdenv.mkDerivation {
  pname = "iland-gl-clients";
  version = "0.1.0";

  src = ./upstream;

  __noChroot = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    unset DEVELOPER_DIR
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK=$(${xcodeUtils.findXcodeScript}/bin/find-xcode)/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
    fi
    if [ ! -d "$MACOS_SDK" ]; then
      echo "ERROR: MacOSX SDK not found." >&2
      exit 1
    fi
    export SDKROOT="$MACOS_SDK"

    CLANG="${pkgs.clang}/bin/clang"

    INCLUDES="-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    # ANGLE's EGLNativeDisplayType is `int`; kmscube (like all gbm/egl apps)
    # passes a `struct gbm_device *` that iland's eglGetDisplay casts back. The
    # offset->pointer attrib casts are also intentional. Relax both (upstream
    # kmscube builds the same way on such header combos).
    CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -O2 -std=c11 $INCLUDES -Wno-int-conversion -Wno-int-to-void-pointer-cast"

    # iland pulls in IOSurface/Foundation/CoreFoundation/CoreGraphics/Accelerate.
    FRAMEWORKS="-framework IOSurface -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework Accelerate -framework QuartzCore -framework Metal"
    LIBS="-L${iland}/lib -liland_userland -L${angle}/lib -lEGL -lGLESv2"

    echo "CC kmscube (standalone binary)"
    "$CLANG" $CFLAGS \
      test/kmscube.c \
      test/esUtil.c \
      $LIBS $FRAMEWORKS \
      -Wl,-rpath,${angle}/lib \
      -o kmscube

    # In-process variant: rename main -> kmscube_main so Wawona can run the
    # client on a thread within its own address space (the only way the Mode A
    # in-process present callback reaches the host compositor; cross-process
    # would require the Mode B framebufferd daemon). Mirrors the
    # weston-simple-shm libweston_simple_shm.a pattern.
    echo "CC libkmscube.a (in-process kmscube_main)"
    "$CLANG" -c $CFLAGS -Dmain=kmscube_main test/kmscube.c -o kmscube_main.o
    "$CLANG" -c $CFLAGS test/esUtil.c -o esUtil.o
    ar rcs libkmscube.a kmscube_main.o esUtil.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin $out/lib $out/include
    cp kmscube $out/bin/
    cp libkmscube.a $out/lib/
    # Declaration for the in-process entry point.
    cat > $out/include/kmscube.h <<'EOF'
#ifndef WAWONA_KMSCUBE_H
#define WAWONA_KMSCUBE_H
/* In-process kmscube entry point (main renamed via -Dmain=kmscube_main).
 * Run on a dedicated thread after iland_drm_set_present_callback() is set so
 * its drmModePageFlip presents reach Wawona's in-window compositor. */
int kmscube_main(int argc, char *argv[]);
#endif
EOF
    mkdir -p $out/nix-support
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
  '';

  meta = with lib; {
    description = "GL test clients (kmscube) over iland GBM/EGL/DRM + ANGLE for macOS";
    homepage = "https://github.com/wawona/iland";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
