{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildModule,
  wawonaSrc ? null,
  simulator ? false,
  iosToolchain,
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  westonClientSrc = pkgs.callPackage ../../libs/weston-simple-shm/patched-src.nix { };
  libwayland = buildModule.buildForIPadOS "libwayland" { inherit simulator; };
  sdkPlatform = if simulator then "iPhoneSimulator" else "iPhoneOS";
  minVerFlag =
    if simulator then
      "-mios-simulator-version-min=${iosToolchain.deploymentTarget}"
    else
      "-miphoneos-version-min=${iosToolchain.deploymentTarget}";
in
stdenv.mkDerivation rec {
  pname = "weston-ipados";
  version = "13.0.0";
  __noChroot = true;

  src = westonClientSrc;
  nativeBuildInputs = [ xcodeUtils.findXcodeScript ];

  buildPhase = ''
    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    cat > weston_shim.c <<'EOF'
    extern int weston_simple_shm_main(int argc, char **argv);
    int wwn_weston_is_compat_shim(void) { return 1; }
    int weston_main(int argc, char **argv) {
      (void)argc;
      (void)argv;
      char *shim_argv[] = { "weston-simple-shm", 0 };
      return weston_simple_shm_main(1, shim_argv);
    }
    EOF

    cat > weston_desktop_stub.c <<'EOF'
    int wwn_weston_desktop_stub(void) {
      return 0;
    }
    EOF

    cp ${./mobile-weston-terminal.c} ./mobile-weston-terminal.c

    "$CLANG" -c weston_shim.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o weston_shim.o
    "$CLANG" -c mobile-weston-terminal.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC \
      -I. -Iinclude -Ishared -I${libwayland}/include -I${libwayland}/include/wayland \
      -o weston_terminal_mobile.o
    "$CLANG" -c xdg-shell-protocol.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC \
      -I. -Iinclude -I${libwayland}/include -I${libwayland}/include/wayland \
      -o xdg-shell-protocol.o
    "$CLANG" -c weston_desktop_stub.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o weston_desktop_stub.o

    "$AR" rcs libweston-13.a weston_shim.o
    "$AR" rcs libweston-terminal.a weston_terminal_mobile.o xdg-shell-protocol.o
    "$AR" rcs libweston-desktop-13.a weston_desktop_stub.o
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp libweston-13.a $out/lib/
    cp libweston-terminal.a $out/lib/
    cp libweston-desktop-13.a $out/lib/
  '';

  meta = with lib; {
    description = "Weston mobile client libraries for iPadOS Wawona";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
