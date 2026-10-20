/*
 * WLCS adapter for Wawona's production WWNCore C ABI.
 *
 * Compile against the WLCS headers from nixpkgs. Never mirror these structs:
 * WLCS has extended WlcsDisplayServer over time and a locally copied layout can
 * silently call the wrong function pointer.
 */

#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-util.h>
#include <wlcs/display_server.h>
#include <wlcs/pointer.h>
#include <wlcs/touch.h>

extern void *WWNCoreNew(void);
extern bool WWNCoreStart(void *core, const char *socket_name);
extern bool WWNCoreStop(void *core);
extern bool WWNCoreProcessEvents(void *core);
extern void WWNCoreFree(void *core);
extern int WWNCoreCreateTestClientSocket(void *core, uint32_t *out_client_id);
extern bool WWNCorePositionWindowForProtocolSurface(
    void *core, uint32_t client_id, uint32_t surface_id, int32_t x, int32_t y);
extern void WWNCoreInjectPointerMotionGlobal(
    void *core, double x, double y, uint32_t timestamp_ms);
extern void WWNCoreInjectPointerButtonGlobal(
    void *core, uint32_t button, uint32_t state, uint32_t timestamp_ms);
extern void WWNCoreInjectTouchDown(
    void *core, int32_t id, double x, double y, uint32_t timestamp_ms);
extern void WWNCoreInjectTouchMotion(
    void *core, int32_t id, double x, double y, uint32_t timestamp_ms);
extern void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp_ms);
extern void WWNCoreInject_touch_frame(void *core);
extern void WWNCoreFlushClients(void *core);
extern uint32_t WWNCorePresentRenderScene(void *core, uint32_t timestamp_ms);

typedef struct {
    int fd;
    uint32_t client_id;
} ClientRecord;

typedef struct {
    WlcsDisplayServer base;
    void *core;
    pthread_t event_thread;
    atomic_bool event_thread_running;
    ClientRecord *clients;
    size_t client_count;
    size_t client_capacity;
} WawonaWlcsServer;

typedef struct {
    WlcsPointer base;
    WawonaWlcsServer *server;
    double x;
    double y;
} WawonaWlcsPointer;

typedef struct {
    WlcsTouch base;
    WawonaWlcsServer *server;
    double x;
    double y;
    int32_t active_id;
} WawonaWlcsTouch;

static uint32_t timestamp_ms(void) {
    struct timespec ts = {0};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(((uint64_t)ts.tv_sec * 1000u) +
                      ((uint64_t)ts.tv_nsec / 1000000u));
}

/* Headless output refresh. Real hosts present after drawing; WLCS has no
 * display, so the harness presents the scene at this cadence instead. */
#define WAWONA_WLCS_REFRESH_MS 16u

static void *event_thread_main(void *opaque) {
    WawonaWlcsServer *server = opaque;
    uint32_t last_present = timestamp_ms();
    while (atomic_load_explicit(
        &server->event_thread_running, memory_order_acquire)) {
        (void)WWNCoreProcessEvents(server->core);
        uint32_t now = timestamp_ms();
        if (now - last_present >= WAWONA_WLCS_REFRESH_MS) {
            (void)WWNCorePresentRenderScene(server->core, now);
            last_present = now;
        }
        usleep(1000);
    }
    return NULL;
}

/*
 * WLCS skips every test whose interface is missing from this list, so it is
 * derived from the globals the core really advertises instead of a hand list
 * that drifts from src/core/wayland.
 */
static WlcsExtensionDescriptor *g_extensions;
static size_t g_extension_count;
static size_t g_extension_capacity;
static WlcsIntegrationDescriptor g_descriptor = {
    .version = WLCS_INTEGRATION_DESCRIPTOR_VERSION,
};
static pthread_once_t g_descriptor_once = PTHREAD_ONCE_INIT;

static void probe_registry_global(
    void *data, struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version) {
    (void)data;
    (void)registry;
    (void)name;
    for (size_t i = 0; i < g_extension_count; ++i) {
        if (strcmp(g_extensions[i].name, interface) == 0) {
            if (version > g_extensions[i].version) {
                g_extensions[i].version = version;
            }
            return;
        }
    }
    if (g_extension_count == g_extension_capacity) {
        size_t capacity = g_extension_capacity ? g_extension_capacity * 2 : 64;
        WlcsExtensionDescriptor *grown =
            realloc(g_extensions, capacity * sizeof(*grown));
        if (!grown) {
            return;
        }
        g_extensions = grown;
        g_extension_capacity = capacity;
    }
    char *copy = strdup(interface);
    if (!copy) {
        return;
    }
    g_extensions[g_extension_count++] =
        (WlcsExtensionDescriptor){.name = copy, .version = version};
}

