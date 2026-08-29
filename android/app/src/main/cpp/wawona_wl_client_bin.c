/*
 * Multicall PATH launcher for nested-niri fuzzel (issue #78).
 *
 * Fuzzel's .desktop Exec= lines are bare command names (weston-simple-shm,
 * weston-flower, …). Those clients live in shared libraries, not as
 * standalone PIEs. So selecting them from fuzzel previously did nothing
 * useful (ENOENT / no window under niri).
 *
 * Packaged as libwawona_wl_bin.so and symlinked into
 * wawona-rootfs/usr/bin/<Exec> so fuzzel's fork+exec inherits niri's
 * WAYLAND_DISPLAY and actually opens a client window in the nested session.
 */
#include <android/log.h>
#include <dlfcn.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define TAG "WawonaWlBin"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

typedef int (*client_main_fn)(int argc, char **argv);

struct client_map {
  const char *exec_name;
  const char *lib_name;
  const char *symbol_name;
};

/* Prefer the light weston-simple-shm .so; other toys are linked into libwawona. */
static const struct client_map k_clients[] = {
    {"weston-simple-shm", "libweston_simple_shm.so", "weston_simple_shm_main"},
    {"weston-simple-egl", "libwawona.so", "simple_egl_main"},
    {"weston-flower", "libwawona.so", "flower_main"},
    {"weston-clickdot", "libwawona.so", "clickdot_main"},
    {"weston-smoke", "libwawona.so", "smoke_main"},
    {"weston-eventdemo", "libwawona.so", "eventdemo_main"},
    {"weston-resizor", "libwawona.so", "resizor_main"},
    {"weston-cliptest", "libwawona.so", "cliptest_main"},
    {"weston-transformed", "libwawona.so", "transformed_main"},
    {"weston-stacking", "libwawona.so", "stacking_main"},
    {"weston-dnd", "libwawona.so", "dnd_main"},
    {"weston-image", "libwawona.so", "image_main"},
    {"weston-scaler", "libwawona.so", "scaler_main"},
    {"weston-editor", "libwawona.so", "editor_main"},
    {"weston-constraints", "libwawona.so", "constraints_main"},
};

static const struct client_map *lookup_client(const char *name) {
  size_t i;
  if (!name || !name[0])
    return NULL;
  for (i = 0; i < sizeof(k_clients) / sizeof(k_clients[0]); i++) {
    if (strcmp(name, k_clients[i].exec_name) == 0)
      return &k_clients[i];
  }
  return NULL;
}

static const char *basename_of(const char *path) {
  const char *slash = strrchr(path, '/');
  return slash ? slash + 1 : path;
}

int main(int argc, char **argv) {
  const char *argv0 = (argc > 0 && argv[0]) ? argv[0] : "wawona-wl-client";
  const char *name = basename_of(argv0);
  const struct client_map *entry = lookup_client(name);
  void *handle;
  client_main_fn fn;
  const char *err;
  int rc;
  const char *wd = getenv("WAYLAND_DISPLAY");
  const char *xdg = getenv("XDG_RUNTIME_DIR");

  if (!entry) {
    LOGE("unknown client argv0=%s (not in nested-niri catalog launcher map)",
         name);
    return 127;
  }

  LOGI("launch %s via %s:%s WAYLAND_DISPLAY=%s XDG_RUNTIME_DIR=%s", name,
       entry->lib_name, entry->symbol_name, wd ? wd : "(null)",
       xdg ? xdg : "(null)");

  handle = dlopen(entry->lib_name, RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    LOGE("dlopen(%s) failed: %s", entry->lib_name, dlerror());
    return 127;
  }

  dlerror();
  fn = (client_main_fn)dlsym(handle, entry->symbol_name);
  err = dlerror();
  if (err || !fn) {
    LOGE("dlsym(%s) failed: %s", entry->symbol_name, err ? err : "null");
    dlclose(handle);
    return 127;
  }

  rc = fn(argc, argv);
  LOGI("%s exited %d", name, rc);
  dlclose(handle);
  return rc;
}
