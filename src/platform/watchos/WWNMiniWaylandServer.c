// WWNMiniWaylandServer.c
// Minimal in-process Wayland compositor for watchOS.
//
// Implements just enough of the Wayland protocol for weston-simple-shm
// (and any other wl_shm client) to connect and commit pixel buffers:
//   wl_display · wl_registry · wl_compositor · wl_shm · wl_shm_pool
//   wl_buffer · wl_surface · wl_shell · wl_shell_surface
//   wl_output · wl_seat (stub)
//
// When libwayland-server.a is not linked (local Xcode build before Nix build)
// all public functions return NULL/0 silently.

#include "WWNMiniWaylandServer.h"

// Compile the real implementation only when wayland-server.h is reachable.
#if __has_include(<wayland/wayland-server.h>)
#  define WWN_WL_SERVER_AVAILABLE 1
#  include <wayland/wayland-server.h>
#  include <wayland/wayland-server-protocol.h>
// XDG shell server protocol (generated from xdg-shell.xml by wayland-scanner
// in libwayland/watchos.nix; provides xdg_wm_base_interface, xdg_surface_interface, etc.)
#  if __has_include(<wayland/xdg-shell-server-protocol.h>)
#    define WWN_XDG_SHELL_AVAILABLE 1
#    include <wayland/xdg-shell-server-protocol.h>
#  endif
#elif __has_include("wayland-server.h")
#  define WWN_WL_SERVER_AVAILABLE 1
#  include "wayland-server.h"
#  include "wayland-server-protocol.h"
#  if __has_include("xdg-shell-server-protocol.h")
#    define WWN_XDG_SHELL_AVAILABLE 1
#    include "xdg-shell-server-protocol.h"
#  endif
#endif

#ifdef WWN_WL_SERVER_AVAILABLE

#include <sys/mman.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

// ── Server root ───────────────────────────────────────────────────────────────

struct WWNMiniWaylandServer {
    struct wl_display    *display;
    struct wl_event_loop *loop;

    struct wl_global *compositor_global;
    struct wl_global *shm_global;
    struct wl_global *xdg_wm_base_global; // primary (Weston 12+)
    struct wl_global *shell_global;        // legacy fallback
    struct wl_global *output_global;
    struct wl_global *seat_global;

    uint32_t output_width;
    uint32_t output_height;

    WWNFrameCallback frame_cb;
    void            *userdata;
};

// ── Helper: send frame done callback ─────────────────────────────────────────

static void notify_frame(struct WWNMiniWaylandServer *srv,
                          const uint8_t *pixels,
                          uint32_t w, uint32_t h, uint32_t stride)
{
    if (srv->frame_cb)
        srv->frame_cb(pixels, w, h, stride, srv->userdata);
}

// ── wl_shm_pool (forward declaration — needed by WWNBuffer) ───────────────────

typedef struct {
    struct wl_resource *resource;
    uint8_t            *data;
    size_t              size;
    // Reference count: 1 for the pool resource itself + 1 per live buffer.
    // The mapped memory is freed only when refcount drops to zero, preventing
    // use-after-free when a client destroys the pool before its buffers.
    int                 refcount;
} WWNPool;

// Decrement the pool refcount; free when it reaches zero.
static void pool_release(WWNPool *pool)
{
    if (!pool) return;
    if (--pool->refcount <= 0) {
        if (pool->data) munmap(pool->data, pool->size);
        free(pool);
    }
}

// ── wl_buffer ─────────────────────────────────────────────────────────────────

typedef struct {
    struct wl_resource *resource;
    uint8_t            *data;   // points into the SHM pool mapping
    uint32_t            width;
    uint32_t            height;
    uint32_t            stride;
    int32_t             offset;
    WWNPool            *pool;   // retained reference — keeps the mmap alive
} WWNBuffer;

static void buf_destroy(struct wl_client *client, struct wl_resource *res)
{
    wl_resource_destroy(res);
}

static const struct wl_buffer_interface buf_impl = {
    .destroy = buf_destroy,
};

static void buf_resource_destroy(struct wl_resource *res)
{
    WWNBuffer *buf = wl_resource_get_user_data(res);
    // Release the pool reference this buffer was holding.
    pool_release(buf->pool);
    free(buf);
}

// ── wl_shm_pool ───────────────────────────────────────────────────────────────

