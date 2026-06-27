# weston toytoolkit + demo clients, cross-compiled for iOS as in-process static
# libraries (real ports, not the old simple-shm shim).
#
# This compiles weston's real toytoolkit (clients/window.c) and the cairo/SHM demo
# clients directly with clang, linking (at app-link time) against the cross
# cairo/pango stack (cairo, pango, pangocairo, fontconfig, freetype, harfbuzz,
# fribidi, glib, libpng, pixman), libwayland (+wayland-cursor), xkbcommon and
# epoll-shim. Each demo client's `main` is renamed to `<name>_main` via -Dmain so
# it can be driven in-process by Wawona.
#
# Output archives preserve the link contract consumed by dependencies/generators/
# xcodegen.nix:
#   libweston-13.a        -> toytoolkit + demo clients (flower_main, etc.)
#   libweston-terminal.a  -> real clients/terminal.c (Apple mobile; watchOS stub)
#   libweston-desktop-13.a-> weston-desktop-shell client (in-process)
#   libweston-keyboard.a  -> weston-keyboard client (in-process)
{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  wawonaSrc ? null,
  simulator ? false,
  iosToolchain,
  # When true (default), attempt weston-simple-egl after verifying the iland GL
  # stack links (kmscube smoke test via iland-gl-clients-ios).
  enableGlClients ? false,
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };

  # Cross dependency closure (headers needed to compile; linked by the app target).
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  xkbcommon = buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  epollShim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };
  cairo = buildModule.buildForIOS "cairo" { inherit simulator; };
  pango = buildModule.buildForIOS "pango" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  glib = buildModule.buildForIOS "glib" { inherit simulator; };
  harfbuzz = buildModule.buildForIOS "harfbuzz" { inherit simulator; };
  fribidi = buildModule.buildForIOS "fribidi" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };

  mobile = (import ../../toolchains/apple-mobile-platform.nix) {
    inherit iosToolchain simulator;
  };
  # In-process zsh PTY shim. Now available across the whole Apple family (the
  # zsh stack is wired for tv/watch/vision in registry.nix +
  # mobile-platform-deps.nix), so the real weston-terminal client can drive a
  # local shell everywhere rather than the old watchOS/tvOS stub.
  wawonaPty = buildModule.buildForIOS "wawona-pty" { inherit simulator; };

  glClients = if enableGlClients then
    pkgs.callPackage ../../libs/iland/gl-clients-ios.nix {
      inherit buildModule simulator iosToolchain;
    }
  else null;
  angle = if enableGlClients then buildModule.buildForIOS "angle" { inherit simulator; } else null;
  iland = if enableGlClients then buildModule.buildForIOS "iland" { inherit simulator; } else null;
  glIncludeFlags = if enableGlClients then
    "-I${iland}/include -I${iland}/include/EGL -I${iland}/include/GLES2 -I${angle}/include"
  else "";
  glClientsPath = if enableGlClients then "${glClients}" else "";

  pkgConfigPath = lib.concatStringsSep ":" (map (d: "${d}/lib/pkgconfig") [
    cairo pango fontconfig freetype glib harfbuzz fribidi pixman libpng
    expat libffi pcre2 xkbcommon libwayland
  ]);

  # Host (build-arch) wayland-scanner — buildPackages.wayland-scanner is broken on
  # darwin, so compile it from the wayland source like the libwayland recipe does.
  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host";
    src = pkgs.wayland.src;
    nativeBuildInputs = [
      buildPackages.meson buildPackages.ninja buildPackages.pkg-config
      buildPackages.expat buildPackages.libxml2
    ];
    configurePhase = ''
      meson setup build --prefix=$out -Dlibraries=false -Ddocumentation=false -Dtests=false
    '';
    buildPhase = ''meson compile -C build wayland-scanner'';
    installPhase = ''
      mkdir -p $out/bin
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
    '';
  };

  sdkPlatform = mobile.sdkPlatform;
  minVerFlag = mobile.minVerFlag;

  # Demo clients to build as in-process *_main libs. Curated to the cairo/SHM set
  # that links only the toytoolkit + already-generated protocols (terminal handled
  # separately). weston-simple-egl is added when enableGlClients and the iland GL
  # stack (kmscube link smoke test) succeeds.
  baseClients = [
    "flower" "clickdot" "smoke" "eventdemo" "resizor" "cliptest"
    "transformed" "stacking" "dnd" "image" "scaler"
    "editor" "constraints"
  ];
  clients = baseClients ++ lib.optionals enableGlClients [ "simple-egl" ];
  westonSimpleShmSrc = pkgs.callPackage ../../libs/weston-simple-shm/patched-src.nix { };
