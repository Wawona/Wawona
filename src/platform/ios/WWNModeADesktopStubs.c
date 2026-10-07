/* Weak Mode A placeholders. Real Mode B Rust exports override when linked. */
#include <stdint.h>

__attribute__((weak)) int wwn_modeb_desktop_start(uint32_t *out_width, uint32_t *out_height) {
  (void)out_width;
  (void)out_height;
  return -1;
}

__attribute__((weak)) int wwn_modeb_desktop_phase(void) { return 0; }

__attribute__((weak)) void wwn_modeb_desktop_size(int32_t *w, int32_t *h) {
  if (w) {
    *w = 0;
  }
  if (h) {
    *h = 0;
  }
}

__attribute__((weak)) int wwn_modeb_desktop_recover_to_greeter(void) { return -1; }
