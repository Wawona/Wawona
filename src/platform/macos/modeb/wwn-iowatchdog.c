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
 * IOServiceOpen fails with kIOReturnExclusiveAccess. Without Apple's
 * private entitlement, open also fails with privilege violation when the
 * daemon is absent. Fallbacks (SIP off + Xcode lldb):
 *
 *   disable: one-shot lldb rewrite of arm64 x1 -> 3 at
 *            IOConnectCallScalarMethod entry in watchdogd
 *   enable:  if watchdogd is up, one-shot rewrite x1 -> 4; if down, waitfor
 *            spawn, step out of CheckEnabled, expr Reenable(4), detach,
 *            then kickstart until the daemon stays up
 *
 * Do not codesign with com.apple.private.iowatchdog.user-access on an
 * ad-hoc signature: Taskgated SIGKILLs Invalid Signature.
 */
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
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
  int stolen;
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

static kern_return_t steal_watchdogd_connection(io_connect_t *out) {
  *out = IO_OBJECT_NULL;
  pid_t wd = find_watchdogd_pid();
  if (wd <= 0)
    return KERN_FAILURE;
  mach_port_name_t remote_name = 0;
  if (lsmp_iowatchdog_port_name(wd, &remote_name) != 0)
    return KERN_FAILURE;
  task_t task = TASK_NULL;
  kern_return_t kr = task_for_pid(mach_task_self(), wd, &task);
  if (kr != KERN_SUCCESS)
    return kr;
  mach_port_t local = MACH_PORT_NULL;
  mach_msg_type_name_t acquired = 0;
  kr = mach_port_extract_right(task, remote_name, MACH_MSG_TYPE_COPY_SEND,
                               &local, &acquired);
  mach_port_deallocate(mach_task_self(), task);
  if (kr != KERN_SUCCESS || local == MACH_PORT_NULL)
    return kr != KERN_SUCCESS ? kr : KERN_FAILURE;
  printf("wwn-iowatchdog: stolen connection pid=%d port=0x%x\n", (int)wd,
         (unsigned)remote_name);
  *out = local;
  return KERN_SUCCESS;
}

static wwn_iow_conn_t open_watchdog(void) {
  wwn_iow_conn_t out = {IO_OBJECT_NULL, 0};
  CFMutableDictionaryRef matching = IOServiceMatching("IOWatchdog");
  if (!matching)
    return out;
  io_service_t service =
      IOServiceGetMatchingService(kIOMainPortDefault, matching);
  if (!service)
    return out;
  io_connect_t connection = IO_OBJECT_NULL;
  kern_return_t err =
      IOServiceOpen(service, mach_task_self(), /*type=*/1, &connection);
  IOObjectRelease(service);
  if (err == KERN_SUCCESS) {
    out.connection = connection;
    return out;
  }
  fprintf(stderr, "wwn-iowatchdog: IOServiceOpen type=1 failed: %s (0x%x)\n",
          mach_error_string(err), (unsigned)err);
  if (steal_watchdogd_connection(&connection) == KERN_SUCCESS) {
    out.connection = connection;
    out.stolen = 1;
  }
  return out;
}

static void close_conn(wwn_iow_conn_t *c) {
  if (!c || c->connection == IO_OBJECT_NULL)
    return;
  if (c->stolen)
    mach_port_deallocate(mach_task_self(), c->connection);
  else
    IOServiceClose(c->connection);
  c->connection = IO_OBJECT_NULL;
}

static int call_scalar(io_connect_t c, uint32_t selector, const char *label) {
  kern_return_t err =
      IOConnectCallScalarMethod(c, selector, NULL, 0, NULL, NULL);
  if (err != KERN_SUCCESS) {
    fprintf(stderr, "wwn-iowatchdog: %s (selector %u) failed: %s (0x%x)\n",
            label, selector, mach_error_string(err), (unsigned)err);
    return 1;
  }
  printf("wwn-iowatchdog: %s ok\n", label);
  return 0;
}