in
stdenv.mkDerivation rec {
  pname = "weston-ios";
  version = "13.0.0";
  __noChroot = true;

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  # wayland-cursor sources are compiled here for headers/TU glue; os_create_anonymous_file
  # comes from libwayland-cursor at final link time (not shared/os-compatibility.c).
  waylandSrc = pkgs.wayland.src;

  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54=";
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };

  nativeBuildInputs = [
    xcodeUtils.findXcodeScript
    waylandScanner
    buildPackages.pkg-config
    buildPackages.python3
  ] ++ lib.optionals enableGlClients [ glClients angle iland ];

  postPatch = ''
    # libwayland-cursor ships os_create_anonymous_file + os_resize_anonymous_file.
    python3 <<'PY'
from pathlib import Path
path = Path("shared/os-compatibility.c")
text = path.read_text()
needle = "int\nos_create_anonymous_file(off_t size)"
start = text.index(needle)
end = text.index("\n#ifndef HAVE_STRCHRNUL", start)
path.write_text(
    text[:start]
    + "/* os_create_anonymous_file provided by libwayland-cursor at link time */\n\n"
    + text[end:]
)
PY
  '';

  buildPhase = ''
    runHook preBuild

    if [ -z "''${XCODE_APP:-}" ]; then
      XCODE_APP=$(${xcodeUtils.findXcodeScript}/bin/find-xcode || true)
      if [ -n "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
      fi
    fi
    export SDKROOT="$DEVELOPER_DIR/Platforms/${sdkPlatform}.platform/Developer/SDKs/${sdkPlatform}.sdk"
    CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    AR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/ar"

    export PKG_CONFIG_PATH="${pkgConfigPath}"
    PKGCONF="${buildPackages.pkg-config}/bin/pkg-config"
    DEP_CFLAGS=$($PKGCONF --cflags cairo pango pangocairo fontconfig freetype2 harfbuzz fribidi glib-2.0 gobject-2.0 libpng pixman-1 xkbcommon wayland-client wayland-cursor)

    # --- Generated wayland protocols (client headers + private code) ---
    mkdir -p gen
    SCANNER="${waylandScanner}/bin/wayland-scanner"
    WP="${buildPackages.wayland-protocols}/share/wayland-protocols"
    gen_proto() {
      local name="$1" xml="$2"
      "$SCANNER" client-header "$xml" "gen/$name-client-protocol.h"
      "$SCANNER" private-code  "$xml" "gen/$name-protocol.c"
    }
    gen_proto xdg-shell                      "$WP/stable/xdg-shell/xdg-shell.xml"
    gen_proto viewporter                     "$WP/stable/viewporter/viewporter.xml"
    gen_proto presentation-time              "$WP/stable/presentation-time/presentation-time.xml"
    gen_proto relative-pointer-unstable-v1   "$WP/unstable/relative-pointer/relative-pointer-unstable-v1.xml"
    gen_proto pointer-constraints-unstable-v1 "$WP/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml"
    gen_proto tablet-unstable-v2             "$WP/unstable/tablet/tablet-unstable-v2.xml"
    gen_proto text-input-unstable-v1         "$WP/unstable/text-input/text-input-unstable-v1.xml"
    gen_proto input-method-unstable-v1       "$WP/unstable/input-method/input-method-unstable-v1.xml"
    gen_proto text-cursor-position           "protocol/text-cursor-position.xml"
    gen_proto ivi-application                "protocol/ivi-application.xml"
    gen_proto weston-desktop-shell           "protocol/weston-desktop-shell.xml"

    # --- config.h tailored for the Apple toytoolkit build ---
    cat > config.h <<'EOF'
#ifndef WESTON_CONFIG_H
#define WESTON_CONFIG_H
#define PACKAGE_STRING "weston 13.0.0"
#define PACKAGE_VERSION "13.0.0"
#define HAVE_PANGO 1
#define HAVE_XKBCOMMON_COMPOSE 1
/* Install-path macros (normally injected by meson). Unused at runtime by the
 * in-process Apple libs, but referenced by the sources. */
#define DATADIR "/usr/share"
#define BINDIR "/usr/bin"
#define LIBEXECDIR "/usr/libexec"
#define MODULEDIR "/usr/lib/weston"
#define LIBWESTON_MODULEDIR "/usr/lib/libweston"
/* Apple lacks memfd_create/mkostemp/posix_fallocate/strchrnul: weston's
 * os-compatibility.c provides fallbacks when these are undefined. */
#endif
EOF

    # --- Apple polyfills (force-included into every TU) ---
    cat > include/apple-polyfills.h <<'EOF'
#ifndef WESTON_APPLE_POLYFILLS_H
#define WESTON_APPLE_POLYFILLS_H
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <signal.h>
#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
#include <sys/signal.h>
#endif
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0
#endif
#ifndef SOCK_NONBLOCK
#define SOCK_NONBLOCK 0
#endif
#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
static inline int pipe2(int fds[2], int flags) {
    if (pipe(fds) != 0) return -1;
    if (flags & O_CLOEXEC) {
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    }
    if (flags & O_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    return 0;
}
#endif
#endif
EOF

    # --- Linux input header shims (KEY_*/BTN_* codes used by window.c) ---
    mkdir -p include/linux
    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h
    cat > include/linux/types.h <<'EOF'
#ifndef _LINUX_TYPES_SHIM_H
#define _LINUX_TYPES_SHIM_H
#include <stdint.h>
typedef uint8_t __u8;  typedef uint16_t __u16; typedef uint32_t __u32; typedef uint64_t __u64;
typedef int8_t  __s8;  typedef int16_t  __s16; typedef int32_t  __s32; typedef int64_t  __s64;
typedef uint16_t __le16; typedef uint32_t __le32; typedef uint64_t __le64;
typedef uint16_t __be16; typedef uint32_t __be32; typedef uint64_t __be64;
#define __user
#define __BITS_PER_LONG 64
#endif
EOF
    cat > include/linux/ioctl.h <<'EOF'
#ifndef _LINUX_IOCTL_SHIM_H
#define _LINUX_IOCTL_SHIM_H
#include <sys/ioctl.h>
#endif
EOF

    # Extract wayland source for wayland-cursor (headers are not installed by libwayland-ios).
    mkdir -p wlsrc && tar xf ${waylandSrc} -C wlsrc
    WLCURSOR=$(echo wlsrc/wayland-*/cursor)

    CFLAGS="-arch arm64 -isysroot $SDKROOT ${minVerFlag} -fPIC -D_GNU_SOURCE -D_DARWIN_C_SOURCE -O2 \
      -I. -Iinclude -Igen -Ishared \
      -I$WLCURSOR \
      -I${libwayland}/include \
      -I${libwayland}/include/wayland \
      -I${epollShim}/include/libepoll-shim \
      -Dprogram_invocation_short_name=getprogname() \
      -DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC -DCLOCK_REALTIME_COARSE=CLOCK_REALTIME \
      -include $PWD/include/apple-polyfills.h \
      $DEP_CFLAGS"

    objs=""
    compile() { # compile <src> [extra-cflags]
      local src="$1"; shift
      local obj="$(echo "$src" | tr '/.' '__').o"
      echo "CC $src"
      "$CLANG" -c "$src" $CFLAGS "$@" -o "$obj"
      objs="$objs $obj"
    }
    compile_only() { # compile_only <src> [extra-cflags] -> prints obj path on stdout
      local src="$1"; shift
      local obj="$(echo "$src" | tr '/.' '__').o"
      echo "CC $src" >&2
      "$CLANG" -c "$src" $CFLAGS "$@" -o "$obj"
      echo "$obj"
    }

    # Shared (libshared) + cairo-shared + matrix
    # frame_create loads PNGs from WESTON_DATA_DIR; tolerate missing assets on
    # Apple mobile so panel-launched clients don't SIGSEGV before bundle embed.
    cp shared/frame.c shared/mobile-frame.c
    python3 <<'PY'
from pathlib import Path

path = Path("shared/mobile-frame.c")
text = path.read_text()
anchor = '#include "config.h"'
mobile_hdr = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
"""
if mobile_hdr.strip() not in text:
    text = text.replace(anchor, anchor + mobile_hdr, 1)
old = """\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS)
\t\tgoto error;"""
new = """#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS) {
\t\tif (icon)
\t\t\tcairo_surface_destroy(icon);
\t\ticon = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
\t}
#else
\ticon = cairo_image_surface_create_from_png(icon_name);
\tif (cairo_surface_status(icon) != CAIRO_STATUS_SUCCESS)
\t\tgoto error;
#endif"""
if old not in text:
    raise SystemExit("frame.c icon load anchor missing")