static void pool_create_buffer(struct wl_client *client,
                                struct wl_resource *pool_res,
                                uint32_t id,
                                int32_t offset,
                                int32_t width,
                                int32_t height,
                                int32_t stride,
                                uint32_t format)
{
    WWNPool *pool = wl_resource_get_user_data(pool_res);

    pool->refcount++;   // buffer holds a reference to the pool

    WWNBuffer *buf = calloc(1, sizeof(WWNBuffer));
    buf->pool   = pool;
    buf->data   = pool->data + offset;
    buf->width  = (uint32_t)width;
    buf->height = (uint32_t)height;
    buf->stride = (uint32_t)stride;
    buf->offset = offset;

    buf->resource = wl_resource_create(client, &wl_buffer_interface, 1, id);
    wl_resource_set_implementation(buf->resource, &buf_impl, buf, buf_resource_destroy);
}

static void pool_destroy(struct wl_client *client, struct wl_resource *res)
{
    wl_resource_destroy(res);
}

static void pool_resize(struct wl_client *client, struct wl_resource *res,
                         int32_t size)
{
    (void)size; // mremap not supported; no-op
}

static const struct wl_shm_pool_interface pool_impl = {
    .create_buffer = pool_create_buffer,
    .destroy       = pool_destroy,
    .resize        = pool_resize,
};

static void pool_resource_destroy(struct wl_resource *res)
{
    // Drop the pool's own reference (the +1 assigned at creation).
    // If no buffers are alive the memory is freed immediately; otherwise
    // it stays alive until the last buffer is destroyed.
    WWNPool *pool = wl_resource_get_user_data(res);
    pool_release(pool);
}

// ── wl_shm ────────────────────────────────────────────────────────────────────

static void shm_create_pool(struct wl_client *client,
                              struct wl_resource *shm_res,
                              uint32_t id,
                              int fd,
                              int32_t size)
{
    void *data = mmap(NULL, (size_t)size, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (data == MAP_FAILED) {
        wl_resource_post_error(shm_res, WL_SHM_ERROR_INVALID_FD, "mmap failed");
        return;
    }

    WWNPool *pool = calloc(1, sizeof(WWNPool));
    pool->data     = data;
    pool->size     = (size_t)size;
    pool->refcount = 1;   // pool's own reference; drops in pool_resource_destroy

    pool->resource = wl_resource_create(client, &wl_shm_pool_interface, 1, id);
    wl_resource_set_implementation(pool->resource, &pool_impl, pool, pool_resource_destroy);
}

static const struct wl_shm_interface shm_impl = {
    .create_pool = shm_create_pool,
};

static void shm_bind(struct wl_client *client, void *data,
                      uint32_t version, uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &wl_shm_interface,
                                                  (int)version < 1 ? 1 : (int)version, id);
    wl_resource_set_implementation(res, &shm_impl, data, NULL);
    // Advertise supported pixel formats
    wl_shm_send_format(res, WL_SHM_FORMAT_ARGB8888);
    wl_shm_send_format(res, WL_SHM_FORMAT_XRGB8888);
}

// ── wl_surface ────────────────────────────────────────────────────────────────

typedef struct {
    struct wl_resource         *resource;
    struct wl_resource         *pending_buffer_res;
    struct wl_resource         *committed_buffer_res;
    struct wl_resource         *pending_frame_cb;
    struct WWNMiniWaylandServer *srv;
} WWNSurface;

static uint32_t wwn_monotonic_millis(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        return 0;
    }
    uint64_t total_ms = (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000ULL);
    return (uint32_t)(total_ms & 0xffffffffu);
}

static void surf_attach(struct wl_client *client, struct wl_resource *res,
                         struct wl_resource *buf_res,
                         int32_t x, int32_t y)
{
    WWNSurface *surf = wl_resource_get_user_data(res);
    surf->pending_buffer_res = buf_res;  // NULL means "detach"
}

static void surf_damage(struct wl_client *c, struct wl_resource *r,
                          int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }

static void surf_frame(struct wl_client *client, struct wl_resource *res,
                         uint32_t callback_id)
{
    WWNSurface *surf = wl_resource_get_user_data(res);
    // Destroy any previously queued callback that was never fired.
    if (surf->pending_frame_cb)
        wl_resource_destroy(surf->pending_frame_cb);
    surf->pending_frame_cb = wl_resource_create(client, &wl_callback_interface, 1, callback_id);
}