static const char *find_lldb(void) {
  static char path[512];
  FILE *f = popen("/usr/bin/xcrun --find lldb 2>/dev/null", "r");
  if (f) {
    if (fgets(path, sizeof(path), f)) {
      size_t n = strlen(path);
      while (n > 0 && (path[n - 1] == '\n' || path[n - 1] == '\r'))
        path[--n] = 0;
      pclose(f);
      if (n > 0 && access(path, X_OK) == 0)
        return path;
    } else {
      pclose(f);
    }
  }
  if (access("/usr/bin/lldb", X_OK) == 0)
    return "/usr/bin/lldb";
  return NULL;
}

/* Run lldb -b -s script with a wall timeout; always SIGCONT watchdogd after. */
static int run_lldb_script(const char *script_body, int timeout_sec,
                           const char *expect_substr) {
  const char *lldb = find_lldb();
  if (!lldb) {
    fprintf(stderr, "wwn-iowatchdog: lldb not found (need Xcode CLT)\n");
    return 1;
  }

  char script_path[] = "/tmp/wwn-iowatchdog-XXXXXX.lldb";
  int sfd = mkstemps(script_path, 5);
  if (sfd < 0)
    return 1;
  FILE *sf = fdopen(sfd, "w");
  if (!sf) {
    close(sfd);
    unlink(script_path);
    return 1;
  }
  fputs(script_body, sf);
  fclose(sf);

  char log_path[] = "/tmp/wwn-iowatchdog-XXXXXX.log";
  int lfd = mkstemp(log_path);
  if (lfd >= 0)
    close(lfd);

  pid_t child = fork();
  if (child < 0) {
    unlink(script_path);
    unlink(log_path);
    return 1;
  }
  if (child == 0) {
    int fd = open(log_path, O_WRONLY | O_TRUNC);
    if (fd >= 0) {
      dup2(fd, STDOUT_FILENO);
      dup2(fd, STDERR_FILENO);
      close(fd);
    }
    execl(lldb, lldb, "-b", "-s", script_path, (char *)NULL);
    _exit(127);
  }

  int timed_out = 0;
  for (int i = 0; i < timeout_sec * 10; i++) {
    int st = 0;
    pid_t r = waitpid(child, &st, WNOHANG);
    if (r == child)
      goto done_wait;
    usleep(100000);
  }
  timed_out = 1;
  kill(child, SIGKILL);
  waitpid(child, NULL, 0);

done_wait:
  unlink(script_path);
  pid_t wd = find_watchdogd_pid();
  if (wd > 0)
    kill(wd, SIGCONT);

  FILE *lf = fopen(log_path, "r");
  int saw = 0;
  if (lf) {
    char line[512];
    while (fgets(line, sizeof(line), lf)) {
      fputs(line, stderr);
      if (expect_substr && strstr(line, expect_substr))
        saw = 1;
    }
    fclose(lf);
  }
  unlink(log_path);

  if (timed_out) {
    fprintf(stderr, "wwn-iowatchdog: lldb timed out after %ds\n", timeout_sec);
    return 1;
  }
  if (expect_substr && !saw) {
    fprintf(stderr, "wwn-iowatchdog: lldb missing expected '%s'\n",
            expect_substr);
    return 1;
  }
  return 0;
}

static int lldb_rewrite_live(uint32_t selector, const char *label) {
  pid_t wd = find_watchdogd_pid();
  if (wd <= 0) {
    fprintf(stderr, "wwn-iowatchdog: watchdogd not running for %s\n", label);
    return 1;
  }
  char body[1024];
  snprintf(body, sizeof(body),
           "process attach --pid %d\n"
           "breakpoint set --name IOConnectCallScalarMethod --one-shot true\n"
           "process continue\n"
           "register read x0 x1\n"
           "register write x1 %u\n"
           "register read x1\n"
           "process detach\n"
           "quit\n",
           (int)wd, (unsigned)selector);
  if (run_lldb_script(body, 20, "register write x1") != 0)
    return 1;
  printf("wwn-iowatchdog: %s ok (lldb live x1=%u pid=%d)\n", label,
         (unsigned)selector, (int)wd);
  return 0;
}

