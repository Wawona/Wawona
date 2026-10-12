/* Optional Relay ABI. Definitions are weak so a real libwawona_relay wins
 * at link time. Strong stubs here would permanently shadow tip Relay. */
#include <stddef.h>

__attribute__((weak)) int relay_start_host_waypipe(const char *handle,
                                                   int (*entry)(int)) {
  (void)handle;
  (void)entry;
  return -2;
}

__attribute__((weak)) int relay_start_shm_importer(const char *handle) {
  (void)handle;
  return -2;
}

__attribute__((weak)) int relay_nix_editor(const char *name, const char *source,
                                           char **json_out) {
  (void)name;
  (void)source;
  if (json_out) {
    *json_out = NULL;
  }
  return -2;
}

__attribute__((weak)) int relay_nixos_generations(const char *disk_path,
                                                  char **json_out) {
  (void)disk_path;
  if (json_out) {
    *json_out = NULL;
  }
  return -2;
}
