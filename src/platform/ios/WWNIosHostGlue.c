/* iOS host glue formerly provided by deleted ObjC. Linked on Apple mobile. */

void (*wwn_startup_log_sink)(const char *module, const char *msg) = 0;

__attribute__((weak)) void WWNCompositorBridgePumpFromC(void);

void wwn_ios_pump_host_compositor(void) {
  if (WWNCompositorBridgePumpFromC) {
    WWNCompositorBridgePumpFromC();
  }
}

/* Bundle env refresh is owned by Swift Rootfs / shell helpers when present. */
void wwn_ios_refresh_bundle_env(void) {}
