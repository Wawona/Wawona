#include "wawona_relay.h"

/*
 * Flake-pinned wwn-relay (ios) currently exports resolve/start/stop/endpoint
 * only. WWNRelay.m already calls relay_copy_frame for guest previews. Provide a
 * weak stub so Mode B tipa links; a newer Relay that exports the real symbol
 * wins over this weak definition.
 */
__attribute__((weak)) int relay_copy_frame(const char *handle, uint8_t *rgba,
                                           size_t len, uint32_t *width,
                                           uint32_t *height) {
  (void)handle;
  (void)rgba;
  (void)len;
  if (width) {
    *width = 0;
  }
  if (height) {
    *height = 0;
  }
  return -3; /* planned / unavailable on this Relay build */
}
