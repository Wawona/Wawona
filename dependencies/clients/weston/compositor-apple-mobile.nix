# Weston nested compositor (wayland + headless backends), cross-compiled for Apple
# mobile as a single in-process static archive (libweston-compositor-13.a).
#
# Entry symbol: weston_compositor_main -> wet_main with cooperative shutdown via
# wwn_weston_compositor_shutdown_requested (volatile sig_atomic_t).
{
  lib,
  stdenv,
  pkgs,
  fetchurl,
  buildPackages,
  buildModule,
  simulator ? false,
  iosToolchain,
  ...
}:

let
  xcodeUtils = import ../../utils/xcode-wrapper.nix { inherit lib pkgs; };

  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  xkbcommon = buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  epollShim = buildModule.buildForIOS "epoll-shim" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  cairo = buildModule.buildForIOS "cairo" { inherit simulator; };
  pango = buildModule.buildForIOS "pango" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  glib = buildModule.buildForIOS "glib" { inherit simulator; };
  harfbuzz = buildModule.buildForIOS "harfbuzz" { inherit simulator; };
  fribidi = buildModule.buildForIOS "fribidi" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };

  crossDeps = [
    libwayland xkbcommon pixman cairo pango fontconfig freetype glib harfbuzz
    fribidi libpng expat libffi pcre2 epollShim
  ];
  pkgConfigPath = lib.concatStringsSep ":" (map (d: "${d}/lib/pkgconfig") crossDeps);
  crossPkgConfigDirs = lib.concatStringsSep "', '" (
    (map (d: "${d}/lib/pkgconfig") crossDeps)
    ++ [ "${buildPackages.wayland-protocols}/share/pkgconfig" ]
  );

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
      mkdir -p $out/bin $out/share/pkgconfig
      SCANNER_BIN=$(find build -name wayland-scanner -type f | head -n 1)
      [ -n "$SCANNER_BIN" ] || { echo "wayland-scanner not found" >&2; exit 1; }
      cp "$SCANNER_BIN" $out/bin/wayland-scanner
      cat > $out/share/pkgconfig/wayland-scanner.pc <<EOF
prefix=$out
exec_prefix=''${prefix}
bindir=''${exec_prefix}/bin
wayland_scanner=''${bindir}/wayland-scanner
Name: Wayland Scanner
Description: Wayland protocol scanner (host build)
Version: 1.25.0
EOF
    '';
  };

  platformInfo = import ../../toolchains/apple-mobile-platform.nix;
  mobile = platformInfo { inherit iosToolchain simulator; };
  isTVOS = mobile.isTVOS;
  isVisionOS = mobile.isVisionOS;
  isWatchOS = mobile.isWatchOS;
  mobileMinVersion = mobile.minVersion;
