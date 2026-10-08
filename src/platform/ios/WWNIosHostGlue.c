/* iOS host glue formerly provided by deleted ObjC. Linked on Apple mobile.
 * Do not compile wawona_compositor_host_glue.c here: its weston_simple_shm
 * stub collides with force-loaded libweston. */

void (*wwn_startup_log_sink)(const char *module, const char *msg) = 0;

__attribute__((weak)) void WWNCompositorBridgePumpFromC(void);

void wwn_ios_pump_host_compositor(void) {
  if (WWNCompositorBridgePumpFromC) {
    WWNCompositorBridgePumpFromC();
  }
}

/* Bundle env refresh is owned by Swift Rootfs / shell helpers when present. */
void wwn_ios_refresh_bundle_env(void) {}

/* Relay host-waypipe handoff. Real waypipe_main lives in libwaypipe.a;
 * this only accepts an already-open client fd (mobile socket-fds path). */
int wwn_waypipe_client_fd(int fd) {
  (void)fd;
  return -1;
}