static void surf_set_opaque(struct wl_client *c, struct wl_resource *r,
                               struct wl_resource *region)
{ (void)c;(void)r;(void)region; }

static void surf_set_input(struct wl_client *c, struct wl_resource *r,
                             struct wl_resource *region)
{ (void)c;(void)r;(void)region; }

static void surf_commit(struct wl_client *client, struct wl_resource *res)
{
    WWNSurface *surf = wl_resource_get_user_data(res);
    uint32_t frame_time_ms = wwn_monotonic_millis();

    if (surf->pending_buffer_res) {
        // 1. Release the previously committed buffer so the client can reuse it.
        if (surf->committed_buffer_res && surf->committed_buffer_res != surf->pending_buffer_res) {
            wl_buffer_send_release(surf->committed_buffer_res);
        }

        struct wl_resource *buf_res = surf->pending_buffer_res;
        surf->pending_buffer_res = NULL;
        surf->committed_buffer_res = buf_res;

        // 2. Deliver pixels to the bridge.
        WWNBuffer *buf = wl_resource_get_user_data(buf_res);
        if (buf && buf->data && buf->pool && buf->pool->data) {
            notify_frame(surf->srv, buf->data, buf->width, buf->height, buf->stride);
        }
    }

    // 3. Fire the frame callback after processing buffer release/attach (when present).
    // Always complete queued frame callbacks, even on state-only commits with no
    // newly attached buffer, so clients don't stall waiting for frame done.
    if (surf->pending_frame_cb) {
        wl_callback_send_done(surf->pending_frame_cb, frame_time_ms);
        wl_resource_destroy(surf->pending_frame_cb);
        surf->pending_frame_cb = NULL;
    }
}

static void surf_set_buffer_transform(struct wl_client *c, struct wl_resource *r,
                                        int32_t t){ (void)c;(void)r;(void)t; }

static void surf_set_buffer_scale(struct wl_client *c, struct wl_resource *r,
                                    int32_t s){ (void)c;(void)r;(void)s; }

static void surf_damage_buffer(struct wl_client *c, struct wl_resource *r,
                                 int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }

static void surf_destroy(struct wl_client *c, struct wl_resource *r)
{ wl_resource_destroy(r); }

static const struct wl_surface_interface surf_impl = {
    .attach               = surf_attach,
    .damage               = surf_damage,
    .frame                = surf_frame,
    .set_opaque_region    = surf_set_opaque,
    .set_input_region     = surf_set_input,
    .commit               = surf_commit,
    .set_buffer_transform = surf_set_buffer_transform,
    .set_buffer_scale     = surf_set_buffer_scale,
    .damage_buffer        = surf_damage_buffer,
    .destroy              = surf_destroy,
};

static void surf_resource_destroy(struct wl_resource *res)
{
    free(wl_resource_get_user_data(res));
}

// ── wl_region (stub) ─────────────────────────────────────────────────────────

static void region_destroy(struct wl_client *c, struct wl_resource *r)
{ wl_resource_destroy(r); }
static void region_add(struct wl_client *c, struct wl_resource *r,
                         int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }
static void region_subtract(struct wl_client *c, struct wl_resource *r,
                               int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }

static const struct wl_region_interface region_impl = {
    .destroy  = region_destroy,
    .add      = region_add,
    .subtract = region_subtract,
};

// ── wl_compositor ─────────────────────────────────────────────────────────────

static void comp_create_surface(struct wl_client *client,
                                  struct wl_resource *comp_res,
                                  uint32_t id)
{
    struct WWNMiniWaylandServer *srv = wl_resource_get_user_data(comp_res);

    WWNSurface *surf = calloc(1, sizeof(WWNSurface));
    surf->srv = srv;
    surf->resource = wl_resource_create(client, &wl_surface_interface, 4, id);
    wl_resource_set_implementation(surf->resource, &surf_impl, surf, surf_resource_destroy);
}

static void comp_create_region(struct wl_client *client,
                                  struct wl_resource *comp_res,
                                  uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &wl_region_interface, 1, id);
    wl_resource_set_implementation(res, &region_impl, NULL, NULL);
}

static const struct wl_compositor_interface comp_impl = {
    .create_surface = comp_create_surface,
    .create_region  = comp_create_region,
};

static void comp_bind(struct wl_client *client, void *data,
                        uint32_t version, uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &wl_compositor_interface,
                                                  version < 4 ? (int)version : 4, id);
    wl_resource_set_implementation(res, &comp_impl, data, NULL);
}