path.write_text(text.replace(old, new, 1))
PY
    for s in shared/config-parser.c shared/option-parser.c shared/signal.c \
             shared/file-util.c shared/os-compatibility.c shared/process-util.c \
             shared/hash.c shared/image-loader.c shared/cairo-util.c shared/matrix.c \
             libweston/vertex-clipping.c; do
      compile "$s"
    done
    compile shared/mobile-frame.c

    # wayland-cursor TU glue (cursor/os-compatibility.c lives in libwayland-cursor.a).
    compile "$WLCURSOR/wayland-cursor.c"
    compile "$WLCURSOR/xcursor.c"

    objs="$objs $(compile_only ${./wwn-weston-log.c})"

    # Generated protocol private-code lives in libweston-compositor-13.a when the
    # nested compositor is linked; compiling gen/* here duplicates wl_interface
    # symbols at final link time.

    # Toytoolkit core — on Apple mobile, connect via inherited socket fd instead
    # of WAYLAND_SOCKET env (setenv is unreliable in the iOS app sandbox).
    cp ${./wwn-mobile-clients.h} ./wwn-mobile-clients.h
    cp clients/window.c clients/mobile-window.c
    python3 <<'PY'
from pathlib import Path

path = Path("clients/mobile-window.c")
text = path.read_text()
anchor = '#include <wayland-client.h>'
if anchor not in text:
    raise SystemExit("window.c wayland-client include missing")
