{ lib, stdenv, pkgs, fetchurl, wayland-scanner, wayland-protocols }:

stdenv.mkDerivation rec {
  pname = "weston-simple-shm-patched-src";
  version = "13.0.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  nativeBuildInputs = [ wayland-scanner ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p $out
    cp -r clients $out/
    cp -r shared $out/
    cp -r include $out/

    # Generate xdg-shell protocols
    WAYLAND_PROTOCOLS_DATADIR="${wayland-protocols}/share/wayland-protocols"
    wayland-scanner client-header $WAYLAND_PROTOCOLS_DATADIR/stable/xdg-shell/xdg-shell.xml $out/xdg-shell-client-protocol.h
    wayland-scanner private-code $WAYLAND_PROTOCOLS_DATADIR/stable/xdg-shell/xdg-shell.xml $out/xdg-shell-protocol.c

    wayland-scanner client-header $WAYLAND_PROTOCOLS_DATADIR/unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml $out/fullscreen-shell-unstable-v1-client-protocol.h
    wayland-scanner private-code $WAYLAND_PROTOCOLS_DATADIR/unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml $out/fullscreen-shell-unstable-v1-protocol.c

    # Patch main function to be a callable library entry point
    sed -i 's/^main(int argc, char \*\*argv)/weston_simple_shm_main(int argc, char \*\*argv)/' $out/clients/simple-shm.c

    # Use return instead of exit to avoid crashing host process
    # First, handle functions returning pointers (like create_display)
    sed -i '/create_display(void)/,/^}/ s/exit(\([0-9]*\))/return NULL/g' $out/clients/simple-shm.c
    # Then handle functions returning int (like main)
    sed -i 's/exit(\([0-9]*\))/return \1/g' $out/clients/simple-shm.c

    # Fix Android NDK bug: sys/select.h (included by unistd.h) needs sigset_t, which is mysteriously blocked. Provide the exact NDK types manually.
    sed -i 's/#include <unistd.h>/#ifndef __APPLE__\ntypedef unsigned long sigset_t;\ntypedef struct { unsigned long __bits[128\/sizeof(long)]; } sigset64_t;\n#endif\n#include <unistd.h>/g' $out/clients/simple-shm.c
    sed -i 's/#include <unistd.h>/#ifndef __APPLE__\ntypedef unsigned long sigset_t;\ntypedef struct { unsigned long __bits[128\/sizeof(long)]; } sigset64_t;\n#endif\n#include <unistd.h>/g' $out/shared/os-compatibility.c
    sed -i 's/mkostemp(tmpname, O_CLOEXEC)/mkstemp(tmpname)/g' $out/shared/os-compatibility.c

    # Polyfill linux/input.h constants
    sed -i '/#include <linux\/input.h>/d' $out/clients/simple-shm.c
    sed -i 's/#include "config.h"/#include "config.h"\n#ifndef BTN_LEFT\n#define BTN_LEFT (0x110)\n#endif\n#ifndef BTN_RIGHT\n#define BTN_RIGHT (0x111)\n#endif\n#ifndef BTN_MIDDLE\n#define BTN_MIDDLE (0x112)\n#endif\n#ifndef KEY_ESC\n#define KEY_ESC (1)\n#endif/g' $out/clients/simple-shm.c

    # Disable Unix signal handler setup (sigaction not fully supported/needed here)
    sed -i '/struct sigaction/d' $out/clients/simple-shm.c
    sed -i '/sigemptyset/d' $out/clients/simple-shm.c
    sed -i '/sa_flags/d' $out/clients/simple-shm.c
    sed -i '/sa_handler/d' $out/clients/simple-shm.c
    sed -i '/sigaction(/d' $out/clients/simple-shm.c

    # Remove sys/epoll.h from os-compatibility.c since it is unavailable on iOS/macOS
    sed -i '/#include <sys\/epoll.h>/d' $out/shared/os-compatibility.c
    
    # Stub out epoll_create which doesn't exist on Apple platforms, but is unused by simple-shm
    sed -i 's/epoll_create(1)/-1/g' $out/shared/os-compatibility.c

    sed -i 's/static int running/int g_simple_shm_running/g' $out/clients/simple-shm.c
    sed -i 's/\brunning =/g_simple_shm_running =/g' $out/clients/simple-shm.c
    sed -i 's/\brunning;/g_simple_shm_running;/g' $out/clients/simple-shm.c
    sed -i 's/\brunning &&/g_simple_shm_running \&\&/g' $out/clients/simple-shm.c

    awk '
      /^weston_simple_shm_main/ { in_main = 1 }
      /^\{/ && in_main { 
        print; 
        print "\tg_simple_shm_running = 1;";
        print "\tint width = 250, height = 250;";
        print "\tfor (int i = 1; i < argc; i++) {";
        print "\t\tif (strcmp(argv[i], \"--width\") == 0 && i + 1 < argc) width = atoi(argv[++i]);";
        print "\t\telse if (strcmp(argv[i], \"--height\") == 0 && i + 1 < argc) height = atoi(argv[++i]);";
        print "\t}";
        in_main = 0; 
        next 
      }
      /display = create_display\(\);/ { print; print "\tif (!display) return 1;"; next }
      /window = create_window/ { print "\twindow = create_window(display, width, height);" ; next }
      { print }
    ' $out/clients/simple-shm.c > $out/clients/simple-shm.c.tmp
    mv $out/clients/simple-shm.c.tmp $out/clients/simple-shm.c

    # Create a basic config.h
    cat > $out/config.h <<'EOF'
#define VERSION "13.0.0"
EOF
  '';
}