static void probe_registry_global_remove(
    void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener kProbeRegistryListener = {
    .global = probe_registry_global,
    .global_remove = probe_registry_global_remove,
};

typedef struct {
    void *core;
    atomic_bool running;
} ProbeLoop;

static void *probe_thread_main(void *opaque) {
    ProbeLoop *loop = opaque;
    while (atomic_load_explicit(&loop->running, memory_order_acquire)) {
        (void)WWNCoreProcessEvents(loop->core);
        usleep(1000);
    }
    return NULL;
}

static void probe_advertised_globals(void) {
    ProbeLoop loop = {.core = WWNCoreNew()};
    if (!loop.core || !WWNCoreStart(loop.core, "wawona-wlcs-probe")) {
        abort();
    }
    atomic_init(&loop.running, true);
    pthread_t thread;
    if (pthread_create(&thread, NULL, probe_thread_main, &loop) != 0) {
        abort();
    }

    uint32_t client_id = 0;
    int fd = WWNCoreCreateTestClientSocket(loop.core, &client_id);
    struct wl_display *display = fd >= 0 ? wl_display_connect_to_fd(fd) : NULL;
    if (!display) {
        abort();
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &kProbeRegistryListener, NULL);
    if (wl_display_roundtrip(display) < 0 || g_extension_count == 0) {
        abort();
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(display);

    atomic_store_explicit(&loop.running, false, memory_order_release);
    pthread_join(thread, NULL);
    (void)WWNCoreStop(loop.core);
    WWNCoreFree(loop.core);

    g_descriptor.num_extensions = g_extension_count;
    g_descriptor.supported_extensions = g_extensions;
}

static const WlcsIntegrationDescriptor *wawona_get_descriptor(
    const WlcsDisplayServer *server) {
    (void)server;
    pthread_once(&g_descriptor_once, probe_advertised_globals);
    return &g_descriptor;
}

static void wawona_start(WlcsDisplayServer *display_server) {
    WawonaWlcsServer *server = (WawonaWlcsServer *)display_server;
    if (!server->core) {
        server->core = WWNCoreNew();
    }
    if (!server->core || !WWNCoreStart(server->core, "wawona-wlcs")) {
        abort();
    }
    atomic_store_explicit(
        &server->event_thread_running, true, memory_order_release);
    if (pthread_create(
            &server->event_thread, NULL, event_thread_main, server) != 0) {
        atomic_store(&server->event_thread_running, false);
        (void)WWNCoreStop(server->core);
        abort();
    }
}

static void wawona_stop(WlcsDisplayServer *display_server) {
    WawonaWlcsServer *server = (WawonaWlcsServer *)display_server;
    if (!server->core) {
        return;
    }
    if (atomic_exchange(&server->event_thread_running, false)) {
        pthread_join(server->event_thread, NULL);
    }
    (void)WWNCoreStop(server->core);
    server->client_count = 0;
}

static int wawona_create_client_socket(WlcsDisplayServer *display_server) {
    WawonaWlcsServer *server = (WawonaWlcsServer *)display_server;
    uint32_t client_id = 0;
    int fd = WWNCoreCreateTestClientSocket(server->core, &client_id);
    if (fd < 0) {
        return -1;
    }
    if (server->client_count == server->client_capacity) {
        size_t capacity = server->client_capacity ? server->client_capacity * 2 : 8;
        ClientRecord *clients =
            realloc(server->clients, capacity * sizeof(*clients));
        if (!clients) {
            close(fd);
            return -1;
        }
        server->clients = clients;
        server->client_capacity = capacity;
    }
    server->clients[server->client_count++] =
        (ClientRecord){.fd = fd, .client_id = client_id};
    return fd;
}

static uint32_t client_id_for_display(
    const WawonaWlcsServer *server, wl_display *display) {
    int fd = wl_display_get_fd(display);
    for (size_t i = server->client_count; i > 0; --i) {
        if (server->clients[i - 1].fd == fd) {
            return server->clients[i - 1].client_id;
        }
    }
    return 0;
}

static void wawona_position_window_absolute(
    WlcsDisplayServer *display_server,
    wl_display *client,
    wl_surface *surface,
    int x,
    int y) {
    WawonaWlcsServer *server = (WawonaWlcsServer *)display_server;
    uint32_t client_id = client_id_for_display(server, client);
    uint32_t surface_id = wl_proxy_get_id((struct wl_proxy *)surface);
    if (client_id != 0) {
        (void)WWNCorePositionWindowForProtocolSurface(
            server->core, client_id, surface_id, x, y);
    }
}

static void pointer_move_absolute(WlcsPointer *pointer, wl_fixed_t x, wl_fixed_t y) {
    WawonaWlcsPointer *p = (WawonaWlcsPointer *)pointer;
    p->x = wl_fixed_to_double(x);
    p->y = wl_fixed_to_double(y);
    WWNCoreInjectPointerMotionGlobal(
        p->server->core, p->x, p->y, timestamp_ms());
    WWNCoreFlushClients(p->server->core);
}

static void pointer_move_relative(
    WlcsPointer *pointer, wl_fixed_t dx, wl_fixed_t dy) {
    WawonaWlcsPointer *p = (WawonaWlcsPointer *)pointer;
    pointer_move_absolute(
        pointer,
        wl_fixed_from_double(p->x + wl_fixed_to_double(dx)),
        wl_fixed_from_double(p->y + wl_fixed_to_double(dy)));
}

static void pointer_button_up(WlcsPointer *pointer, int button) {
    WawonaWlcsPointer *p = (WawonaWlcsPointer *)pointer;
    WWNCoreInjectPointerButtonGlobal(
        p->server->core, (uint32_t)button, 0, timestamp_ms());
    WWNCoreFlushClients(p->server->core);
}

static void pointer_button_down(WlcsPointer *pointer, int button) {
    WawonaWlcsPointer *p = (WawonaWlcsPointer *)pointer;
    WWNCoreInjectPointerButtonGlobal(
        p->server->core, (uint32_t)button, 1, timestamp_ms());
    WWNCoreFlushClients(p->server->core);
}

static void pointer_destroy(WlcsPointer *pointer) {
    free(pointer);
}

static WlcsPointer *wawona_create_pointer(WlcsDisplayServer *display_server) {
    WawonaWlcsPointer *pointer = calloc(1, sizeof(*pointer));
    if (!pointer) {
        return NULL;
    }
    pointer->server = (WawonaWlcsServer *)display_server;
    pointer->base = (WlcsPointer){
        .version = WLCS_POINTER_VERSION,
        .move_absolute = pointer_move_absolute,
        .move_relative = pointer_move_relative,
        .button_up = pointer_button_up,
        .button_down = pointer_button_down,
        .destroy = pointer_destroy,
    };
    return &pointer->base;
}

static void touch_down(WlcsTouch *touch, wl_fixed_t x, wl_fixed_t y) {
    WawonaWlcsTouch *t = (WawonaWlcsTouch *)touch;
    t->x = wl_fixed_to_double(x);
    t->y = wl_fixed_to_double(y);
    t->active_id++;
    WWNCoreInjectTouchDown(
        t->server->core, t->active_id, t->x, t->y, timestamp_ms());
    WWNCoreInject_touch_frame(t->server->core);
    WWNCoreFlushClients(t->server->core);
}

static void touch_move(WlcsTouch *touch, wl_fixed_t x, wl_fixed_t y) {
    WawonaWlcsTouch *t = (WawonaWlcsTouch *)touch;
    t->x = wl_fixed_to_double(x);
    t->y = wl_fixed_to_double(y);
    WWNCoreInjectTouchMotion(
        t->server->core, t->active_id, t->x, t->y, timestamp_ms());
    WWNCoreInject_touch_frame(t->server->core);
    WWNCoreFlushClients(t->server->core);
}

static void touch_up(WlcsTouch *touch) {
    WawonaWlcsTouch *t = (WawonaWlcsTouch *)touch;
    WWNCoreInjectTouchUp(t->server->core, t->active_id, timestamp_ms());
    WWNCoreInject_touch_frame(t->server->core);
    WWNCoreFlushClients(t->server->core);
}

static void touch_destroy(WlcsTouch *touch) {
    free(touch);
}

static WlcsTouch *wawona_create_touch(WlcsDisplayServer *display_server) {
    WawonaWlcsTouch *touch = calloc(1, sizeof(*touch));
    if (!touch) {
        return NULL;
    }
    touch->server = (WawonaWlcsServer *)display_server;
    touch->active_id = -1;
    touch->base = (WlcsTouch){
        .version = WLCS_TOUCH_VERSION,
        .touch_down = touch_down,
        .touch_move = touch_move,
        .touch_up = touch_up,
        .destroy = touch_destroy,
    };
    return &touch->base;
}

static WlcsDisplayServer *wawona_create_server(
    int argc, char const **argv) {
    (void)argc;
    (void)argv;
    pthread_once(&g_descriptor_once, probe_advertised_globals);
    WawonaWlcsServer *server = calloc(1, sizeof(*server));
    if (!server) {
        return NULL;
    }
    server->core = WWNCoreNew();
    if (!server->core) {
        free(server);
        return NULL;
    }
    atomic_init(&server->event_thread_running, false);
    server->base = (WlcsDisplayServer){
        .version = WLCS_DISPLAY_SERVER_VERSION,
        .start = wawona_start,
        .stop = wawona_stop,
        .create_client_socket = wawona_create_client_socket,
        .position_window_absolute = wawona_position_window_absolute,
        .create_pointer = wawona_create_pointer,
        .create_touch = wawona_create_touch,
        .get_descriptor = wawona_get_descriptor,
        .start_on_this_thread = NULL,
    };
    return &server->base;
}

static void wawona_destroy_server(WlcsDisplayServer *display_server) {
    WawonaWlcsServer *server = (WawonaWlcsServer *)display_server;
    if (!server) {
        return;
    }
    if (server->core) {
        if (atomic_load(&server->event_thread_running)) {
            wawona_stop(display_server);
        }
        WWNCoreFree(server->core);
    }
    free(server->clients);
    free(server);
}

const WlcsServerIntegration wlcs_server_integration = {
    .version = WLCS_SERVER_INTEGRATION_VERSION,
    .create_server = wawona_create_server,
    .destroy_server = wawona_destroy_server,
};
