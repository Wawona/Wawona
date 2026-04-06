{ lib, stdenv, pkgs, fetchurl, wawonaSrc ? null, simulator ? false, ... }:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };
  sdkPlatform = if simulator then "iPhoneSimulator" else "iPhoneOS";
  minVerFlag = if simulator then "-mios-simulator-version-min=26.0" else "-miphoneos-version-min=26.0";
in
stdenv.mkDerivation rec {
  pname = "weston-ios";
  version = "13.0.0";
  __noChroot = true;

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  dontUnpack = true;
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
    int weston_main(int argc, char **argv) {
      (void)argc;
      (void)argv;
      char *shim_argv[] = { "weston-simple-shm", 0 };
      return weston_simple_shm_main(1, shim_argv);
    }
    EOF

    cat > weston_terminal_shim.c <<'EOF'
    extern int weston_simple_shm_main(int argc, char **argv);
    int weston_terminal_main(int argc, char **argv) {
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

    "$CLANG" -c weston_shim.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o weston_shim.o
    "$CLANG" -c weston_terminal_shim.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o weston_terminal_shim.o
    "$CLANG" -c weston_desktop_stub.c -arch arm64 -isysroot "$SDKROOT" ${minVerFlag} -fPIC -o weston_desktop_stub.o

    "$AR" rcs libweston-13.a weston_shim.o
    "$AR" rcs libweston-terminal.a weston_terminal_shim.o
    "$AR" rcs libweston-desktop-13.a weston_desktop_stub.o
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp libweston-13.a $out/lib/
    cp libweston-terminal.a $out/lib/
    cp libweston-desktop-13.a $out/lib/
  '';

  meta = with lib; {
    description = "Weston compatibility shims for iOS Wawona";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
