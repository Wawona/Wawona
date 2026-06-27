# Weston real toytoolkit + demo clients, cross-compiled for Android (NDK) as in-process
# static libraries (mirrors ios.nix; not the old placeholder .so shim).
#
# Compiles clients/window.c and cairo/SHM demo clients with the NDK, linking against
# the cross cairo/pango stack. Each demo `main` is renamed to `<name>_main`. Output
# archives are static-linked into libwawona.so (whole-archive) at app build time.
{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  androidToolchain ? (import ../../toolchains/android.nix { inherit lib pkgs; }),
  ...
}:

let
  libwayland = buildModule.buildForAndroid "libwayland" { };
  xkbcommon = buildModule.buildForAndroid "xkbcommon" { };
  cairo = buildModule.buildForAndroid "cairo" { };
  pango = buildModule.buildForAndroid "pango" { };
  fontconfig = buildModule.buildForAndroid "fontconfig" { };
  freetype = buildModule.buildForAndroid "freetype" { };
  glib = buildModule.buildForAndroid "glib" { };
  harfbuzz = buildModule.buildForAndroid "harfbuzz" { };
  fribidi = buildModule.buildForAndroid "fribidi" { };
  pixman = buildModule.buildForAndroid "pixman" { };
  libpng = buildModule.buildForAndroid "libpng" { };
  expat = buildModule.buildForAndroid "expat" { };
  libffi = buildModule.buildForAndroid "libffi" { };
  pcre2 = buildModule.buildForAndroid "pcre2" { };
  libintl = buildModule.buildForAndroid "libintl" { };

  pkgConfigPath = lib.concatStringsSep ":" (map (d: "${d}/lib/pkgconfig") [
    cairo pango fontconfig freetype glib harfbuzz fribidi pixman libpng
    expat libffi pcre2 libintl xkbcommon libwayland
  ]);

  waylandScanner = buildPackages.stdenv.mkDerivation {
    name = "wayland-scanner-host-weston-android";
    src = pkgs.wayland.src;
    depsBuildBuild = with buildPackages; [ libxml2 expat ];
    nativeBuildInputs = with buildPackages; [
      meson
      ninja
      pkg-config
      python3
      libxml2
      expat
    ];
    configurePhase = ''
      export PKG_CONFIG_PATH="${buildPackages.libxml2.dev}/lib/pkgconfig:${buildPackages.expat.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      meson setup build \
        --prefix=$out \
        -Dlibraries=false \
        -Ddocumentation=false \
        -Dtests=false
    '';
    buildPhase = ''
      meson compile -C build wayland-scanner
    '';
    installPhase = ''
      mkdir -p $out/bin
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
    '';
  };

  clients = [
    "flower" "clickdot" "smoke" "eventdemo" "resizor" "cliptest"
    "transformed" "stacking" "dnd" "image" "scaler"
    "editor" "constraints"
  ];

  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54=";
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "weston-android";
  version = "13.0.0";

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  waylandSrc = pkgs.wayland.src;

  nativeBuildInputs = [
    waylandScanner
    buildPackages.wayland-protocols
    buildPackages.pkg-config
    buildPackages.python3
  ];

  buildPhase = ''
    runHook preBuild

    CC="${androidToolchain.androidCC}"
    AR="${androidToolchain.androidAR}"
    RANLIB="${androidToolchain.androidRANLIB}"
    export PKG_CONFIG_PATH="${pkgConfigPath}"
    PKGCONF="${buildPackages.pkg-config}/bin/pkg-config"
    DEP_CFLAGS=$($PKGCONF --cflags cairo pango pangocairo fontconfig freetype2 harfbuzz fribidi glib-2.0 gobject-2.0 libpng pixman-1 xkbcommon wayland-client wayland-cursor)

    mkdir -p gen include/linux
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
    gen_proto text-cursor-position           "protocol/text-cursor-position.xml"
    gen_proto ivi-application                "protocol/ivi-application.xml"

    cat > config.h <<'EOF'