// ── xdg_wm_base (XDG shell — primary shell protocol for Weston 12+) ──────────
// Requires xdg-shell-server-protocol.h (generated by libwayland/watchos.nix).
// Falls back to wl_shell for older clients when XDG is not compiled in.

#ifdef WWN_XDG_SHELL_AVAILABLE

// Forward declarations
static const struct xdg_surface_interface   xdg_surface_impl;
static const struct xdg_toplevel_interface  xdg_toplevel_impl;

// Shared serial counter for configure events
static uint32_t g_xdg_serial = 1;

// ── xdg_toplevel ─────────────────────────────────────────────────────────────

static void xdg_tl_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static void xdg_tl_set_parent(struct wl_client *c, struct wl_resource *r,
                                struct wl_resource *p)
{ (void)c;(void)r;(void)p; }
static void xdg_tl_set_title(struct wl_client *c, struct wl_resource *r, const char *t)
{ (void)c;(void)r;(void)t; }
static void xdg_tl_set_app_id(struct wl_client *c, struct wl_resource *r, const char *a)
{ (void)c;(void)r;(void)a; }
static void xdg_tl_show_window_menu(struct wl_client *c, struct wl_resource *r,
                                      struct wl_resource *seat, uint32_t serial,
                                      int32_t x, int32_t y)
{ (void)c;(void)r;(void)seat;(void)serial;(void)x;(void)y; }
static void xdg_tl_move(struct wl_client *c, struct wl_resource *r,
                          struct wl_resource *seat, uint32_t serial)
{ (void)c;(void)r;(void)seat;(void)serial; }
static void xdg_tl_resize(struct wl_client *c, struct wl_resource *r,
                            struct wl_resource *seat, uint32_t serial, uint32_t edges)
{ (void)c;(void)r;(void)seat;(void)serial;(void)edges; }
static void xdg_tl_set_max_size(struct wl_client *c, struct wl_resource *r,
                                  int32_t w, int32_t h)
{ (void)c;(void)r;(void)w;(void)h; }
static void xdg_tl_set_min_size(struct wl_client *c, struct wl_resource *r,
                                  int32_t w, int32_t h)
{ (void)c;(void)r;(void)w;(void)h; }
static void xdg_tl_set_maximized(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }
static void xdg_tl_unset_maximized(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }
static void xdg_tl_set_fullscreen(struct wl_client *c, struct wl_resource *r,
                                    struct wl_resource *output)
{ (void)c;(void)r;(void)output; }
static void xdg_tl_unset_fullscreen(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }
static void xdg_tl_set_minimized(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }

static const struct xdg_toplevel_interface xdg_toplevel_impl = {
    .destroy           = xdg_tl_destroy,
    .set_parent        = xdg_tl_set_parent,
    .set_title         = xdg_tl_set_title,
    .set_app_id        = xdg_tl_set_app_id,
    .show_window_menu  = xdg_tl_show_window_menu,
    .move              = xdg_tl_move,
    .resize            = xdg_tl_resize,
    .set_max_size      = xdg_tl_set_max_size,
    .set_min_size      = xdg_tl_set_min_size,
    .set_maximized     = xdg_tl_set_maximized,
    .unset_maximized   = xdg_tl_unset_maximized,
    .set_fullscreen    = xdg_tl_set_fullscreen,
    .unset_fullscreen  = xdg_tl_unset_fullscreen,
    .set_minimized     = xdg_tl_set_minimized,
};

// ── xdg_surface ──────────────────────────────────────────────────────────────

typedef struct {
    struct wl_resource *resource;
    struct wl_resource *surface;   // the underlying wl_surface
} WWNXdgSurface;

static void xdg_surf_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }

static void xdg_surf_get_toplevel(struct wl_client *client,
                                    struct wl_resource *xdg_surf_res,
                                    uint32_t id)
{
    struct wl_resource *tl = wl_resource_create(client, &xdg_toplevel_interface, 1, id);
    wl_resource_set_implementation(tl, &xdg_toplevel_impl, NULL, NULL);

    // Send configure: width=0, height=0 → client picks its own size; no states.
    struct wl_array states;
    wl_array_init(&states);
    xdg_toplevel_send_configure(tl, 0, 0, &states);
    wl_array_release(&states);

    // Send xdg_surface.configure with a serial so client calls ack_configure.
    uint32_t serial = g_xdg_serial++;
    xdg_surface_send_configure(xdg_surf_res, serial);
}

