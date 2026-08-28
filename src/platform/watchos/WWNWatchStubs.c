// WWNWatchStubs.c
// Compile-time safety stubs for watchOS.
//
// These weak definitions allow the project to link in plain Xcode without Nix.
// After `nix run .#xcodegen`, -force_load brings in the real implementations
// from the Nix-built static archives (libweston_simple_shm.a, libweston-13.a,
// libfoot.a, libwaypipe.a, etc.) which override these at link time.
//
// The Rust compositor C-API stubs (libwawona.a) return no-ops so the bridge
// falls through to WWNMiniWaylandServer.

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <signal.h>

typedef void *WawonaCompositorHandle;

typedef struct {
    uint64_t window_id;
    uint32_t surface_id;
    uint64_t buffer_id;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
    uint32_t format;
    uint8_t *pixels;
    size_t size;
    size_t capacity;
    uint32_t iosurface_id;
} WatchCBufferData;

// ── Rust compositor C-API stubs ──────────────────────────────────────────────

__attribute__((weak))
WawonaCompositorHandle wawona_compositor_create(const char *socket_name) {
    (void)socket_name;
    return NULL;
}

__attribute__((weak))
int wawona_compositor_dispatch(WawonaCompositorHandle handle) {
    (void)handle;
    return 1;
}

__attribute__((weak))
void wawona_compositor_destroy(WawonaCompositorHandle handle) {
    (void)handle;
}

__attribute__((weak))
WatchCBufferData *wawona_compositor_pop_buffer(WawonaCompositorHandle handle) {
    (void)handle;
    return NULL;
}

__attribute__((weak))
void wawona_buffer_free(WatchCBufferData *buf) {
    (void)buf;
}

// ── Wayland client entry-point stubs ─────────────────────────────────────────
// Overridden by -force_load'd Nix-built static libraries.

__attribute__((weak))
int weston_simple_shm_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 0;
}

__attribute__((weak))
int weston_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 0;
}

__attribute__((weak))
int wwn_weston_is_compat_shim(void) {
    return 1;
}

__attribute__((weak))
int weston_terminal_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 0;
}

__attribute__((weak))
int wwn_weston_terminal_is_compat_shim(void) {
    return 1;
}

__attribute__((weak))
int foot_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 0;
}

__attribute__((weak))
int wwn_foot_is_compat_shim(void) {
    return 1;
}

__attribute__((weak))
int niri_main(void) {
    return 127;
}

/* GLES/VK clients: weak stubs for baseline watch builds only. When
 * WWN_WATCH_SWIFTSHADER_BUNDLED is set, omit these so -Wl,-u pulls the real
 * *_main from libweston-13.a / libopengl_cube.a / libvkcube.a (same rule as
 * phoon_main: a weak stub satisfies -u and blocks the archive member). */
#ifndef WWN_WATCH_SWIFTSHADER_BUNDLED
__attribute__((weak))
int simple_egl_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 127;
}

__attribute__((weak))
int opengl_cube_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 127;
}

__attribute__((weak))
int vkcube_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 127;
}

__attribute__((weak))
int kmscube_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 127;
}

__attribute__((weak))
int gbm_es2_demo_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 127;
}
#endif

// ── Waypipe stub ─────────────────────────────────────────────────────────────
// Overridden by libwaypipe.a when linked. The bridge nil-checks the weak
// symbol before calling.

__attribute__((weak))
int waypipe_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

// ── Extra client / host helpers referenced by force-loaded weston/pty ────────
// watchOS LDFLAGS historically omitted xkb/zsh/openssh client archives; keep
// weak stubs so Debug sim links while deps catch up (ISSUE-017).

__attribute__((weak))
int fastfetch_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

/* No phoon_main stub: wwn-phoon-rs (libphoon_rs.a) is lazy-linked on watchOS
 * (-lphoon_rs + -Wl,-u,_phoon_main; std dedupes against niri's force-load), so
 * the real phoon_main is always pulled. A weak stub here would satisfy the -u
 * and stop the archive member from being linked. */

__attribute__((weak))
int fuzzel_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int wawona_nvim_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

/* wawona_coreutils_main lives in libwawona.a (uutils feature enabled on
 * watchOS) and is pulled via -Wl,-u,_wawona_coreutils_main. Same rule as
 * phoon_main above: a weak stub here would satisfy the -u and STOP the real
 * archive member (and all uutils applets) from linking. So only define the
 * stub on the arm64_32 slice, which links no derivedRustLib (see
 * xcodegen.nix OTHER_LDFLAGS[arch=arm64_32]) and therefore needs a fallback.
 * arm64 device + arm64 simulator are LP64 and link the real dispatcher. */
#if !defined(__LP64__)
__attribute__((weak))
int wawona_coreutils_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

/* WWNLog.h always calls the Rust log ring. arm64_32 does not link
 * libwawona.a (Nix watch archives are arm64-only). */
__attribute__((weak))
void wwn_log_ring_append(const char *module, const char *msg) {
    (void)module;
    (void)msg;
}

__attribute__((weak))
void wwn_log_ring_set_machine(const char *machine_id) {
    (void)machine_id;
}