in
stdenv.mkDerivation rec {
  pname = "weston-compositor-apple-mobile";
  version = "13.0.0";
  __noChroot = true;

  src = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/weston/-/releases/${version}/downloads/weston-${version}.tar.xz";
    sha256 = "sha256-Uv8dSqI5Si5BbIWjOLYnzpf6cdQ+t2L9Sq8UXTb8eVo=";
  };

  wayland_cursor_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/cursor/wayland-cursor.h";
    sha256 = "sha256-DZ22b6sk+QbnKzZAEyug2QymprjDnnvyuc/cJcwV3zg=";
  };
  wayland_xcursor_h = fetchurl {
    url = "https://gitlab.freedesktop.org/wayland/wayland/-/raw/1.23.1/cursor/xcursor.h";
    sha256 = "sha256-l4vxxyzBImXkMIywX6/aalUU5lWAWs/i85/z+NCv+Jc=";
  };

  linuxHeadersRef = "45dcf5e28813954da4150e7260ccb61e95856176";
  drmHeadersRef = "8de45ef60d69472a0f8ba898f91250dac88bb81f";

  linux_input_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input.h";
    sha256 = "sha256-ciO4IN6ANMgnw/yBe2dApcUcqDMkgLhtagwUJzD7I54=";
  };
  linux_input_event_codes_h = fetchurl {
    url = "https://raw.githubusercontent.com/torvalds/linux/${linuxHeadersRef}/include/uapi/linux/input-event-codes.h";
    sha256 = "sha256-CqF1r2sCoJbn3Bcr0x6B1JnrqQg3d1FejCCqkVq3new=";
  };
  libdrm_fourcc_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm_fourcc.h";
    sha256 = "sha256-qFbvL2tD6PeyaHFZThkYZMVAoDcg1xwT7opFDSarxi0=";
  };
  libdrm_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm.h";
    sha256 = "sha256-+erb+g+eGurMJ/XJMco717RpdNutgXzQL+YBzLXN8I0=";
  };
  libdrm_mode_h = fetchurl {
    url = "https://gitlab.freedesktop.org/mesa/drm/-/raw/${drmHeadersRef}/include/drm/drm_mode.h";
    sha256 = "sha256-7kBowCbftshcZoy05B/5y/MOmcEMXn7yrRx4cNP5o78=";
  };

  nativeBuildInputs = [
    waylandScanner
    buildPackages.wayland-protocols
    buildPackages.meson
    buildPackages.ninja
    buildPackages.pkg-config
    buildPackages.python3
    buildPackages.bison
    buildPackages.flex
  ];

  buildInputs = [ ];

  mesonFlags = [
    "-Dbackend-drm=false"
    "-Dbackend-headless=true"
    "-Dbackend-rdp=false"
    "-Dbackend-vnc=false"
    "-Dbackend-pipewire=false"
    "-Dbackend-wayland=true"
    "-Dbackend-x11=false"
    "-Dxwayland=false"
    "-Dbackend-default=wayland"
    "-Drenderer-gl=false"
    "-Dimage-jpeg=false"
    "-Dimage-webp=false"
    "-Ddemo-clients=false"
    "-Dsimple-clients=[]"
    "-Dtest-junit-xml=false"
    "-Ddoc=false"
    "-Dpipewire=false"
    "-Dsystemd=false"
    "-Dcolor-management-lcms=false"
    "-Dshell-desktop=true"
    "-Dshell-fullscreen=false"
    "-Dshell-ivi=false"
    "-Dshell-kiosk=false"
    "-Dremoting=false"
    "-Dscreenshare=false"
    "-Dsystemd=false"
  ];

  postPatch = ''
    cp ${./mobile-weston-client-launch.c} compositor/mobile-weston-client-launch.c
    cp ${./wwn-mobile-clients.h} include/wwn-mobile-clients.h

    # Skip tests and client demos (compositor-only static archive)
    sed -i "/subdir('tests')/d" meson.build
    sed -i "/subdir('clients')/d" meson.build

    # Static in-process modules (no dlopen on iOS)
    sed -i 's/shared_library(/static_library(/g' libweston/backend-wayland/meson.build
    sed -i 's/shared_library(/static_library(/g' libweston/backend-headless/meson.build
    sed -i 's/shared_library(/static_library(/g' desktop-shell/meson.build
    sed -i "/subdir('wcap')/d" meson.build
    sed -i "/^exe_weston = executable(/,/^)/d" compositor/meson.build

    python3 - <<'PY'
from pathlib import Path
import re

def staticify_lib(path: Path, name: str) -> None:
    text = path.read_text()
    if f"{name} = shared_library(" not in text:
        if f"{name} = static_library(" in text:
            return
        raise SystemExit(f"{name} shared_library anchor not found in {path}")
    text = text.replace(f"{name} = shared_library(", f"{name} = static_library(", 1)
    # Remove kwargs invalid for static_library within this target block only.
    block_re = re.compile(
        rf"{re.escape(name)} = static_library\((.*?)\n\)",
        re.DOTALL,
    )
    m = block_re.search(text)
    if not m:
        raise SystemExit(f"{name} static_library block not found in {path}")
    block = m.group(1)
    block = re.sub(r"^\s*version:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*soversion:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*install_dir:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*install_rpath:.*\n", "", block, flags=re.MULTILINE)
    block = re.sub(r"^\s*name_prefix:.*\n", "", block, flags=re.MULTILINE)
    block = block.replace("install: true", "install: false")
    text = text[: m.start(1)] + block + text[m.end(1) :]
    path.write_text(text)

staticify_lib(Path("libweston/meson.build"), "lib_weston")
PY

    python3 - <<'PY'
