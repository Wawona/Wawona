# iOS GL test clients built against iland (GBM/EGL/DRM over IOSurface) + ANGLE.
#
# Produces libkmscube.a with kmscube_main for in-process nested GL inside Wawona.
{
  lib,
  pkgs,
  buildModule,
  simulator ? false,
  iosToolchain ? (import ../../apple/default.nix { inherit lib pkgs; }),
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  iland = buildModule.buildForIOS "iland" { inherit simulator; };
  angle = buildModule.buildForIOS "angle" { inherit simulator; };
  sdkPlatform = if simulator then "iPhoneSimulator" else "iPhoneOS";
  minFlag =
    if simulator then
      "-mios-simulator-version-min=${iosToolchain.deploymentTarget}"
    else
      "-miphoneos-version-min=${iosToolchain.deploymentTarget}";
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
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      [ -n "$XCODE_APP" ] && export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    INCLUDES="-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
    CFLAGS="-arch arm64 -isysroot $SDKROOT ${minFlag} -O2 -std=c11 \
      $INCLUDES -Wno-int-conversion -Wno-int-to-void-pointer-cast"

    echo "CC libkmscube.a (in-process kmscube_main)"
    "$CLANG" -c $CFLAGS -Dmain=kmscube_main test/kmscube.c -o kmscube_main.o
    "$CLANG" -c $CFLAGS test/esUtil.c -o esUtil.o
    cat > simple_egl_stub.c <<'EOF'
int simple_egl_main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    return 1;
}
EOF
    "$CLANG" -c $CFLAGS simple_egl_stub.c -o simple_egl_stub.o
    "$AR" rcs libkmscube.a kmscube_main.o esUtil.o simple_egl_stub.o

    # Full-stack link smoke needs an app bundle link line (static ANGLE + iland +
    # libc++); bare Mach-O executables are not representative on iOS. Compile +
    # archive is sufficient here — Xcode validates the final link.
    echo "Skipping kmscube link smoke (compile + archive verified)"

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include $out/nix-support
    cp libkmscube.a $out/lib/
    cat > $out/include/kmscube.h <<'EOF'
#ifndef WAWONA_KMSCUBE_H
#define WAWONA_KMSCUBE_H
int kmscube_main(int argc, char *argv[]);
#endif
EOF
    echo "${angle}" > $out/nix-support/angle-path
    echo "${iland}" > $out/nix-support/iland-path
  '';

  meta = with lib; {
    description = "GL test clients (kmscube) over iland GBM/EGL/DRM + ANGLE for iOS";
    homepage = "https://github.com/wawona/iland";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
