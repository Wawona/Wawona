# iland userland core for macOS (Mode A — in-window, App-Store-safe shape).
#
# Builds the IOSurface/ANGLE-backed Linux-graphics compat shims as a single
# static archive (libiland_userland.a) that Wayland/Weston GL clients
# (kmscube, es2gears, weston-simple-egl) link against:
#
#   displaysurface  IOSurface creation (WSPixelFormat / CAWindowServer-compatible)
#   gbm             Generic Buffer Management backed by IOSurface
#   egl             EGL/GLES entrypoints wrapping ANGLE (nixpkgs#angle)
#   drm             DRM/KMS userland API (drmMode*, gbm handle registry)
#
# Mode B (Dobby code injection, framebufferd/SkyLight, AMFI bypass, inputd) is
# intentionally NOT built here; it lives behind the `iland-baremetal` gate.
{
  lib,
  pkgs,
  stdenv,
  buildModule,
  # iland Mode B (bare-metal WindowServer replacement) opt-in. Default false:
  # build only the App-Store-safe Mode A userland (in-window IOSurface + ANGLE).
  # When true, additionally stage the Mode B sources (Dobby injection, AMFI
  # bypass, framebufferd/SkyLight, inputd, symrez). Mode B is macOS-only, is NOT
  # App-Store-safe (needs SIP off + root + private entitlements), and is never
  # used by the default app/store builds.
  baremetal ? false,
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  angle = buildModule.buildForMacOS "angle" { };
in
pkgs.stdenv.mkDerivation {
  pname = "iland-userland";
  version = "0.1.0";

  src = ./upstream;

  # Needs the macOS SDK (IOSurface/Accelerate/Foundation frameworks) via xcrun.
  __noChroot = true;

  dontConfigure = true;

  preBuild = ''
    # De-MacPorts: the EGL shim dlopen()s ANGLE from /opt/local; point it at the
    # Nix-provided ANGLE (nixpkgs#angle) instead.
    substituteInPlace shims/egl/src/egl.c \
      --replace "/opt/local/lib/libEGL.dylib"    "${angle}/lib/libEGL.dylib" \
      --replace "/opt/local/lib/libGLESv2.dylib" "${angle}/lib/libGLESv2.dylib"
  '';

  buildPhase = ''
    runHook preBuild

    # Robust macOS SDK detection (mirrors pixman/macos.nix).
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
    AR="ar"

    INCLUDES="\
      -Ishims/include \
      -Ishims/drm/displaysurface/include \
      -Ishims/drm/drm/include \
      -Ishims/gbm/include \
      -Ishims/egl/include \
      -I${angle}/include"

    COMMON_FLAGS="-isysroot $SDKROOT -mmacosx-version-min=12.0 -fPIC -O2 -std=c11 $INCLUDES"

    OBJS=""
    for src in \
      shims/drm/displaysurface/src/DisplaySurface.m \
      shims/gbm/src/gbm.m \
      shims/drm/drm/src/drm.c \
      shims/drm/drm/src/drm_linux.c \
      shims/drm/drm/src/drm_ioctl.c \
      shims/egl/src/egl.c; do
      obj="$(basename "$src").o"
      echo "CC $src"
      "$CLANG" -c "$src" $COMMON_FLAGS -o "$obj"
      OBJS="$OBJS $obj"
    done

    "$AR" rcs libiland_userland.a $OBJS

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include/EGL $out/include/GLES2 $out/include/GLES3 $out/include/KHR

    cp libiland_userland.a $out/lib/

    # Public client-facing headers
    cp shims/gbm/include/gbm.h                       $out/include/
    cp shims/egl/include/egl_shim.h                  $out/include/
    cp shims/drm/displaysurface/include/DisplaySurface.h $out/include/
    cp shims/include/drm_fourcc.h                    $out/include/
    cp shims/include/xf86drm.h                       $out/include/
    cp shims/include/xf86drmMode.h                   $out/include/
    cp shims/include/esUtil.h                        $out/include/ || true
    cp shims/drm/drm/include/drm.h                   $out/include/ || true
    cp shims/drm/drm/include/iland_present.h         $out/include/

    # GLES/EGL/KHR headers come from ANGLE so clients get a consistent ABI.
    cp -r ${angle}/include/EGL/.   $out/include/EGL/
    cp -r ${angle}/include/GLES2/. $out/include/GLES2/
    cp -r ${angle}/include/GLES3/. $out/include/GLES3/ || true
    cp -r ${angle}/include/KHR/.   $out/include/KHR/

    # Record the ANGLE runtime libraries clients dlopen/link at runtime.
    mkdir -p $out/nix-support
    echo "${angle}" > $out/nix-support/angle-path
    echo "${if baremetal then "mode-b-baremetal" else "mode-a-userland"}" \
      > $out/nix-support/iland-mode
  '' + lib.optionalString baremetal ''
    # Mode B (opt-in, macOS-only, NOT App-Store-safe): stage the bare-metal
    # WindowServer-replacement sources for the external injection toolchain.
    # These are intentionally NOT compiled into libiland_userland.a and require
    # SIP off + root + private entitlements + Dobby to build/run.
    mkdir -p $out/baremetal/src
    cp -r shims/drm/framebufferd      $out/baremetal/src/ || true
    cp -r shims/libinput/input-daemon $out/baremetal/src/ || true
    cp -r shims/wayland/amfi          $out/baremetal/src/ || true
    cp -r shims/drm/symrez            $out/baremetal/src/ || true
    cat > $out/baremetal/README.txt <<'EOF'
    iland Mode B (bare-metal WindowServer replacement) — macOS only, opt-in.
    NOT App-Store-safe. Requires SIP disabled, root, private entitlements and
    Dobby. Build with the external iland baremetal harness; never linked into
    the default Wawona app. The default (Mode A) path needs none of this.
    EOF
  '';

  passthru = {
    inherit angle;
    angleLibs = "${angle}/lib";
  };

  meta = with lib; {
    description = "iland userland in-window Linux-graphics compat (GBM/EGL/DRM over IOSurface+ANGLE) for macOS";
    homepage = "https://github.com/wawona/iland";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