if "wwn-mobile-clients.h" not in text:
    text = text.replace(
        anchor,
        anchor + """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
#include "wwn-mobile-clients.h"
extern void weston_log(const char *fmt, ...);
#define WWN_DISPLAY_LOG(...) weston_log(__VA_ARGS__)
#else
#define WWN_DISPLAY_LOG(...) ((void)0)
#endif
#else
#define WWN_DISPLAY_LOG(...) ((void)0)
#endif""",
        1,
    )
old_connect = (
    "\td->display = wl_display_connect(NULL);\n"
    "\tif (d->display == NULL) {\n"
    '\t\tfprintf(stderr, "failed to connect to Wayland display: %s\\n",\n'
    "\t\t\tstrerror(errno));\n"
    "\t\tfree(d);\n"
    "\t\treturn NULL;\n"
    "\t}"
)
new_connect = (
    "\t{\n"
    "#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)\n"
    "\t\tint wwn_fd = wwn_mobile_consume_wayland_socket_fd();\n"
    "\n"
    "\t\tif (wwn_fd > STDERR_FILENO) {\n"
    "\t\t\tWWN_DISPLAY_LOG(\"wwn toytoolkit: display_create connect_to_fd(%d)\\n\", wwn_fd);\n"
    "\t\t\td->display = wl_display_connect_to_fd(wwn_fd);\n"
    "\t\t} else {\n"
    "\t\t\t/* libwayland reads WAYLAND_SOCKET from env before WAYLAND_DISPLAY. */\n"
    "\t\t\tunsetenv(\"WAYLAND_SOCKET\");\n"
    "\t\t\tWWN_DISPLAY_LOG(\"wwn toytoolkit: display_create wl_display_connect(NULL) "
    "(host compositor)\\n\");\n"
    "\t\t\td->display = wl_display_connect(NULL);\n"
    "\t\t}\n"
    "#else\n"
    "\t\td->display = wl_display_connect(NULL);\n"
    "#endif\n"
    "\t}\n"
    "\tif (d->display == NULL) {\n"
    '\t\tWWN_DISPLAY_LOG("wwn toytoolkit: display_create connect failed: %s\\n",\n'
    "\t\t\t      strerror(errno));\n"
    '\t\tfprintf(stderr, "failed to connect to Wayland display: %s\\n",\n'
    "\t\t\tstrerror(errno));\n"
    "\t\tfree(d);\n"
    "\t\treturn NULL;\n"
    "\t}\n"
    '\tWWN_DISPLAY_LOG("wwn toytoolkit: display_create connected, roundtrip...\\n");'
)
if old_connect not in text:
    raise SystemExit("window.c display_create connect anchor missing")
text = text.replace(old_connect, new_connect, 1)
old_roundtrip = (
    "\tif (wl_display_roundtrip(d->display) < 0) {\n"
    '\t\tfprintf(stderr, "Failed to process Wayland connection: %s\\n",\n'
    "\t\t\tstrerror(errno));\n"
    "\t\tdisplay_destroy(d);\n"
    "\t\treturn NULL;\n"
    "\t}"
)
new_roundtrip = (
    "\tif (wwn_mobile_display_roundtrip(d->display) < 0) {\n"
    '\t\tWWN_DISPLAY_LOG("wwn toytoolkit: display_create roundtrip failed: %s\\n",\n'
    "\t\t\t      strerror(errno));\n"
    '\t\tfprintf(stderr, "Failed to process Wayland connection: %s\\n",\n'
    "\t\t\tstrerror(errno));\n"
    "\t\tdisplay_destroy(d);\n"
    "\t\treturn NULL;\n"
    "\t}\n"
    '\tWWN_DISPLAY_LOG("wwn toytoolkit: display_create roundtrip OK (outputs=%d)\\n",\n'
    "\t\t      wl_list_length(&d->output_list));"
)
if old_roundtrip not in text:
    raise SystemExit("window.c display_create roundtrip anchor missing")