/*
 * Daemon absent (kernel monitoring still disabled): wait for spawn, finish
 * CheckEnabled, expr Reenable(4), detach, bootstrap until stable.
 * Prefer bootstrap over kickstart: kickstart often returns ESRCH here.
 */
static int lldb_reenable_spawn(void) {
  const char *body =
      "process attach --name watchdogd --waitfor\n"
      "breakpoint set --name IOConnectCallScalarMethod --one-shot true\n"
      "process continue\n"
      "expr unsigned int $wwn_conn = (unsigned int)$x0\n"
      "register read x0 x1\n"
      "thread step-out\n"
      "expr -- (int)IOConnectCallScalarMethod($wwn_conn, (unsigned int)4, "
      "(unsigned long long *)0, (unsigned int)0, (unsigned long long *)0, "
      "(unsigned int *)0)\n"
      "process detach\n"
      "quit\n";

  (void)system("/bin/launchctl enable system/com.apple.watchdogd >/dev/null "
               "2>&1");

  /* Kickstart/bootstrap after lldb is listening. */
  pid_t helper = fork();
  if (helper == 0) {
    usleep(1500000);
    (void)system("/bin/launchctl bootout system/com.apple.watchdogd "
                 ">/dev/null 2>&1");
    usleep(200000);
    (void)system("/bin/launchctl bootstrap system "
                 "/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
                 ">/dev/null 2>&1");
    for (int i = 0; i < 8; i++) {
      usleep(500000);
      if (find_watchdogd_pid() > 0)
        break;
      (void)system("/bin/launchctl bootstrap system "
                   "/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
                   ">/dev/null 2>&1");
    }
    _exit(0);
  }

  int rc = run_lldb_script(body, 30, "IOConnectCallScalarMethod");
  if (helper > 0) {
    int st = 0;
    for (int i = 0; i < 50; i++) {
      if (waitpid(helper, &st, WNOHANG) == helper)
        break;
      usleep(100000);
    }
    kill(helper, SIGKILL);
    waitpid(helper, NULL, 0);
  }
  if (rc != 0)
    fprintf(stderr, "wwn-iowatchdog: spawn-reenable lldb failed (continuing "
                    "bootstrap loop)\n");

  for (int i = 0; i < 10; i++) {
    if (find_watchdogd_pid() > 0) {
      sleep(2);
      if (find_watchdogd_pid() > 0) {
        printf("wwn-iowatchdog: ReenableUserspaceMonitoring ok "
               "(spawn-reenable, pid=%d)\n",
               (int)find_watchdogd_pid());
        return 0;
      }
    }
    (void)system("/bin/launchctl bootout system/com.apple.watchdogd "
                 ">/dev/null 2>&1");
    usleep(200000);
    (void)system("/bin/launchctl bootstrap system "
                 "/System/Library/LaunchDaemons/com.apple.watchdogd.plist "
                 ">/dev/null 2>&1");
    sleep(1);
  }
  fprintf(stderr,
          "wwn-iowatchdog: enable failed; reboot restores IOWatchdog. "
          "Do not unload watchdogd again until enable works.\n");
  return 1;
}

static int run_selector(uint32_t selector, const char *label) {
  wwn_iow_conn_t c = open_watchdog();
  if (c.connection != IO_OBJECT_NULL) {
    int rc = call_scalar(c.connection, selector, label);
    close_conn(&c);
    return rc;
  }
  fprintf(stderr, "wwn-iowatchdog: falling back to lldb for %s\n", label);
  if (selector == kIOWatchdogDaemonReenableUserspaceMonitoring &&
      find_watchdogd_pid() <= 0)
    return lldb_reenable_spawn();
  return lldb_rewrite_live(selector, label);
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