static void xdg_popup_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static void xdg_popup_grab(struct wl_client *c, struct wl_resource *r,
                              struct wl_resource *seat, uint32_t serial)
{ (void)c;(void)r;(void)seat;(void)serial; }
static void xdg_popup_reposition(struct wl_client *c, struct wl_resource *r,
                                   struct wl_resource *positioner, uint32_t token)
{ (void)c;(void)r;(void)positioner;(void)token; }

static const struct xdg_popup_interface xdg_popup_impl = {
    .destroy     = xdg_popup_destroy,
    .grab        = xdg_popup_grab,
    .reposition  = xdg_popup_reposition,
};

static void xdg_surf_get_popup(struct wl_client *c, struct wl_resource *r,
                                 uint32_t id, struct wl_resource *parent,
                                 struct wl_resource *positioner)
{
    (void)parent; (void)positioner;
    struct wl_resource *popup = wl_resource_create(c, &xdg_popup_interface, 1, id);
    wl_resource_set_implementation(popup, &xdg_popup_impl, NULL, NULL);
}

static void xdg_surf_set_window_geometry(struct wl_client *c, struct wl_resource *r,
                                           int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }

static void xdg_surf_ack_configure(struct wl_client *c, struct wl_resource *r,
                                     uint32_t serial)
{ (void)c;(void)r;(void)serial; }

static const struct xdg_surface_interface xdg_surface_impl = {
    .destroy              = xdg_surf_destroy,
    .get_toplevel         = xdg_surf_get_toplevel,
    .get_popup            = xdg_surf_get_popup,
    .set_window_geometry  = xdg_surf_set_window_geometry,
    .ack_configure        = xdg_surf_ack_configure,
};

static void xdg_surf_resource_destroy(struct wl_resource *r)
{
    free(wl_resource_get_user_data(r));
}

// ── xdg_wm_base ──────────────────────────────────────────────────────────────

static void xdg_wmbase_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }

static void xdg_pos_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static void xdg_pos_set_size(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h)
{ (void)c;(void)r;(void)w;(void)h; }
static void xdg_pos_set_anchor_rect(struct wl_client *c, struct wl_resource *r,
                                      int32_t x, int32_t y, int32_t w, int32_t h)
{ (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }
static void xdg_pos_set_anchor(struct wl_client *c, struct wl_resource *r, uint32_t anchor)
{ (void)c;(void)r;(void)anchor; }
static void xdg_pos_set_gravity(struct wl_client *c, struct wl_resource *r, uint32_t gravity)
{ (void)c;(void)r;(void)gravity; }
static void xdg_pos_set_constraint_adjustment(struct wl_client *c, struct wl_resource *r, uint32_t ca)
{ (void)c;(void)r;(void)ca; }
static void xdg_pos_set_offset(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y)
{ (void)c;(void)r;(void)x;(void)y; }
static void xdg_pos_set_reactive(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }
static void xdg_pos_set_parent_size(struct wl_client *c, struct wl_resource *r,
                                      int32_t w, int32_t h)
{ (void)c;(void)r;(void)w;(void)h; }
static void xdg_pos_set_parent_configure(struct wl_client *c, struct wl_resource *r, uint32_t serial)
{ (void)c;(void)r;(void)serial; }

static const struct xdg_positioner_interface xdg_positioner_impl = {
    .destroy                  = xdg_pos_destroy,
    .set_size                 = xdg_pos_set_size,
    .set_anchor_rect          = xdg_pos_set_anchor_rect,
    .set_anchor               = xdg_pos_set_anchor,
    .set_gravity              = xdg_pos_set_gravity,
    .set_constraint_adjustment= xdg_pos_set_constraint_adjustment,
    .set_offset               = xdg_pos_set_offset,
    .set_reactive             = xdg_pos_set_reactive,
    .set_parent_size          = xdg_pos_set_parent_size,
    .set_parent_configure     = xdg_pos_set_parent_configure,
};

static void xdg_wmbase_create_positioner(struct wl_client *client,
                                           struct wl_resource *r,
                                           uint32_t id)
{
    (void)r;
    struct wl_resource *pos = wl_resource_create(client, &xdg_positioner_interface, 1, id);
    wl_resource_set_implementation(pos, &xdg_positioner_impl, NULL, NULL);
}

static void xdg_wmbase_get_xdg_surface(struct wl_client *client,
                                          struct wl_resource *wm_res,
                                          uint32_t id,
                                          struct wl_resource *surface_res)
{
    WWNXdgSurface *xs = calloc(1, sizeof(WWNXdgSurface));
    xs->surface = surface_res;
    xs->resource = wl_resource_create(client, &xdg_surface_interface, 1, id);
    wl_resource_set_implementation(xs->resource, &xdg_surface_impl, xs, xdg_surf_resource_destroy);
}

static void xdg_wmbase_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial)
{ (void)c;(void)r;(void)serial; }

