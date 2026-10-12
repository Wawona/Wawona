/* Optional Relay ABI stubs for symbols that may be absent on a target.
 *
 * Do NOT weak-stub `relay_start_shm_importer` or `relay_start_host_waypipe`.
 * Apple ld treats a weak definition as satisfying `-Wl,-u,_…`, so the strong
 * symbol in libwawona_relay.a is never pulled. The binary then keeps the
 * stub (`return -2` / ERR_PLANNED) and Mode A SHM present never starts.
 * Those two always come from the linked Relay archive (+ `-u` / force_load).
 */
#include <stddef.h>

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
