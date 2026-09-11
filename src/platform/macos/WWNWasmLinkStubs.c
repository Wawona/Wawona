/* Weak fallbacks when the bundled macos libwawona_wasm.a predates
 * interrupt/status exports. Strong symbols in a current archive win. */

__attribute__((weak))
void wawona_wasm_request_interrupt(void) {}

__attribute__((weak))
int wawona_wasm_is_running(void) {
  return 0;
}