#ifndef WESTON_CONFIG_H
#define WESTON_CONFIG_H
#define PACKAGE_STRING "weston 13.0.0"
#define PACKAGE_VERSION "13.0.0"
#define HAVE_PANGO 1
#define HAVE_XKBCOMMON_COMPOSE 1
#define DATADIR "/usr/share"
#define BINDIR "/usr/bin"
#define LIBEXECDIR "/usr/libexec"
#define MODULEDIR "/usr/lib/weston"
#define LIBWESTON_MODULEDIR "/usr/lib/libweston"
#endif
EOF

    cat > include/android-polyfills.h <<'EOF'
#ifndef WESTON_ANDROID_POLYFILLS_H
#define WESTON_ANDROID_POLYFILLS_H
#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#ifndef WESTON_HOWMANY
#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
#endif
#endif
EOF

    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h

    mkdir -p wlsrc && tar xf ${waylandSrc} -C wlsrc
    WLCURSOR=$(echo wlsrc/wayland-*/cursor)

    POLYFILLS="$PWD/include/android-polyfills.h"
    CFLAGS="-fPIC -O2 \
      -I. -Iinclude -Igen \
      -idirafter shared \
      -I$WLCURSOR \
      -I${libwayland}/include \
      -I${libintl}/include \
      -Dprogram_invocation_short_name=getprogname() \
      -DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC -DCLOCK_REALTIME_COARSE=CLOCK_REALTIME \
      $DEP_CFLAGS"

    objs=()
    compile() {
      local src="$1"; shift
      local obj="$(echo "$src" | tr '/.' '__').o"
      echo "CC $src"
      "$CC" -c "$src" -include "$POLYFILLS" $CFLAGS "$@" -o "$obj"
      objs+=("$obj")
    }

    for s in shared/config-parser.c shared/option-parser.c shared/signal.c \
             shared/file-util.c shared/os-compatibility.c shared/process-util.c \
             shared/hash.c shared/image-loader.c shared/cairo-util.c shared/frame.c \
             shared/matrix.c libweston/vertex-clipping.c; do
      compile "$s"
    done

    compile "$WLCURSOR/wayland-cursor.c"
    compile "$WLCURSOR/xcursor.c"

    for p in gen/*-protocol.c; do compile "$p"; done
    compile clients/window.c

    for c in ${lib.concatStringsSep " " clients}; do
      sym=$(echo "$c" | tr '-' '_')
      compile "clients/$c.c" "-Dmain=''${sym}_main"
    done

    cat > weston_main.c <<'EOF'
extern int flower_main(int argc, char **argv);
int wwn_weston_is_compat_shim(void) { return 0; }
int wwn_weston_is_real_toytoolkit(void) { return 1; }
int weston_main(int argc, char **argv) {
  (void)argc; (void)argv;
  char *a[] = { "weston-flower", 0 };
  return flower_main(1, a);
}
EOF
    compile weston_main.c
    "$AR" rcs libweston-13.a "''${objs[@]}"
    if command -v "$RANLIB" >/dev/null 2>&1; then
      "$RANLIB" libweston-13.a
    fi

    cp ${./mobile-weston-terminal.c} ./mobile-weston-terminal.c
    "$CC" -c mobile-weston-terminal.c -include "$POLYFILLS" $CFLAGS -o weston_terminal.o
    "$AR" rcs libweston-terminal.a weston_terminal.o

    cat > weston_desktop_stub.c <<'EOF'
int wwn_weston_desktop_stub(void) { return 0; }
EOF
    "$CC" -c weston_desktop_stub.c -include "$POLYFILLS" $CFLAGS -o weston_desktop_stub.o
    "$AR" rcs libweston-desktop-13.a weston_desktop_stub.o

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    cp libweston-13.a $out/lib/
    cp libweston-terminal.a $out/lib/
    cp libweston-desktop-13.a $out/lib/
    if [ -d gen ]; then cp -r gen $out/include/weston-gen; fi
    runHook postInstall
  '';

  meta = with lib; {
    description = "Weston real toytoolkit + demo clients (Android NDK static libs)";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