__attribute__((weak))
char *wwn_log_ring_dump(const char *machine_id_or_null) {
    (void)machine_id_or_null;
    return NULL;
}

__attribute__((weak))
char *wwn_github_bug_report_url(const char *platform,
                                const char *install_channel,
                                const char *wawona_version,
                                const char *host_os, const char *logs) {
    (void)platform;
    (void)install_channel;
    (void)wawona_version;
    (void)host_os;
    (void)logs;
    return NULL;
}

__attribute__((weak))
void WWNStringFree(char *s) {
    (void)s;
}
#endif

/* ssh_main / ssh_keygen_main / scp_main: real impls from libwwn-ssh-cli on
 * arm64; weak stubs keep the arm64_32 fat slice linking (ASC 90733). */
__attribute__((weak))
int ssh_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int ssh_keygen_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int scp_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int weston_compositor_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
volatile sig_atomic_t wwn_weston_compositor_shutdown_requested;

/* Mini Wayland server. WWNMiniWaylandServer.c is excluded on arm64_32
 * (needs libwayland-server). Weak stubs; arm64 uses the real .c. */
typedef struct WWNMiniWaylandServer WWNMiniWaylandServer;
typedef void (*WWNFrameCallback)(const uint8_t *, uint32_t, uint32_t, uint32_t, void *);

__attribute__((weak))
WWNMiniWaylandServer *wwn_wls_create(const char *socket_name,
                                     uint32_t output_width,
                                     uint32_t output_height,
                                     WWNFrameCallback cb,
                                     void *userdata) {
    (void)socket_name; (void)output_width; (void)output_height;
    (void)cb; (void)userdata;
    return NULL;
}

__attribute__((weak))
int wwn_wls_dispatch(WWNMiniWaylandServer *srv, int timeout_ms) {
    (void)srv; (void)timeout_ms;
    return 0;
}

__attribute__((weak))
int wwn_wls_attach_inprocess_client(WWNMiniWaylandServer *srv) {
    (void)srv;
    return -1;
}

__attribute__((weak))
void wwn_wls_set_fill_host(WWNMiniWaylandServer *srv, int fill_host) {
    (void)srv;
    (void)fill_host;
}

__attribute__((weak))
void wwn_wls_destroy(WWNMiniWaylandServer *srv) {
    (void)srv;
}

/* Keyboard input injection (real impls in WWNMiniWaylandServer.c, arm64 only).
 * arm64_32 links no mini server, so these weak fallbacks keep the fat slice
 * linking; WWNWatchCompositorBridge nil-checks the server before calling. */
__attribute__((weak))
void wwn_wls_feed_text(WWNMiniWaylandServer *srv, const char *utf8) {
    (void)srv; (void)utf8;
}

__attribute__((weak))
void wwn_wls_feed_key(WWNMiniWaylandServer *srv, uint32_t evdev_keycode,
                      int pressed) {
    (void)srv; (void)evdev_keycode; (void)pressed;
}

/* Weston toytoolkit demo clients referenced by wawona-dispatch tables. */
#define WWN_WATCH_CLIENT_STUB(name) \
    __attribute__((weak)) int name(int argc, char **argv) { \
        (void)argc; (void)argv; \
        return 127; \
    }
WWN_WATCH_CLIENT_STUB(flower_main)
WWN_WATCH_CLIENT_STUB(clickdot_main)
WWN_WATCH_CLIENT_STUB(smoke_main)
WWN_WATCH_CLIENT_STUB(eventdemo_main)
WWN_WATCH_CLIENT_STUB(resizor_main)
WWN_WATCH_CLIENT_STUB(cliptest_main)
WWN_WATCH_CLIENT_STUB(transformed_main)
WWN_WATCH_CLIENT_STUB(stacking_main)
WWN_WATCH_CLIENT_STUB(dnd_main)
WWN_WATCH_CLIENT_STUB(image_main)
WWN_WATCH_CLIENT_STUB(scaler_main)
WWN_WATCH_CLIENT_STUB(editor_main)
WWN_WATCH_CLIENT_STUB(constraints_main)
#undef WWN_WATCH_CLIENT_STUB

/* Weak fallback only. xcodegen -force_load's libwawona-zsh.a so the real
 * App Store-compliant in-process zsh wins at link time. */
__attribute__((weak))
int wawona_zsh_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
void wwn_ios_pump_host_compositor(void) {}

/* Weak fallback only. WWNWatchShellEnvironment.m provides the real
 * wwn_ios_refresh_bundle_env that applies share-tree + rootfs shell env. */
__attribute__((weak))
void wwn_ios_refresh_bundle_env(void) {}

/* Weak fallback; real definition is in libwawona-pty.a. */
__attribute__((weak))
void wwn_pty_ios_allow_new_shell_session(void) {}

/* wwn-wasm is size-gated off watchOS, so there is no libwawona_wasm.a.
 * libwwn-pty dispatch still references these when -u pulls dispatch.o.
 * Darwin treats those externs as strong undefs. Weak stubs keep the
 * companion linking. Do not add -Wl,-u for these on watch. */
__attribute__((weak))
int wawona_wasm_run(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int wawona_wasm_can_run(const char *path) {
    (void)path;
    return 0;
}

__attribute__((weak))
int wpm_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}