from pathlib import Path
path = Path("compositor/meson.build")
text = path.read_text()
old = """libexec_weston = shared_library(
	'exec_weston',
	sources: srcs_weston,
	include_directories: common_inc,
	dependencies: deps_weston,
	install_dir: dir_module_weston,
	install: true,
	version: '0.0.0',
	soversion: 0
)"""
new = """libexec_weston = static_library(
	'exec_weston',
	sources: srcs_weston,
	include_directories: common_inc,
	dependencies: deps_weston,
	install: false
)"""
if old not in text:
    raise SystemExit("libexec_weston block not found")
path.write_text(text.replace(old, new, 1))
PY

    # Unique backend entry symbols (avoid duplicate weston_backend_init when linked)
    sed -i 's/^weston_backend_init(/wwn_weston_wayland_backend_init(/' libweston/backend-wayland/wayland.c
    sed -i 's/^weston_backend_init(/wwn_weston_headless_backend_init(/' libweston/backend-headless/headless.c
    sed -i 's/^wet_shell_init(/wwn_wet_desktop_shell_init(/' desktop-shell/shell.c

    # Replace libinput with empty stubs (same as macos.nix)
    touch include/empty.c
    mkdir -p include
    sed -i "s/'libinput-device.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.c'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-seat.h'/'..\/include\/empty.c'/g" libweston/meson.build
    sed -i "s/'libinput-device.h'/'..\/include\/empty.c'/g" libweston/meson.build

    sed -i "s|message('The default backend is ' + backend_default)|message('Skipping backend validation for mobile compositor build')|g" meson.build
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" meson.build
    sed -i "s/cc.find_library('pam'/cc.find_library('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('pam'/dependency('pam', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" libweston/meson.build
    sed -i "s/dependency('libudev'/dependency('libudev', required: false/g" clients/meson.build
    sed -i "s/error(/warning(/g" clients/meson.build
    sed -i "s/dependency('libevdev'/dependency('libevdev', required: false/g" clients/meson.build
    sed -i "s/dependency('gbm'/dependency('gbm', required: false/g" clients/meson.build
    sed -i "s/dependency('libdrm'/dependency('libdrm', required: false/g" clients/meson.build
    sed -i "s/dependency('libinput'/dependency('libinput', required: false/g" clients/meson.build
    sed -i "s/dep_libinput,//" compositor/meson.build
    sed -i "s/dep_libevdev,//" compositor/meson.build

    # Replace libinput backend with empty stub (no Linux input stack on Apple mobile)
    python3 - <<'PY'
from pathlib import Path
path = Path("libweston/meson.build")
text = path.read_text()
start = "lib_libinput_backend = static_library("
end = "dep_libinput_backend = declare_dependency("
si = text.find(start)
ei = text.find(end)
if si < 0 or ei < 0:
    raise SystemExit("libinput backend block not found")
# Include the full dep_libinput_backend declare_dependency(...) block.
close = text.find(")\n\ndep_vertex_clipping", ei)
if close < 0:
    raise SystemExit("libinput backend end anchor not found")
close += 2  # keep trailing newline before dep_vertex_clipping
stub = """lib_libinput_backend = static_library(
	'libinput-backend',
	'../include/empty.c',
	include_directories: common_inc,
	install: false
)
dep_libinput_backend = declare_dependency(
	link_with: lib_libinput_backend,
	include_directories: include_directories('.')
)

"""
path.write_text(text[:si] + stub + text[close:])
PY

    # Stub pkg-config for Linux-only deps (headers only; no runtime dlopen)
    cat > include/wwn-static-modules.h <<'EOF'
#ifndef WWN_STATIC_MODULES_H
#define WWN_STATIC_MODULES_H
#include <stddef.h>
#include <string.h>
struct weston_compositor;
struct weston_backend_config;
extern int wwn_weston_wayland_backend_init(struct weston_compositor *c, struct weston_backend_config *cfg);
extern int wwn_weston_headless_backend_init(struct weston_compositor *c, struct weston_backend_config *cfg);
extern int wwn_wet_desktop_shell_init(struct weston_compositor *ec, int *argc, char **argv);
extern volatile int wwn_weston_compositor_shutdown_requested;
static inline void *wwn_static_module_lookup(const char *name, const char *entrypoint) {
	if (!name || !entrypoint)
		return NULL;
	if (strcmp(entrypoint, "weston_backend_init") == 0) {
		if (strstr(name, "wayland-backend") != NULL)
			return (void *)wwn_weston_wayland_backend_init;
		if (strstr(name, "headless-backend") != NULL)
			return (void *)wwn_weston_headless_backend_init;
	}
	if (strcmp(entrypoint, "wet_shell_init") == 0 && strstr(name, "desktop-shell") != NULL)
		return (void *)wwn_wet_desktop_shell_init;
	return NULL;
}
#endif
EOF

    python3 - <<'PY'
