/*
 * wwn-iowatchdog: macOS Desktop Mode B only.
 *
 * Disable / re-enable kernel IOWatchdog userspace monitoring so launchctl
 * may unload com.apple.watchdogd without an immediate XNU panic
 * (watchdogd[pid] exited, PanicOnConsecutiveCrash on macOS 26 / 25F80).
 *
 * Never ship on iOS / store IPA. Requires SIP fully disabled + root.
 *
 * Method selectors match /usr/libexec/watchdogd error strings on 25F80.
 *
 * On macOS 26, watchdogd holds exclusive type=1 IOWatchdogUserClient, so
 * IOServiceOpen fails with kIOReturnExclusiveAccess (or privilege
 * violation when the daemon is absent). Do NOT fall back to lldb attach:
 * that exited watchdogd with SIGTRAP (paniclog namespace 2 subcode 0x5)
 * and paniced the machine during install / app open / restore (2026-08-20).
 *
 * Until a non-lldb path exists (entitled user client or Apple-supported
 * API), disable/enable fail closed. Take Over must abort and leave Aqua.
 */
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum {
  kIOWatchdogDaemonCheckEnabled = 0,
  kIOWatchdogDaemonCheckUserspaceDefanged = 1,
  kIOWatchdogDaemonCheckin = 2,
  kIOWatchdogDaemonDisableUserspaceMonitoring = 3,
  kIOWatchdogDaemonReenableUserspaceMonitoring = 4,
};

typedef struct {
  io_connect_t connection;
} wwn_iow_conn_t;

static void usage(const char *argv0) {
  fprintf(stderr, "usage: %s status|disable|enable\n", argv0);
}

static pid_t find_watchdogd_pid(void) {
  int bufsize = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
  if (bufsize <= 0)
    return 0;
  pid_t *pids = calloc((size_t)bufsize, 1);
  if (!pids)
    return 0;
  bufsize = proc_listpids(PROC_ALL_PIDS, 0, pids, bufsize);
  pid_t found = 0;
  int n = bufsize / (int)sizeof(pid_t);
  for (int i = 0; i < n; i++) {
    if (pids[i] <= 0)
      continue;
    char name[32] = {0};
    if (proc_name(pids[i], name, sizeof(name)) <= 0)
      continue;
    if (strcmp(name, "watchdogd") == 0) {
      found = pids[i];
      break;
    }
  }
  free(pids);
  return found;
}

static int lsmp_iowatchdog_port_name(pid_t wd, mach_port_name_t *out_name) {
  char cmd[64];
  snprintf(cmd, sizeof(cmd), "/usr/bin/lsmp -p %d", (int)wd);
  FILE *f = popen(cmd, "r");
  if (!f)
    return -1;
  char line[512];
  int found = 0;
  while (fgets(line, sizeof(line), f)) {
    if (strstr(line, "IOWatchdogUserClient") == NULL)
      continue;
    unsigned name = 0;
    if (sscanf(line, "0x%x", &name) == 1 && name != 0) {
      *out_name = (mach_port_name_t)name;
      found = 1;
      break;
    }
  }
  pclose(f);
  return found ? 0 : -1;
}

static void close_conn(wwn_iow_conn_t *c) {
  if (c->connection != IO_OBJECT_NULL) {
    IOServiceClose(c->connection);
    c->connection = IO_OBJECT_NULL;
  }
}

static wwn_iow_conn_t open_watchdog(void) {
  wwn_iow_conn_t out = {.connection = IO_OBJECT_NULL};
  CFMutableDictionaryRef matching = IOServiceMatching("IOWatchdog");
  if (!matching)
    return out;
  io_service_t service =
      IOServiceGetMatchingService(kIOMainPortDefault, matching);
  if (service == IO_OBJECT_NULL)
    return out;
  kern_return_t kr =
      IOServiceOpen(service, mach_task_self(), /*type=*/1, &out.connection);
  IOObjectRelease(service);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "wwn-iowatchdog: IOServiceOpen type=1 failed: %s (0x%x)\n",
            mach_error_string(kr), (unsigned)kr);
    out.connection = IO_OBJECT_NULL;
  }
  return out;
}

static int call_scalar(io_connect_t conn, uint32_t selector,
                       const char *label) {
  kern_return_t kr =
      IOConnectCallScalarMethod(conn, selector, NULL, 0, NULL, NULL);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "wwn-iowatchdog: %s (selector %u) failed: %s (0x%x)\n",
            label, (unsigned)selector, mach_error_string(kr), (unsigned)kr);
    return 1;
  }
  printf("wwn-iowatchdog: %s ok\n", label);
  return 0;
}

static int run_selector(uint32_t selector, const char *label) {
  wwn_iow_conn_t c = open_watchdog();
  if (c.connection != IO_OBJECT_NULL) {
    int rc = call_scalar(c.connection, selector, label);
    close_conn(&c);
    return rc;
  }
  /*
   * No direct user client. Never attach lldb (2026-08-20 SIGTRAP panics).
   * Take Over must abort; reboot restores kernel monitoring if it was
   * previously disabled somehow.
   */
  fprintf(stderr,
          "wwn-iowatchdog: %s unavailable (IOWatchdogUserClient exclusive to "
          "watchdogd; lldb fallback removed after kernel panics). Do not "
          "unload com.apple.watchdogd.\n",
          label);
  return 1;
}

static int cmd_status(void) {
  wwn_iow_conn_t c = open_watchdog();
  if (c.connection != IO_OBJECT_NULL) {
    int a = call_scalar(c.connection, kIOWatchdogDaemonCheckEnabled,
                        "CheckEnabled");
    int b = call_scalar(c.connection, kIOWatchdogDaemonCheckUserspaceDefanged,
                        "CheckUserspaceDefanged");
    close_conn(&c);
    return (a == 0 || b == 0) ? 0 : 1;
  }
  pid_t wd = find_watchdogd_pid();
  mach_port_name_t port = 0;
  int have_port = (wd > 0 && lsmp_iowatchdog_port_name(wd, &port) == 0);
  printf("wwn-iowatchdog: status (no direct connection)\n");
  printf("  watchdogd pid: %d\n", (int)wd);
  if (have_port)
    printf("  IOWatchdogUserClient port: 0x%x (exclusive to watchdogd)\n",
           (unsigned)port);
  else
    printf("  IOWatchdogUserClient: not listed\n");
  printf("  disable/enable: blocked without exclusive open "
         "(lldb fallback removed)\n");
  return (wd > 0 && have_port) ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    usage(argv[0]);
    return 2;
  }
  if (geteuid() != 0) {
    fprintf(stderr, "wwn-iowatchdog: must run as root (euid=%d)\n", geteuid());
    return 2;
  }

  const char *cmd = argv[1];
  if (strcmp(cmd, "status") == 0)
    return cmd_status();
  if (strcmp(cmd, "disable") == 0)
    return run_selector(kIOWatchdogDaemonDisableUserspaceMonitoring,
                        "DisableUserspaceMonitoring");
  if (strcmp(cmd, "enable") == 0)
    return run_selector(kIOWatchdogDaemonReenableUserspaceMonitoring,
                        "ReenableUserspaceMonitoring");
  usage(argv[0]);
  return 2;
}