text = text.replace(old_roundtrip, new_roundtrip, 1)
old_display_run_epoll = (
    "\t\tcount = epoll_wait(display->epoll_fd,\n"
    "\t\t\t\t   ep, ARRAY_LENGTH(ep), -1);"
)
new_display_run_epoll = (
    "#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)\n"
    "\t\t/* Timed wait yields to nested compositor thread (same-process clients). */\n"
    "\t\tcount = epoll_wait(display->epoll_fd,\n"
    "\t\t\t\t   ep, ARRAY_LENGTH(ep), 1);\n"
    "\t\tif (count == 0) {\n"
    "\t\t\twwn_ios_pump_host_compositor();\n"
    "\t\t\tsched_yield();\n"
    "\t\t\tcontinue;\n"
    "\t\t}\n"
    "#else\n"
    "\t\tcount = epoll_wait(display->epoll_fd,\n"
    "\t\t\t\t   ep, ARRAY_LENGTH(ep), -1);\n"
    "#endif"
)
if old_display_run_epoll not in text:
    raise SystemExit("window.c display_run epoll anchor missing")
text = text.replace(old_display_run_epoll, new_display_run_epoll, 1)
if "#include <sched.h>" not in text:
    text = text.replace("#include <errno.h>", "#include <errno.h>\n#include <sched.h>", 1)
if "wwn_mobile_display_dispatch(display)" not in text:
    anchor_macro = '#include "wwn-mobile-clients.h"'
    if anchor_macro not in text:
        raise SystemExit("window.c wwn-mobile-clients include missing for roundtrip macro")
    text = text.replace(
        anchor_macro,
        anchor_macro + """
#define wl_display_roundtrip(display) wwn_mobile_display_roundtrip(display)
#define wl_display_dispatch(display) wwn_mobile_display_dispatch(display)""",
        1,
    )
elif "wwn_mobile_display_roundtrip(display)" not in text:
    anchor_macro = '#include "wwn-mobile-clients.h"'
    if anchor_macro not in text:
        raise SystemExit("window.c wwn-mobile-clients include missing for roundtrip macro")
    text = text.replace(
        anchor_macro,
        anchor_macro + """
#define wl_display_roundtrip(display) wwn_mobile_display_roundtrip(display)
#define wl_display_dispatch(display) wwn_mobile_display_dispatch(display)""",
        1,
    )
path.write_text(text)
PY
    cp ${./terminal-patches/patch-window-csd.py} ./patch-window-csd.py
    python3 patch-window-csd.py clients/mobile-window.c clients/window.h
    compile clients/mobile-window.c
    objs="$objs $(compile_only ${./mobile-weston-host-clients.c})"

    # Demo clients (main -> <sanitized>_main, hyphens -> underscores)
    GL_CLIENTS_OK=0
    if [ "${if enableGlClients then "1" else "0"}" = "1" ] && [ -n "${glClientsPath}" ] && [ -f "${glClientsPath}/lib/libkmscube.a" ]; then
      echo "GL stack probe: iland-gl-clients-ios present (kmscube link verified at build time)"
      GL_CLIENTS_OK=1
    fi
    for c in ${lib.concatStringsSep " " baseClients}; do
      sym=$(echo "$c" | tr '-' '_')
      compile "clients/$c.c" "-Dmain=''${sym}_main"
    done
    if [ "$GL_CLIENTS_OK" = "1" ]; then
      sym=simple_egl
      echo "CC clients/simple-egl.c (iland GL stack)"
      compile "clients/simple-egl.c" "-Dmain=''${sym}_main ${glIncludeFlags}" || {
        echo "WARNING: weston-simple-egl skipped (compile failed)" >&2
      }
    fi

    echo "CC weston-simple-shm (patched in-process weston_simple_shm_main)"
    shm_src="weston-simple-shm-patched.c"
    cp "${westonSimpleShmSrc}/clients/simple-shm.c" "$shm_src"
    chmod u+w "$shm_src"
    # constraints already defines struct wl_shm_listener shm_listener.
    python3 <<'PY'