from pathlib import Path

compositor = Path("libweston/compositor.c").read_text()
needle = '#include "backend.h"'
insert = needle + '\n#include "include/wwn-static-modules.h"'
if needle not in compositor:
    raise SystemExit("compositor.c include anchor missing")
compositor = compositor.replace(needle, insert, 1)
old = "\tmodule = dlopen(path, RTLD_NOW | RTLD_NOLOAD);"
new = """\t{
\t\tvoid *static_init = wwn_static_module_lookup(name, entrypoint);
\t\tif (static_init)
\t\t\treturn static_init;
\t}
\tmodule = dlopen(path, RTLD_NOW | RTLD_NOLOAD);"""
if old not in compositor:
    raise SystemExit("weston_load_module dlopen anchor missing")
compositor = compositor.replace(old, new, 1)
Path("libweston/compositor.c").write_text(compositor)

main = Path("compositor/main.c").read_text()
main = main.replace(
    "\twl_display_run(display);",
    """\twhile (!wwn_weston_compositor_shutdown_requested) {
\t\tif (wl_event_loop_dispatch(loop, 0) < 0)
\t\t\tbreak;
\t}""",
    1,
)
if "wwn-static-modules.h" not in main:
    main = main.replace(
        '#include "weston-private.h"',
        '#include "weston-private.h"\n#include "include/wwn-static-modules.h"',
        1,
    )
forward_decl = """
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
struct wet_process *
wwn_wet_client_launch_inprocess(struct weston_compositor *compositor,
				struct custom_env *child_env,
				int *no_cloexec_fds,
				size_t num_no_cloexec_fds,
				wet_process_cleanup_func_t cleanup,
				void *cleanup_data);
#endif
"""
wet_launch_anchor = "struct wet_process *\nwet_client_launch(struct weston_compositor *compositor,"
if "wwn_wet_client_launch_inprocess" not in main:
    if wet_launch_anchor not in main:
        raise SystemExit("wet_client_launch definition anchor missing")
    main = main.replace(
        wet_launch_anchor,
        forward_decl + "\n" + wet_launch_anchor,
        1,
    )
inprocess_hook = """
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
	{
		proc = wwn_wet_client_launch_inprocess(compositor, child_env,
					no_cloexec_fds, num_no_cloexec_fds,
					cleanup, cleanup_data);
		if (proc) {
			wl_list_insert(&wet->child_process_list, &proc->link);
			custom_env_fini(child_env);
			free(fail_exec);
			return proc;
		}
	}
#endif
"""
fork_anchor = "\tstr_printf(&fail_exec, \"Error: Couldn't launch client '%s'\\n\", argp[0]);\n\n\tpid = fork();"
if fork_anchor not in main:
    raise SystemExit("wet_client_launch fork anchor missing")
if inprocess_hook.strip() not in main:
    main = main.replace(
        fork_anchor,
        "\tstr_printf(&fail_exec, \"Error: Couldn't launch client '%s'\\n\", argp[0]);\n"
        + inprocess_hook
        + "\n\tpid = fork();",
        1,
    )
Path("compositor/main.c").write_text(main)
PY

    cat > compositor/wwn-weston-compositor-main.c <<'EOF'
#include "config.h"
#include <signal.h>
#include "weston.h"

volatile sig_atomic_t wwn_weston_compositor_shutdown_requested = 0;

int weston_compositor_main(int argc, char **argv)
{
	wwn_weston_compositor_shutdown_requested = 0;
	return wet_main(argc, argv, NULL);
}
EOF
    python3 - <<'PY'
from pathlib import Path
path = Path("compositor/meson.build")
text = path.read_text()
needle = "\t'main.c',"
insert = needle + "\n\t'wwn-weston-compositor-main.c',"
if needle not in text:
    raise SystemExit("main.c entry not found in compositor/meson.build")
