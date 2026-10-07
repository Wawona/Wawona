/* Host compositor lifecycle ABI expected by Sources/WawonaApple Present glue.
 * Maps onto WWNCore* from libwawona.a. Mode B / tipa helpers stay weak stubs
 * until the matching archives export them. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct WWNCore WWNCore;

extern WWNCore *WWNCoreNew(void);
extern bool WWNCoreStart(WWNCore *core, const char *socket_name);
extern bool WWNCoreStop(WWNCore *core);
extern bool WWNCoreIsRunning(const WWNCore *core);
extern char *WWNCoreGetSocketPath(const WWNCore *core);
extern bool WWNCoreProcessEvents(WWNCore *core);
extern void WWNCoreFlushClients(WWNCore *core);
extern void WWNCoreFree(WWNCore *core);

static WWNCore *g_core = NULL;
static char g_socket_name[64] = "wayland-0";
static char *g_socket_path_cache = NULL;

int wawona_compositor_start(const char *socket) {
  if (socket && socket[0]) {
    strncpy(g_socket_name, socket, sizeof(g_socket_name) - 1);
    g_socket_name[sizeof(g_socket_name) - 1] = '\0';
  }
  if (!g_core) {
    g_core = WWNCoreNew();
    if (!g_core) {
      return -1;
    }
  }
  if (!WWNCoreStart(g_core, g_socket_name)) {
    return -1;
  }
  free(g_socket_path_cache);
  g_socket_path_cache = WWNCoreGetSocketPath(g_core);
  return 0;
}

void wawona_compositor_stop(void) {
  if (g_core) {
    (void)WWNCoreStop(g_core);
    WWNCoreFree(g_core);
    g_core = NULL;
  }
  free(g_socket_path_cache);
  g_socket_path_cache = NULL;
}

int wawona_compositor_is_running(void) {
  return (g_core && WWNCoreIsRunning(g_core)) ? 1 : 0;
}

const char *wawona_compositor_socket_path(void) {
  if (g_socket_path_cache) {
    return g_socket_path_cache;
  }
  return "/tmp/wawona-wayland-0";
}

/* Swift Present glue still names this PollEvents. */
int WWNCorePollEvents(WWNCore *core) {
  WWNCore *target = core ? core : g_core;
  if (!target) {
    return 0;
  }
  return WWNCoreProcessEvents(target) ? 1 : 0;
}

void (*wwn_startup_log_sink)(const char *module, const char *msg) = NULL;

int weston_simple_shm_main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return -1;
}

int wwn_waypipe_client_fd(int fd) {
  (void)fd;
  return -1;
}

int wwn_modeb_desktop_phase(void) { return 0; }
int wwn_modeb_desktop_recover_to_greeter(void) { return -1; }
int wwn_modeb_desktop_size(uint32_t *w, uint32_t *h) {
  if (w) {
    *w = 0;
  }
  if (h) {
    *h = 0;
  }
  return -1;
}
int wwn_modeb_desktop_start(void) { return -1; }
int wwn_modeb_desktop_present_bgra(const void *pixels, uint32_t w, uint32_t h) {
  (void)pixels;
  (void)w;
  (void)h;
  return -1;
}