static const struct xdg_wm_base_interface xdg_wmbase_impl = {
    .destroy            = xdg_wmbase_destroy,
    .create_positioner  = xdg_wmbase_create_positioner,
    .get_xdg_surface    = xdg_wmbase_get_xdg_surface,
    .pong               = xdg_wmbase_pong,
};

static void xdg_wmbase_bind(struct wl_client *client, void *data,
                              uint32_t version, uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &xdg_wm_base_interface,
                                                  version < 5 ? (int)version : 5, id);
    wl_resource_set_implementation(res, &xdg_wmbase_impl, data, NULL);
}

#endif // WWN_XDG_SHELL_AVAILABLE

// ── wl_shell & wl_shell_surface (legacy fallback for older clients) ───────────

static void shell_surface_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial)
{ (void)c;(void)r;(void)serial; }
static void shell_surface_move(struct wl_client *c, struct wl_resource *r,
                                  struct wl_resource *seat, uint32_t serial)
{ (void)c;(void)r;(void)seat;(void)serial; }
static void shell_surface_resize(struct wl_client *c, struct wl_resource *r,
                                    struct wl_resource *seat, uint32_t serial, uint32_t edges)
{ (void)c;(void)r;(void)seat;(void)serial;(void)edges; }
static void shell_surface_set_toplevel(struct wl_client *c, struct wl_resource *r)
{ (void)c;(void)r; }
static void shell_surface_set_transient(struct wl_client *c, struct wl_resource *r,
                                           struct wl_resource *parent, int32_t x, int32_t y, uint32_t flags)
{ (void)c;(void)r;(void)parent;(void)x;(void)y;(void)flags; }
static void shell_surface_set_fullscreen(struct wl_client *c, struct wl_resource *r,
                                            uint32_t method, uint32_t framerate, struct wl_resource *output)
{ (void)c;(void)r;(void)method;(void)framerate;(void)output; }
static void shell_surface_set_popup(struct wl_client *c, struct wl_resource *r,
                                       struct wl_resource *seat, uint32_t serial,
                                       struct wl_resource *parent, int32_t x, int32_t y, uint32_t flags)
{ (void)c;(void)r;(void)seat;(void)serial;(void)parent;(void)x;(void)y;(void)flags; }
static void shell_surface_set_maximized(struct wl_client *c, struct wl_resource *r,
                                           struct wl_resource *output)
{ (void)c;(void)r;(void)output; }
static void shell_surface_set_title(struct wl_client *c, struct wl_resource *r,
                                       const char *title)
{ (void)c;(void)r;(void)title; }
static void shell_surface_set_class(struct wl_client *c, struct wl_resource *r,
                                       const char *class_)
{ (void)c;(void)r;(void)class_; }
// wl_shell_surface has no destroy request; the resource is freed via
// wl_resource_destroy() when the client releases the connection.
static const struct wl_shell_surface_interface shell_surface_impl = {
    .pong           = shell_surface_pong,
    .move           = shell_surface_move,
    .resize         = shell_surface_resize,
    .set_toplevel   = shell_surface_set_toplevel,
    .set_transient  = shell_surface_set_transient,
    .set_fullscreen = shell_surface_set_fullscreen,
    .set_popup      = shell_surface_set_popup,
    .set_maximized  = shell_surface_set_maximized,
    .set_title      = shell_surface_set_title,
    .set_class      = shell_surface_set_class,
};

static void shell_get_shell_surface(struct wl_client *client,
                                      struct wl_resource *shell_res,
                                      uint32_t id,
                                      struct wl_resource *surface_res)
{
    (void)surface_res;
    struct wl_resource *res = wl_resource_create(client, &wl_shell_surface_interface, 1, id);
    wl_resource_set_implementation(res, &shell_surface_impl, NULL, NULL);
    wl_shell_surface_send_configure(res, 0, 0, 0);
}