if "wwn-weston-compositor-main.c" not in text:
    text = text.replace(needle, insert, 1)
needle2 = "\t'wwn-weston-compositor-main.c',"
insert2 = needle2 + "\n\t'mobile-weston-client-launch.c',"
if needle2 not in text:
    raise SystemExit("wwn-weston-compositor-main.c entry not found")
if "mobile-weston-client-launch.c" not in text:
    text = text.replace(needle2, insert2, 1)
path.write_text(text)
PY

    # Apple shims (mirror macos.nix)
    mkdir -p include/sys include/libudev include/libinput include/libevdev include/linux include/GLES2 include/EGL include/KHR

    cat > include/weston-macos-polyfills.h <<'EOF'
#ifndef WESTON_MACOS_POLYFILLS_H
#define WESTON_MACOS_POLYFILLS_H
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#ifdef __APPLE__
#include <TargetConditionals.h>
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
#define WESTON_HOWMANY(x, y) (((int)(x) + (int)(y) - 1) / (int)(y))
#define SOCK_CLOEXEC 0
#define SOCK_NONBLOCK 0
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
#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_WATCH
/* fork/exec/system are prohibited on Apple mobile sandboxes. */
static inline int wwn_weston_system(const char *cmd) { (void)cmd; return -1; }
#define system(cmd) wwn_weston_system(cmd)
static inline pid_t wwn_weston_fork(void) { return (pid_t)-1; }
#undef fork
#define fork() wwn_weston_fork()
#define execl(file, arg0, ...) (-1)
#define execlp(file, arg0, ...) (-1)
#define execve(file, argv, envp) (-1)
#define execv(file, argv) (-1)
#define execvp(file, argv) (-1)
#endif
#endif
#endif
EOF

    cat > include/libinput.h <<'EOF'
#ifndef _LIBINPUT_H
#define _LIBINPUT_H
#include <stdint.h>
struct libinput;
struct libinput_device;
struct libinput_event;
struct libinput_event_keyboard;
struct libinput_event_pointer;
struct libinput_seat;

enum libinput_led { LIBINPUT_LED_NUM_LOCK, LIBINPUT_LED_CAPS_LOCK, LIBINPUT_LED_SCROLL_LOCK };
enum libinput_key_state { LIBINPUT_KEY_STATE_RELEASED, LIBINPUT_KEY_STATE_PRESSED };
enum libinput_device_capability { LIBINPUT_DEVICE_CAP_POINTER, LIBINPUT_DEVICE_CAP_KEYBOARD, LIBINPUT_DEVICE_CAP_TOUCH };

enum libinput_config_scroll_method { LIBINPUT_CONFIG_SCROLL_NO_SCROLL, LIBINPUT_CONFIG_SCROLL_2FG, LIBINPUT_CONFIG_SCROLL_EDGE, LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN };
enum libinput_config_click_method { LIBINPUT_CONFIG_CLICK_METHOD_NONE, LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS, LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER };
enum libinput_config_tap_state { LIBINPUT_CONFIG_TAP_DISABLED, LIBINPUT_CONFIG_TAP_ENABLED };
enum libinput_config_tap_button_map { LIBINPUT_CONFIG_TAP_MAP_LRM, LIBINPUT_CONFIG_TAP_MAP_LMR };
enum libinput_config_send_events_mode { LIBINPUT_CONFIG_SEND_EVENTS_ENABLED, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED, LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE };
enum libinput_config_accel_profile { LIBINPUT_CONFIG_ACCEL_PROFILE_NONE, LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT, LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE };

