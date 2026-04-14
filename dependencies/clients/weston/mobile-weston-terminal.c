#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

struct wwn_terminal_client {
  struct wl_display *display;
  struct wl_registry *registry;
  struct wl_compositor *compositor;
  struct wl_shm *shm;
  struct xdg_wm_base *wm_base;

  struct wl_surface *surface;
  struct xdg_surface *xdg_surface;
  struct xdg_toplevel *xdg_toplevel;

  struct wl_buffer *buffer;
  int width;
  int height;
  bool configured;
  bool running;
};

static int
wwn_create_anonymous_file(size_t size) {
  const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
  if (!runtime_dir || runtime_dir[0] == '\0') {
    runtime_dir = "/tmp";
  }

  char template_path[512];
  snprintf(template_path, sizeof(template_path), "%s/%s", runtime_dir,
           "wawona-weston-terminal-XXXXXX");
  int fd = mkstemp(template_path);
  if (fd < 0) {
    return -1;
  }

  unlink(template_path);
  if (ftruncate(fd, (off_t)size) != 0) {
    close(fd);
    return -1;
  }

  return fd;
}

static void
wwn_draw_terminal_frame(uint32_t *pixels, int width, int height) {
  const uint32_t bg = 0xFF111317u;
  const uint32_t title = 0xFF1F2430u;
  const uint32_t accent = 0xFF5CC8FFu;
  const uint32_t body = 0xFF0B0D11u;
  const int title_h = 42;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      uint32_t color = (y < title_h) ? title : bg;
      if (y >= title_h && (y % 22 == 0)) {
        color = body;
      }
      if (y < title_h && x > 14 && x < width - 14 && y > title_h - 8) {
        color = accent;
      }
      pixels[y * width + x] = color;
    }
  }

  /* Cursor-like block so the client appears clearly alive. */
  const int cursor_x = 18;
  const int cursor_y = title_h + 26;
  const int cursor_w = 10;
  const int cursor_h = 18;
  for (int y = cursor_y; y < cursor_y + cursor_h && y < height; y++) {
    for (int x = cursor_x; x < cursor_x + cursor_w && x < width; x++) {
      pixels[y * width + x] = 0xFFE6EAF2u;
    }
  }
}

static void
wwn_destroy_buffer(struct wwn_terminal_client *client) {
  if (client->buffer) {
    wl_buffer_destroy(client->buffer);
    client->buffer = NULL;
  }
}

static int
wwn_attach_buffer(struct wwn_terminal_client *client) {
  const int stride = client->width * 4;
  const size_t size = (size_t)stride * (size_t)client->height;
  int fd = wwn_create_anonymous_file(size);
  if (fd < 0) {
    return -1;
  }

  void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (map == MAP_FAILED) {
    close(fd);
    return -1;
  }

  wwn_draw_terminal_frame((uint32_t *)map, client->width, client->height);

  struct wl_shm_pool *pool = wl_shm_create_pool(client->shm, fd, (int)size);
  struct wl_buffer *buffer = wl_shm_pool_create_buffer(
      pool, 0, client->width, client->height, stride, WL_SHM_FORMAT_ARGB8888);
  wl_shm_pool_destroy(pool);
  munmap(map, size);
  close(fd);

  if (!buffer) {
    return -1;
  }

  wwn_destroy_buffer(client);
  client->buffer = buffer;
  wl_surface_attach(client->surface, client->buffer, 0, 0);
  wl_surface_damage_buffer(client->surface, 0, 0, client->width, client->height);
  wl_surface_commit(client->surface);
  return 0;
}

static void
wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial) {
  (void)data;
  xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
    .ping = wm_base_ping,
};

static void
xdg_surface_configure(void *data, struct xdg_surface *surface, uint32_t serial) {
  struct wwn_terminal_client *client = (struct wwn_terminal_client *)data;
  xdg_surface_ack_configure(surface, serial);
  if (!client->configured) {
    client->configured = true;
    wwn_attach_buffer(client);
  }
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_configure,
};

