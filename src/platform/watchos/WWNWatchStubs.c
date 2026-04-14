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