static inline const char* libinput_device_get_name(struct libinput_device *d) { (void)d; return "apple-input"; }
static inline void* libinput_device_get_user_data(struct libinput_device *d) { (void)d; return (void*)0; }
static inline int libinput_device_has_capability(struct libinput_device *d, int c) { (void)d; (void)c; return 0; }
static inline int libinput_event_keyboard_get_key_state(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline int libinput_event_keyboard_get_seat_key_count(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline uint64_t libinput_event_keyboard_get_time_usec(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline uint32_t libinput_event_keyboard_get_key(struct libinput_event_keyboard *e) { (void)e; return 0; }
static inline void libinput_device_led_update(struct libinput_device *d, int l) { (void)d; (void)l; }
static inline void* libinput_event_keyboard_get_device(struct libinput_event_keyboard *e) { (void)e; return (void*)0; }

static inline uint32_t libinput_device_config_scroll_get_methods(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_scroll_set_method(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_scroll_set_button(struct libinput_device *d, uint32_t b) { (void)d; (void)b; return 0; }
static inline uint32_t libinput_device_config_click_get_methods(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_click_set_method(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_tap_get_finger_count(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_tap_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_tap_set_button_map(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline void libinput_device_config_tap_set_drag_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline void libinput_device_config_send_events_set_mode(struct libinput_device *d, int m) { (void)d; (void)m; }
static inline int libinput_device_config_accel_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_accel_set_speed(struct libinput_device *d, double s) { (void)d; (void)s; }
static inline void libinput_device_config_accel_set_profile(struct libinput_device *d, int p) { (void)d; (void)p; }
static inline uint32_t libinput_device_config_accel_get_profiles(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_left_handed_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_left_handed_set(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_middle_emulation_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_middle_emulation_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_natural_scroll_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_scroll_has_natural_scroll(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_scroll_set_natural_scroll_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
static inline int libinput_device_config_rotation_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_rotation_set_angle(struct libinput_device *d, double a) { (void)d; (void)a; }
static inline void libinput_device_config_calibration_set_matrix(struct libinput_device *d, const float m[6]) { (void)d; (void)m; }
static inline int libinput_device_config_tap_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline int libinput_device_config_dwt_is_available(struct libinput_device *d) { (void)d; return 0; }
static inline void libinput_device_config_dwt_set_enabled(struct libinput_device *d, int e) { (void)d; (void)e; }
#endif
EOF

    cat > include/libevdev/libevdev.h <<'EOF'
#ifndef _LIBEVDEV_H
#define _LIBEVDEV_H
struct libevdev;
#define EV_KEY 1
static inline int libevdev_event_code_from_name(unsigned int type, const char *name) { (void)type; (void)name; return -1; }
#endif
EOF

    cat > include/libudev.h <<'EOF'
#ifndef _LIBUDEV_H
#define _LIBUDEV_H
struct udev;
struct udev_device;
#endif
EOF

    cat > include/gbm.h <<'EOF'
#ifndef _GBM_H
#define _GBM_H
struct gbm_device;
struct gbm_bo;
struct gbm_surface;
#endif
EOF

    cat > include/pty.h <<'EOF'
#ifndef _PTY_H
#define _PTY_H
#include <util.h>
#endif
EOF

    cat > include/values.h <<'EOF'
#ifndef _VALUES_H
#define _VALUES_H
#include <limits.h>
#include <float.h>
#endif
EOF

    cat > include/alloca.h <<'EOF'
#ifndef _ALLOCA_H
#define _ALLOCA_H
#include <stdlib.h>
#endif
EOF

    cat > include/endian.h <<'EOF'
#ifndef _ENDIAN_H
#define _ENDIAN_H
#include <machine/endian.h>
#define __BYTE_ORDER BYTE_ORDER
#endif
EOF

    cp ${linux_input_h} include/linux/input.h
    cp ${linux_input_event_codes_h} include/linux/input-event-codes.h
    cat > include/linux/types.h <<'EOF'
#ifndef _LINUX_TYPES_H
#define _LINUX_TYPES_H
#include <stdint.h>
typedef uint8_t __u8; typedef uint16_t __u16; typedef uint32_t __u32; typedef uint64_t __u64;
typedef int8_t __s8; typedef int16_t __s16; typedef int32_t __s32; typedef int64_t __s64;
typedef uint16_t __le16; typedef uint32_t __le32; typedef uint64_t __le64;
#define __user
#define __BITS_PER_LONG 64
#endif
EOF
    cat > include/linux/ioctl.h <<'EOF'
#ifndef _LINUX_IOCTL_H
#define _LINUX_IOCTL_H
#include <sys/ioctl.h>
#endif
EOF
    cat > include/linux/limits.h <<'EOF'
#ifndef _LINUX_LIMITS_H
#define _LINUX_LIMITS_H
#include <limits.h>
#endif
EOF

    cp ${libdrm_fourcc_h} include/drm_fourcc.h
    cp ${libdrm_h} include/drm.h
    cp ${libdrm_mode_h} include/drm_mode.h
    cat > include/xf86drm.h <<'EOF'
#ifndef _XF86DRM_H
#define _XF86DRM_H
#include <stdint.h>
#define drmGetFormatModifierName(m) "INVALID"
#define drmGetFormatModifierVendor(m) "INVALID"
#endif
EOF

    # wayland-cursor headers (libwayland-ios ships the .a but not cursor/*.h)
    mkdir -p include/wayland
    cp ${wayland_cursor_h} include/wayland/wayland-cursor.h
    cp ${wayland_xcursor_h} include/wayland/xcursor.h

    cat > include/EGL/egl.h <<'EOF'
#ifndef _EGL_H
#define _EGL_H
typedef void *EGLDisplay;
typedef void *EGLContext;
typedef void *EGLSurface;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_NONE 0x3038
#endif
EOF
    touch include/EGL/eglext.h include/EGL/eglplatform.h include/GLES2/gl2.h include/GLES2/glext.h include/KHR/khrplatform.h
  '';

  preConfigure = ''
    ${iosToolchain.mkIOSBuildEnv { inherit simulator; minVersion = mobileMinVersion; }}

    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""
    export CC="$XCODE_CLANG"
    export CXX="$XCODE_CLANGXX"
    export PKG_CONFIG_PATH="$PWD/stub-pkgconfig:${waylandScanner}/share/pkgconfig:${pkgConfigPath}"

    mkdir -p stub-pkgconfig
    cat > stub-pkgconfig/libudev.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libudev
Version: 255
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libinput.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libinput
Version: 1.25.0
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libevdev.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libevdev
Version: 1.13.0
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/libdrm.pc <<EOF
prefix=$PWD
includedir=$PWD/include
Name: libdrm
Version: 2.4.120
Cflags: -I$PWD/include
EOF
    cat > stub-pkgconfig/wayland-scanner.pc <<EOF
prefix=${waylandScanner}
exec_prefix=''${prefix}
bindir=''${exec_prefix}/bin
wayland_scanner=${waylandScanner}/bin/wayland-scanner
Name: wayland-scanner
Description: Wayland protocol scanner
Version: 1.25.0
EOF

    # Meson runs wayland-scanner on the build machine during protocol codegen.
    MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    NATIVE_CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    NATIVE_CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"

    cat > native-file.txt <<EOF
[binaries]
c = '$NATIVE_CC'
cpp = '$NATIVE_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[built-in options]
c_args = ['-isysroot', '$MACOS_SDK_PATH']
cpp_args = ['-isysroot', '$MACOS_SDK_PATH']
c_link_args = ['-isysroot', '$MACOS_SDK_PATH']
cpp_link_args = ['-isysroot', '$MACOS_SDK_PATH']
pkg_config_path = ['$PWD/stub-pkgconfig', '${waylandScanner}/share/pkgconfig', '${buildPackages.wayland-protocols}/share/pkgconfig']
EOF

    _CC="$XCODE_CLANG"
    _CXX="$XCODE_CLANGXX"
    _SDK="$SDKROOT"
    _ARCH="$IOS_ARCH"
    _DEPLOY="$APPLE_DEPLOYMENT_FLAG"
    if [[ "''${APPLE_SDK_NAME:-}" == xros ]] || [[ "''${APPLE_SDK_NAME:-}" == xrsimulator ]]; then
      _TARGET="$APPLE_LINKER_TARGET"
      _DEPLOY=""
    else
      _TARGET=""
    fi

    EPOL_LINK="-L${epollShim}/lib -lepoll-shim"

    if [[ -n "$_TARGET" ]]; then
      cat > ios-cross-file.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
subsystem = '${mobile.mesonSubsystem}'

[built-in options]
c_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-D_DARWIN_C_SOURCE', '-I${epollShim}/include/libepoll-shim', '-I$PWD/include', '-I$PWD/include/wayland', '-include', '$PWD/include/weston-macos-polyfills.h', '-Dprogram_invocation_short_name=getprogname()', '-DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC', '-DCLOCK_REALTIME_COARSE=CLOCK_REALTIME']
cpp_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$PWD/include']
c_link_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
cpp_link_args = ['-target', '$_TARGET', '-isysroot', '$_SDK', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
pkg_config_path = ['$PWD/stub-pkgconfig', '${crossPkgConfigDirs}']
default_library = 'static'
EOF
    else
      cat > ios-cross-file.txt <<EOF
[binaries]
c = '$_CC'
cpp = '$_CXX'
ar = 'ar'
strip = 'strip'
pkg-config = '${buildPackages.pkg-config}/bin/pkg-config'
wayland-scanner = '${waylandScanner}/bin/wayland-scanner'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
subsystem = '${mobile.mesonSubsystem}'

[built-in options]
c_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-D_DARWIN_C_SOURCE', '-I${epollShim}/include/libepoll-shim', '-I$PWD/include', '-I$PWD/include/wayland', '-include', '$PWD/include/weston-macos-polyfills.h', '-Dprogram_invocation_short_name=getprogname()', '-DCLOCK_MONOTONIC_COARSE=CLOCK_MONOTONIC', '-DCLOCK_REALTIME_COARSE=CLOCK_REALTIME']
cpp_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-fPIC', '-D_DARWIN_C_SOURCE', '-I$PWD/include']
c_link_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
cpp_link_args = ['-arch', '$_ARCH', '-isysroot', '$_SDK', '$_DEPLOY', '-L${epollShim}/lib', '-lepoll-shim', '-L${libffi}/lib', '-lffi']
pkg_config_path = ['$PWD/stub-pkgconfig', '${crossPkgConfigDirs}']
default_library = 'static'
EOF
    fi
  '';

  configurePhase = ''
    runHook preConfigure
    unset SDKROOT
    export PKG_CONFIG_PATH="$PWD/stub-pkgconfig:${waylandScanner}/share/pkgconfig:${pkgConfigPath}"
    meson setup build \
      --prefix=$out \
      --libdir=$out/lib \
      --native-file=native-file.txt \
      --cross-file=ios-cross-file.txt \
      --default-library=static \
      ${lib.concatMapStringsSep " \\\n      " (f: f) mesonFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    meson compile -C build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include

    mapfile -t ARCHIVES < <(find build -name '*.a' -type f | sort)
    if [ "''${#ARCHIVES[@]}" -eq 0 ]; then
      echo "No static archives produced" >&2
      exit 1
    fi

    # libtool -static keeps duplicate libweston core objects from each backend
    # archive; extract into one directory so same-named .o files collapse.
    MERGE_DIR=$(mktemp -d)
    ROOT="$PWD"
    for a in "''${ARCHIVES[@]}"; do
      (cd "$MERGE_DIR" && ar x "$ROOT/$a") || exit 1
    done

    # weston-ios libweston-13.a already ships shared helpers + generated protocols +
    # toytoolkit clients. Drop those objects from the compositor fat archive so Xcode
    # can force_load both libraries without duplicate symbols.
    for pattern in \
      'os-compatibility.c.o' \
      'process-util.c.o' \
      'config-parser.c.o' \
      'option-parser.c.o' \
      'signal.c.o' \
      'file-util.c.o' \
      'hash.c.o' \
      'image-loader.c.o' \
      'cairo-util.c.o' \
      'frame.c.o' \
      '*matrix*.o' \
      'vertex-clipping.c.o' \
      'wayland-cursor.c.o' \
      'xcursor.c.o'; do
      find "$MERGE_DIR" -name "$pattern" -delete
    done

    dedupe_protocol_suffix() {
      local suffix="$1"
      mapfile -t matches < <(find "$MERGE_DIR" -name "*$suffix*.o" | sort)
      if [ "''${#matches[@]}" -gt 1 ]; then
        for f in "''${matches[@]:1}"; do rm -f "$f"; done
      fi
    }
    for suffix in \
      xdg-shell-protocol \
      xdg-shell-unstable-v6-protocol \
      xdg-output-unstable-v1-protocol \
      presentation; do
      dedupe_protocol_suffix "$suffix"
    done

    find "$MERGE_DIR" -name '*.o' -print0 | xargs -0 ar rcs $out/lib/libweston-compositor-13.a

    cp include/wwn-static-modules.h $out/include/ 2>/dev/null || true
    runHook postInstall
  '';

  meta = with lib; {
    description = "Weston nested compositor static archive for Apple mobile";
    homepage = "https://gitlab.freedesktop.org/wayland/weston";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