from pathlib import Path
path = Path("weston-simple-shm-patched.c")
text = path.read_text()
needle = "struct wl_shm_listener shm_listener"
start = text.index(needle)
end = text.index("};", start) + 2
path.write_text(text[:start] + "extern struct wl_shm_listener shm_listener;\n\n" + text[end:].lstrip())
PY
    shm_obj="clients_simple_shm_patched_c.o"
    if "$CLANG" -c "$shm_src" $CFLAGS \
      -I${westonSimpleShmSrc} \
      -o "$shm_obj"; then
      objs="$objs $shm_obj"
    else
      echo "WARNING: weston-simple-shm skipped (compile failed)" >&2
    fi

    "$AR" rcs libweston-13.a $objs

    # --- weston-terminal -> libweston-terminal.a ---
    # The real clients/terminal.c (driving in-process zsh over the fake PTY) is
    # now built for the whole Apple family. watchOS/tvOS apply a constrained UX at
    # the view layer (see docs/ios-local-shell/WATCHOS-SCOPE.md), not a C stub.
    cp clients/terminal.c clients/mobile-terminal.c
    cp ${./terminal-patches/patch-terminal.py} ./patch-terminal.py
    cp ${wawonaPty}/include/wwn_pty.h ./wwn_pty.h
    python3 patch-terminal.py clients/mobile-terminal.c
    term_cflags="-Dmain=weston_terminal_main -I${wawonaPty}/include"
    term_objs="$(compile_only clients/mobile-terminal.c $term_cflags)"
    term_objs="$term_objs $(compile_only ${./wwn-terminal-marker.c})"
    "$AR" rcs libweston-terminal.a $term_objs

    # --- weston-desktop-shell -> libweston-desktop-13.a ---
    # Tablet/xdg/text-input protocols live in libweston-13.a; only add shell-specific protocol.
    desktop_objs="$(compile_only gen/weston-desktop-shell-protocol.c)"
    if [ "${toString mobile.isTVOS}" = "true" ] || [ "${toString mobile.isWatchOS}" = "true" ]; then
      cp ${./mobile-desktop-shell-stub.c} ./mobile-desktop-shell-stub.c
      desktop_objs="$desktop_objs $(compile_only mobile-desktop-shell-stub.c -Dmain=weston_desktop_shell_main)"
    else
      cp clients/desktop-shell.c clients/mobile-desktop-shell.c
      python3 <<'PY'
from pathlib import Path

