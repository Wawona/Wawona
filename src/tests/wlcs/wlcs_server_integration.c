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
#include <unistd.h>
#include <wayland-client-core.h>
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

static void *event_thread_main(void *opaque) {
    WawonaWlcsServer *server = opaque;
    while (atomic_load_explicit(
        &server->event_thread_running, memory_order_acquire)) {
        (void)WWNCoreProcessEvents(server->core);
        usleep(1000);
    }
    return NULL;
}

static const WlcsExtensionDescriptor kExtensions[] = {
    {.name = "xdg_shell", .version = 6},
};

static const WlcsIntegrationDescriptor kDescriptor = {
    .version = WLCS_INTEGRATION_DESCRIPTOR_VERSION,
    .num_extensions = sizeof(kExtensions) / sizeof(kExtensions[0]),
    .supported_extensions = kExtensions,
};

static const WlcsIntegrationDescriptor *wawona_get_descriptor(
    const WlcsDisplayServer *server) {
    (void)server;
    return &kDescriptor;
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