static void
xdg_toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width,
                       int32_t height, struct wl_array *states) {
  (void)toplevel;
  (void)states;
  struct wwn_terminal_client *client = (struct wwn_terminal_client *)data;
  if (width > 0 && height > 0 &&
      (client->width != width || client->height != height)) {
    client->width = width;
    client->height = height;
    wwn_attach_buffer(client);
  }
}

static void
xdg_toplevel_close(void *data, struct xdg_toplevel *toplevel) {
  (void)toplevel;
  struct wwn_terminal_client *client = (struct wwn_terminal_client *)data;
  client->running = false;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_toplevel_configure,
    .close = xdg_toplevel_close,
};

static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
                const char *interface, uint32_t version) {
  struct wwn_terminal_client *client = (struct wwn_terminal_client *)data;
  if (strcmp(interface, wl_compositor_interface.name) == 0) {
    client->compositor = wl_registry_bind(registry, name, &wl_compositor_interface,
                                          version < 4 ? version : 4);
  } else if (strcmp(interface, wl_shm_interface.name) == 0) {
    client->shm = wl_registry_bind(registry, name, &wl_shm_interface,
                                   version < 1 ? version : 1);
  } else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
    client->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface,
                                       version < 1 ? version : 1);
  }
}

static void
registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int wwn_weston_terminal_is_compat_shim(void) { return 0; }

#ifdef __ANDROID__
int weston_terminal_main(int argc, const char **argv) {
#else
int weston_terminal_main(int argc, char **argv) {
#endif
  (void)argc;
  (void)argv;

  struct wwn_terminal_client client;
  memset(&client, 0, sizeof(client));
  client.width = 960;
  client.height = 540;
  client.running = true;

  client.display = wl_display_connect(NULL);
  if (!client.display) {
    fprintf(stderr, "weston-terminal: failed to connect to Wayland display\n");
    return 1;
  }

  client.registry = wl_display_get_registry(client.display);
  wl_registry_add_listener(client.registry, &registry_listener, &client);
  wl_display_roundtrip(client.display);
  wl_display_roundtrip(client.display);

  if (!client.compositor || !client.shm || !client.wm_base) {
    fprintf(stderr, "weston-terminal: missing required Wayland globals\n");
    wl_display_disconnect(client.display);
    return 1;
  }

  xdg_wm_base_add_listener(client.wm_base, &wm_base_listener, &client);

  client.surface = wl_compositor_create_surface(client.compositor);
  client.xdg_surface = xdg_wm_base_get_xdg_surface(client.wm_base, client.surface);
  xdg_surface_add_listener(client.xdg_surface, &xdg_surface_listener, &client);
  client.xdg_toplevel = xdg_surface_get_toplevel(client.xdg_surface);
  xdg_toplevel_add_listener(client.xdg_toplevel, &xdg_toplevel_listener, &client);
  xdg_toplevel_set_title(client.xdg_toplevel, "Weston Terminal");
  xdg_toplevel_set_app_id(client.xdg_toplevel, "org.freedesktop.weston-terminal");

  wl_surface_commit(client.surface);
  wl_display_roundtrip(client.display);

  while (client.running && wl_display_dispatch(client.display) != -1) {
    /* Event-driven loop. */
  }

  wwn_destroy_buffer(&client);
  if (client.xdg_toplevel) {
    xdg_toplevel_destroy(client.xdg_toplevel);
  }
  if (client.xdg_surface) {
    xdg_surface_destroy(client.xdg_surface);
  }
  if (client.surface) {
    wl_surface_destroy(client.surface);
  }
  if (client.wm_base) {
    xdg_wm_base_destroy(client.wm_base);
  }
  if (client.shm) {
    wl_shm_destroy(client.shm);
  }
  if (client.compositor) {
    wl_compositor_destroy(client.compositor);
  }
  if (client.registry) {
    wl_registry_destroy(client.registry);
  }
  if (client.display) {
    wl_display_disconnect(client.display);
  }

  return 0;
}