static void shell_destroy(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }

static const struct wl_shell_interface shell_impl = {
    .get_shell_surface = shell_get_shell_surface,
};

static void shell_bind(struct wl_client *client, void *data,
                         uint32_t version, uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &wl_shell_interface, 1, id);
    wl_resource_set_implementation(res, &shell_impl, data, NULL);
}

// ── wl_output ─────────────────────────────────────────────────────────────────

static void output_release(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }

static const struct wl_output_interface output_impl = {
    .release = output_release,
};

static void output_bind(struct wl_client *client, void *data,
                          uint32_t version, uint32_t id)
{
    struct WWNMiniWaylandServer *srv = (struct WWNMiniWaylandServer *)data;
    struct wl_resource *res = wl_resource_create(client, &wl_output_interface,
                                                  version < 3 ? (int)version : 3, id);
    wl_resource_set_implementation(res, &output_impl, data, NULL);
    wl_output_send_geometry(res,
        0, 0,           // x, y
        38, 46,         // physical size mm (Apple Watch Ultra 2 approx)
        WL_OUTPUT_SUBPIXEL_UNKNOWN,
        "Apple Watch",
        "Wawona",
        WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(res,
        WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED,
        (int32_t)srv->output_width,
        (int32_t)srv->output_height,
        60000); // 60 Hz in mHz
    if (version >= 2)
        wl_output_send_done(res);
}

// ── wl_seat (minimal stub — advertises zero capabilities) ────────────────────
// We advertise no input devices, so clients should not call get_pointer/keyboard/touch.
// No-op stubs are provided defensively so the linker is happy and rogue clients don't crash.

static void ptr_set_cursor(struct wl_client *c, struct wl_resource *r,
                              uint32_t serial, struct wl_resource *surf,
                              int32_t hx, int32_t hy)
{ (void)c;(void)r;(void)serial;(void)surf;(void)hx;(void)hy; }
static void ptr_release(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static const struct wl_pointer_interface ptr_impl = {
    .set_cursor = ptr_set_cursor,
    .release    = ptr_release,
};

static void kb_release(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static const struct wl_keyboard_interface kb_impl = {
    .release = kb_release,
};

static void touch_release(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }
static const struct wl_touch_interface touch_impl = {
    .release = touch_release,
};

static void seat_get_pointer(struct wl_client *c, struct wl_resource *r, uint32_t id)
{
    struct wl_resource *ptr = wl_resource_create(c, &wl_pointer_interface, 7, id);
    wl_resource_set_implementation(ptr, &ptr_impl, NULL, NULL);
}
static void seat_get_keyboard(struct wl_client *c, struct wl_resource *r, uint32_t id)
{
    struct wl_resource *kb = wl_resource_create(c, &wl_keyboard_interface, 8, id);
    wl_resource_set_implementation(kb, &kb_impl, NULL, NULL);
}
static void seat_get_touch(struct wl_client *c, struct wl_resource *r, uint32_t id)
{
    struct wl_resource *touch = wl_resource_create(c, &wl_touch_interface, 8, id);
    wl_resource_set_implementation(touch, &touch_impl, NULL, NULL);
}
static void seat_release(struct wl_client *c, struct wl_resource *r)
{ (void)c; wl_resource_destroy(r); }

static const struct wl_seat_interface seat_impl = {
    .get_pointer  = seat_get_pointer,
    .get_keyboard = seat_get_keyboard,
    .get_touch    = seat_get_touch,
    .release      = seat_release,
};

static void seat_bind(struct wl_client *client, void *data,
                        uint32_t version, uint32_t id)
{
    struct wl_resource *res = wl_resource_create(client, &wl_seat_interface,
                                                  version < 8 ? (int)version : 8, id);
    wl_resource_set_implementation(res, &seat_impl, data, NULL);
    wl_seat_send_capabilities(res, 0); // no input capabilities on watch (for now)
}

// ── Public API ────────────────────────────────────────────────────────────────

WWNMiniWaylandServer *wwn_wls_create(const char *socket_name,
                                      uint32_t output_width,
                                      uint32_t output_height,
                                      WWNFrameCallback frame_cb,
                                      void *userdata)
{
    // Unix domain socket paths are limited to 103 usable characters on Darwin
    // (struct sockaddr_un.sun_path is char[104] including null terminator).
    // The iOS/watchOS simulator's TMPDIR is typically 150+ characters — way over limit.
    // Strategy: ensure XDG_RUNTIME_DIR + "/" + socket_name fits in 103 chars.
    // We prefer a short mkdtemp() dir under /tmp (accessible in simulator and on device).
    {
        const char *xdg  = getenv("XDG_RUNTIME_DIR");
        size_t sock_len  = strlen(socket_name);
        // +2 for "/" and null terminator
        int path_fits = xdg && xdg[0] && (strlen(xdg) + 1 + sock_len + 1 <= 104);

        if (!path_fits) {
            // Try a unique short directory under /tmp
            char tmpl[] = "/tmp/wln.XXXXXX";
            char *dir = mkdtemp(tmpl);
            if (dir && (strlen(dir) + 1 + sock_len + 1 <= 104)) {
                setenv("XDG_RUNTIME_DIR", dir, 1);
            } else {
                // Fall back to /tmp itself (15 chars, always fits)
                if (mkdir("/tmp", 0755) < 0 && errno != EEXIST) { /* ignore */ }
                setenv("XDG_RUNTIME_DIR", "/tmp", 1);
            }
        }
    }

    struct wl_display *disp = wl_display_create();
    if (!disp) return NULL;

    // Remove any stale socket from a previous run before binding.
    {
        const char *xdg = getenv("XDG_RUNTIME_DIR");
        char path[256];
        snprintf(path, sizeof(path), "%s/%s", xdg ? xdg : "/tmp", socket_name);
        unlink(path);
    }

    if (wl_display_add_socket(disp, socket_name) < 0) {
        wl_display_destroy(disp);
        return NULL;
    }

    WWNMiniWaylandServer *srv = calloc(1, sizeof(WWNMiniWaylandServer));
    srv->display       = disp;
    srv->loop          = wl_display_get_event_loop(disp);
    srv->output_width  = output_width  ? output_width  : 184;
    srv->output_height = output_height ? output_height : 224;
    srv->frame_cb      = frame_cb;
    srv->userdata      = userdata;

    // Advertise protocol globals
    srv->compositor_global = wl_global_create(disp, &wl_compositor_interface, 4, srv, comp_bind);
    srv->shm_global        = wl_global_create(disp, &wl_shm_interface,        1, srv, shm_bind);
    srv->output_global     = wl_global_create(disp, &wl_output_interface,     3, srv, output_bind);
    srv->seat_global       = wl_global_create(disp, &wl_seat_interface,       8, srv, seat_bind);
    // Prefer xdg_wm_base (Weston 12+); also expose legacy wl_shell as fallback.
#ifdef WWN_XDG_SHELL_AVAILABLE
    srv->xdg_wm_base_global = wl_global_create(disp, &xdg_wm_base_interface,  5, srv, xdg_wmbase_bind);
#endif
    srv->shell_global      = wl_global_create(disp, &wl_shell_interface,      1, srv, shell_bind);

    // Set WAYLAND_DISPLAY so clients (running in-process or as subprocesses) find us
    setenv("WAYLAND_DISPLAY", socket_name, 1);

    return srv;
}

int wwn_wls_dispatch(WWNMiniWaylandServer *srv, int timeout_ms)
{
    if (!srv) return 0;
    wl_event_loop_dispatch(srv->loop, timeout_ms);
    wl_display_flush_clients(srv->display);
    return 1;
}

void wwn_wls_destroy(WWNMiniWaylandServer *srv)
{
    if (!srv) return;
    unsetenv("WAYLAND_DISPLAY");
    wl_display_destroy(srv->display);
    free(srv);
}

// ── Stub path: libwayland-server not available ────────────────────────────────

#else // !WWN_WL_SERVER_AVAILABLE

struct WWNMiniWaylandServer { int unused; };

WWNMiniWaylandServer *wwn_wls_create(const char *socket_name,
                                      uint32_t output_width,
                                      uint32_t output_height,
                                      WWNFrameCallback frame_cb,
                                      void *userdata)
{
    (void)socket_name; (void)output_width; (void)output_height;
    (void)frame_cb; (void)userdata;
    return NULL; // Trigger stub mode in bridge
}

int  wwn_wls_dispatch(WWNMiniWaylandServer *srv, int timeout_ms) { (void)srv; (void)timeout_ms; return 0; }
void wwn_wls_destroy (WWNMiniWaylandServer *srv) { (void)srv; }

#endif // WWN_WL_SERVER_AVAILABLE
