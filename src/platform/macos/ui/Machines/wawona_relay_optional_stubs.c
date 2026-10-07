/* Optional Relay ABI. Declared weak so verify-link-contract skips them when
 * libwawona_relay.a does not export the newer helpers yet. Definitions are
 * also weak so a real relay archive wins at link time. */
#include <stddef.h>

extern int relay_start_host_waypipe(const char *handle, int (*entry)(int)) __attribute__((weak));
extern int relay_nix_editor(const char *name, const char *source, char **json_out) __attribute__((weak));
extern int relay_nixos_generations(const char *disk_path, char **json_out) __attribute__((weak));

int relay_start_host_waypipe(const char *handle, int (*entry)(int)) {
  (void)handle;
  (void)entry;
  return -2;
}

int relay_nix_editor(const char *name, const char *source, char **json_out) {
  (void)name;
  (void)source;
  if (json_out) {
    *json_out = NULL;
  }
  return -2;
}

int relay_nixos_generations(const char *disk_path, char **json_out) {
  (void)disk_path;
  if (json_out) {
    *json_out = NULL;
  }
  return -2;
}