path = Path("clients/mobile-desktop-shell.c")
text = path.read_text()
if "WWN_SHELL_LOG" not in text:
    header = """
#if defined(__APPLE__)
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
extern void weston_log(const char *fmt, ...);
#define WWN_SHELL_LOG(...) weston_log(__VA_ARGS__)
#else
#define WWN_SHELL_LOG(...) ((void)0)
#endif
#else
#define WWN_SHELL_LOG(...) ((void)0)
#endif
"""
    anchor = '#include "shared/xalloc.h"'
    if anchor not in text:
        raise SystemExit("desktop-shell include anchor missing")
    text = text.replace(anchor, anchor + header, 1)
    mobile_clients = """
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
#include "wwn-mobile-clients.h"
#endif
"""
    anchor2 = '#include "weston-desktop-shell-client-protocol.h"'
    if anchor2 not in text:
        raise SystemExit("desktop-shell protocol include missing")
    if "wwn-mobile-clients.h" not in text:
        text = text.replace(anchor2, anchor2 + mobile_clients, 1)
    old_main = """int main(int argc, char *argv[])
{
	struct desktop desktop = { 0 };
	struct output *output;
	struct weston_config_section *s;
	const char *config_file;

	desktop.unlock_task.run = unlock_dialog_finish;
	wl_list_init(&desktop.outputs);

	config_file = weston_config_get_name_from_env();
	desktop.config = weston_config_parse(config_file);
	s = weston_config_get_section(desktop.config, "shell", NULL, NULL);
	weston_config_section_get_bool(s, "locking", &desktop.locking, true);
	parse_panel_position(&desktop, s);
	parse_clock_format(&desktop, s);

	desktop.display = display_create(&argc, argv);
	if (desktop.display == NULL) {
		fprintf(stderr, "failed to create display: %s\\n",
			strerror(errno));
		weston_config_destroy(desktop.config);
		return -1;
	}

	display_set_user_data(desktop.display, &desktop);
	display_set_global_handler(desktop.display, global_handler);
	display_set_global_handler_remove(desktop.display, global_handler_remove);

	/* Create panel and background for outputs processed before the shell
	 * global interface was processed */
	if (desktop.want_panel)
		weston_desktop_shell_set_panel_position(desktop.shell, desktop.panel_position);
	wl_list_for_each(output, &desktop.outputs, link)
		if (!output->panel)
			output_init(output, &desktop);

	grab_surface_create(&desktop);

	signal(SIGCHLD, sigchild_handler);"""
    new_main = """int main(int argc, char *argv[])
{
	struct desktop desktop = { 0 };
	struct output *output;
	struct weston_config_section *s;
	const char *config_file;

	desktop.unlock_task.run = unlock_dialog_finish;
	wl_list_init(&desktop.outputs);

	config_file = weston_config_get_name_from_env();
	WWN_SHELL_LOG("wwn desktop-shell: config file '%s'\\n",
		      config_file ? config_file : "(null)");
	desktop.config = weston_config_parse(config_file);
	if (!desktop.config)
		WWN_SHELL_LOG("wwn desktop-shell: config parse failed (errno=%d)\\n",
			      errno);
	else
		WWN_SHELL_LOG("wwn desktop-shell: config parsed OK\\n");
	s = weston_config_get_section(desktop.config, "shell", NULL, NULL);
	weston_config_section_get_bool(s, "locking", &desktop.locking, true);
	parse_panel_position(&desktop, s);
	parse_clock_format(&desktop, s);

	desktop.display = display_create(&argc, argv);
	if (desktop.display == NULL) {
		WWN_SHELL_LOG("wwn desktop-shell: display_create failed: %s\\n",
			      strerror(errno));
		weston_config_destroy(desktop.config);
		return -1;
	}

	display_set_user_data(desktop.display, &desktop);
	display_set_global_handler(desktop.display, global_handler);
	display_set_global_handler_remove(desktop.display, global_handler_remove);

	WWN_SHELL_LOG("wwn desktop-shell: shell=%p outputs=%d want_panel=%d\\n",
		      (void *)desktop.shell,
		      wl_list_length(&desktop.outputs),
		      desktop.want_panel);

	/* Create panel and background for outputs processed before the shell
	 * global interface was processed */
	if (desktop.want_panel && desktop.shell)
		weston_desktop_shell_set_panel_position(desktop.shell, desktop.panel_position);
	else if (desktop.want_panel && !desktop.shell)
		WWN_SHELL_LOG("wwn desktop-shell: shell global missing, skipping panel position\\n");
	wl_list_for_each(output, &desktop.outputs, link)
		if (!output->panel)
			output_init(output, &desktop);

#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
	if (desktop.display) {
		struct wl_display *wl = display_get_display(desktop.display);
		struct output *out;

		wl_display_flush(wl);
		wwn_mobile_pump_client_display_for_ms(wl, 250);
		wl_list_for_each(out, &desktop.outputs, link) {
			if (out->background && out->background->widget)
				widget_schedule_redraw(out->background->widget);
			if (out->panel && out->panel->widget)
				widget_schedule_redraw(out->panel->widget);
		}
		wl_display_flush(wl);
		wwn_mobile_pump_client_display_for_ms(wl, 250);
	}
#endif

	WWN_SHELL_LOG("wwn desktop-shell: outputs initialized, entering display_run\\n");

	grab_surface_create(&desktop);

#if !(defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH))
	signal(SIGCHLD, sigchild_handler);
#endif"""
    if old_main not in text:
        raise SystemExit("desktop-shell main() anchor missing")
    text = text.replace(old_main, new_main, 1)
    old_output_init = """output_init(struct output *output, struct desktop *desktop)
{
\tstruct wl_surface *surface;

\tif (desktop->want_panel) {"""
    new_output_init = """output_init(struct output *output, struct desktop *desktop)
{
\tstruct wl_surface *surface;

\tif (!desktop->shell) {
\t\tWWN_SHELL_LOG("wwn desktop-shell: output_init skipped (no shell global)\\n");
\t\treturn;
\t}

\tif (desktop->want_panel) {"""
    if old_output_init not in text:
        raise SystemExit("desktop-shell output_init anchor missing")
    text = text.replace(old_output_init, new_output_init, 1)
    old_bg_cfg = """background_configure(void *data,
\t\t     struct weston_desktop_shell *desktop_shell,
\t\t     uint32_t edges, struct window *window,
\t\t     int32_t width, int32_t height)
{
\tstruct output *owner;
\tstruct background *background =
\t\t(struct background *) window_get_user_data(window);

\tif (width < 1 || height < 1) {"""
    new_bg_cfg = """background_configure(void *data,
\t\t     struct weston_desktop_shell *desktop_shell,
\t\t     uint32_t edges, struct window *window,
\t\t     int32_t width, int32_t height)
{
\tstruct output *owner;
\tstruct background *background =
\t\t(struct background *) window_get_user_data(window);

\tWWN_SHELL_LOG("wwn desktop-shell: background_configure %dx%d\\n",
\t\t      width, height);

\tif (width < 1 || height < 1) {"""
    if old_bg_cfg not in text:
        raise SystemExit("desktop-shell background_configure anchor missing")
    text = text.replace(old_bg_cfg, new_bg_cfg, 1)
    old_bg_draw = """background_draw(struct widget *widget, void *data)
{
\tstruct background *background = data;
\tcairo_surface_t *surface, *image;"""
    new_bg_draw = """background_draw(struct widget *widget, void *data)
{
\tstruct background *background = data;
\tcairo_surface_t *surface, *image;

\tWWN_SHELL_LOG("wwn desktop-shell: background_draw color=0x%08x\\n",
\t\t      background->color);"""
    if old_bg_draw not in text:
        raise SystemExit("desktop-shell background_draw anchor missing")
    text = text.replace(old_bg_draw, new_bg_draw, 1)
    old_panel_cfg = """panel_configure(void *data,
\t\tstruct weston_desktop_shell *desktop_shell,
\t\tuint32_t edges, struct window *window,
\t\tint32_t width, int32_t height)
{
\tstruct desktop *desktop = data;
\tstruct surface *surface = window_get_user_data(window);
\tstruct panel *panel = container_of(surface, struct panel, base);
\tstruct output *owner;

\tif (width < 1 || height < 1) {"""
    new_panel_cfg = """panel_configure(void *data,
\t\tstruct weston_desktop_shell *desktop_shell,
\t\tuint32_t edges, struct window *window,
\t\tint32_t width, int32_t height)
{
\tstruct desktop *desktop = data;
\tstruct surface *surface = window_get_user_data(window);
\tstruct panel *panel = container_of(surface, struct panel, base);
\tstruct output *owner;

\tWWN_SHELL_LOG("wwn desktop-shell: panel_configure %dx%d\\n",
\t\t      width, height);

\tif (width < 1 || height < 1) {"""
    if old_panel_cfg not in text:
        raise SystemExit("desktop-shell panel_configure anchor missing")
    text = text.replace(old_panel_cfg, new_panel_cfg, 1)
    old_clock_draw = """\tcr = widget_cairo_create(clock->panel->widget);
\tcairo_set_font_size(cr, 14);"""
    new_clock_draw = """\tcr = widget_cairo_create(clock->panel->widget);
\t/* Clear the clock allocation before drawing; otherwise each tick leaves
\t * ghost digits (especially visible with clock-format=seconds). */
\tcairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
\tset_hex_color(cr, clock->panel->color);
\tcairo_rectangle(cr, allocation.x, allocation.y,
\t\t\t allocation.width, allocation.height);
\tcairo_fill(cr);
\tcairo_set_operator(cr, CAIRO_OPERATOR_OVER);
\tcairo_set_font_size(cr, 14);"""
    if old_clock_draw not in text:
        raise SystemExit("desktop-shell panel_clock_redraw anchor missing")
    text = text.replace(old_clock_draw, new_clock_draw, 1)
    old_out_init_end = """\tweston_desktop_shell_set_background(desktop->shell,
\t\t\t\t\t    output->output, surface);
}"""
    new_out_init_end = """\tweston_desktop_shell_set_background(desktop->shell,
\t\t\t\t\t    output->output, surface);

\tWWN_SHELL_LOG("wwn desktop-shell: output_init panel=%p background=%p\\n",
\t\t      (void *)output->panel, (void *)output->background);
}"""
    if old_out_init_end not in text:
        raise SystemExit("desktop-shell output_init end anchor missing")
    text = text.replace(old_out_init_end, new_out_init_end, 1)
    old_launcher = """static void
panel_launcher_activate(struct panel_launcher *widget)
{
\tpid_t pid;

\tpid = fork();"""
    new_launcher = """static void
panel_launcher_activate(struct panel_launcher *widget)
{
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH)
\tWWN_SHELL_LOG("wwn desktop-shell: launcher activate path='%s' arg0='%s'\\n",
\t\t      widget->path ? widget->path : "(null)",
\t\t      widget->argp && widget->argp[0] ? widget->argp[0] : "(null)");
\twwn_launch_panel_client(widget->argp, widget->envp);
\treturn;
#endif
\tpid_t pid;

\tpid = fork();"""
    if "wwn_launch_panel_client" not in text:
        if old_launcher not in text:
            raise SystemExit("panel_launcher_activate anchor missing")
        text = text.replace(old_launcher, new_launcher, 1)
    path.write_text(text)
PY
      desktop_objs="$desktop_objs $(compile_only clients/mobile-desktop-shell.c -Dmain=weston_desktop_shell_main)"
    fi
    "$AR" rcs libweston-desktop-13.a $desktop_objs

    # --- weston-keyboard -> libweston-keyboard.a ---
    keyboard_objs="$(compile_only gen/input-method-unstable-v1-protocol.c)"
    keyboard_objs="$keyboard_objs $(compile_only clients/keyboard.c -Dmain=weston_keyboard_main)"
    "$AR" rcs libweston-keyboard.a $keyboard_objs

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp libweston-13.a $out/lib/
    cp libweston-terminal.a $out/lib/
    cp libweston-desktop-13.a $out/lib/
    cp libweston-keyboard.a $out/lib/
    cp wwn-mobile-clients.h $out/include/
    cp -r gen $out/include/weston-gen || true
  '';

  meta = with lib; {
    description = "Weston real toytoolkit + demo clients (iOS in-process static libs)";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
