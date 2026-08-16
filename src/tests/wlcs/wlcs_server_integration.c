/*
 * WLCS server integration skeleton (ci-l2-wlcs).
 *
 * WLCS (Wayland Conformance Test Suite) loads a compositor-provided shared
 * object that exports the `wlcs_server_integration` symbol. WLCS drives the
 * compositor through the WlcsDisplayServer vtable (start/stop, create client
 * connections, position/move windows) and runs its protocol test battery.
 *
 * This is a SKELETON: it wires the ABI surface and delegates to the Wawona
 * compositor, but the in-process client-socket + window-manipulation hooks are
 * left as clearly-marked TODOs. Linux runtime (actually running the WLCS
 * battery) is deferred to CI. See dependencies/tests/wlcs.nix and the nightly
 * full-matrix workflow.
 *
 * ABI reference: https://github.com/MirServer/wlcs (include/wlcs/display_server.h)
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

/* --- Minimal subset of the WLCS ABI (mirrors wlcs headers) --------------- */

typedef struct WlcsDisplayServer WlcsDisplayServer;
typedef struct WlcsPointer WlcsPointer;
typedef struct WlcsTouch WlcsTouch;

typedef struct WlcsIntegrationDescriptor {
    uint32_t version;
    /* extension list omitted in skeleton */
} WlcsIntegrationDescriptor;

struct WlcsDisplayServer {
    uint32_t version;

    void (*start)(WlcsDisplayServer* server);
    void (*stop)(WlcsDisplayServer* server);

    int (*create_client_socket)(WlcsDisplayServer* server);

    void (*position_window_absolute)(WlcsDisplayServer* server,
                                     void* wl_surface, int x, int y);

    WlcsPointer* (*create_pointer)(WlcsDisplayServer* server);
    WlcsTouch* (*create_touch)(WlcsDisplayServer* server);

    const WlcsIntegrationDescriptor* (*get_descriptor)(
        const WlcsDisplayServer* server);

    /* Newer optional hooks omitted in skeleton (start_on_this_thread, ...). */
};

typedef struct WlcsServerIntegration {
    uint32_t version;
    WlcsDisplayServer* (*create_server)(int argc, char const** argv);
    void (*destroy_server)(WlcsDisplayServer* server);
} WlcsServerIntegration;

/* --- Wawona display-server shim ------------------------------------------ */

typedef struct WawonaWlcsServer {
    WlcsDisplayServer base;
    /* TODO: handle to the in-process Wawona compositor + its event loop. */
    void* compositor;
} WawonaWlcsServer;

static const WlcsIntegrationDescriptor kDescriptor = { .version = 1 };

static const WlcsIntegrationDescriptor* wawona_get_descriptor(
    const WlcsDisplayServer* server) {
    (void)server;
    return &kDescriptor;
}

static void wawona_start(WlcsDisplayServer* server) {
    (void)server;
    /* TODO: boot the Wawona compositor core on its own thread and bring up a
     * Wayland listening socket that create_client_socket() can hand out fds
     * for. Reuse the FFI used by the compositor-host binary. */
}

static void wawona_stop(WlcsDisplayServer* server) {
    (void)server;
    /* TODO: signal the compositor event loop to exit and join the thread. */
}

static int wawona_create_client_socket(WlcsDisplayServer* server) {
    (void)server;
    /* TODO: socketpair(); register the server end with the compositor's
     * wayland_server Display; return the client end fd. Return -1 until wired
     * so WLCS reports a clear failure rather than hanging. */
    return -1;
}

static void wawona_position_window_absolute(WlcsDisplayServer* server,
                                            void* wl_surface, int x, int y) {
    (void)server;
    (void)wl_surface;
    (void)x;
    (void)y;
    /* TODO: map wl_surface -> window and set its absolute position. */
}

static WlcsPointer* wawona_create_pointer(WlcsDisplayServer* server) {
    (void)server;
    return NULL; /* TODO: expose a synthetic pointer device. */
}

static WlcsTouch* wawona_create_touch(WlcsDisplayServer* server) {
    (void)server;
    return NULL; /* TODO: expose a synthetic touch device. */
}

static WlcsDisplayServer* wawona_create_server(int argc, char const** argv) {
    (void)argc;
    (void)argv;
    WawonaWlcsServer* s = calloc(1, sizeof(*s));
    if (!s) {
        return NULL;
    }
    s->base.version = 1;
    s->base.start = wawona_start;
    s->base.stop = wawona_stop;
    s->base.create_client_socket = wawona_create_client_socket;
    s->base.position_window_absolute = wawona_position_window_absolute;
    s->base.create_pointer = wawona_create_pointer;
    s->base.create_touch = wawona_create_touch;
    s->base.get_descriptor = wawona_get_descriptor;
    return &s->base;
}

static void wawona_destroy_server(WlcsDisplayServer* server) {
    free(server);
}

/* WLCS looks up this symbol by name in the loaded .so. */
const WlcsServerIntegration wlcs_server_integration = {
    .version = 1,
    .create_server = wawona_create_server,
    .destroy_server = wawona_destroy_server,
};
