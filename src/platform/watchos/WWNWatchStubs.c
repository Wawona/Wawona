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

__attribute__((weak))
int fuzzel_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int niri_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int wawona_nvim_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
int wawona_coreutils_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

/* ssh_main / ssh_keygen_main / scp_main: provided by libwwn-ssh-cli.a (wwn-ssh). */

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
 * App Store–compliant in-process zsh wins at link time. */
__attribute__((weak))
int wawona_zsh_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return 1;
}

__attribute__((weak))
void wwn_ios_pump_host_compositor(void) {}

__attribute__((weak))
void wwn_ios_refresh_bundle_env(void) {}
