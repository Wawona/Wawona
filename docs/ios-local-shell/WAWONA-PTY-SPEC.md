# Wawona PTY Library Specification (`libwwn-pty`)

**Status:** Draft — implementation starts Phase 0/2  
**Package path (planned):** `dependencies/libs/wawona-pty/`  
**Headers:** `include/wwn_pty.h`

This library is the **only supported path** for spawning a local shell on Apple mobile. Weston compositor `fork()` stubs must not be used for shell launch.

---

## Design goals

1. **App Store compliance** — spawn only bundled rootfs binaries (see [SECURITY-SPAWN-POLICY.md](SECURITY-SPAWN-POLICY.md))
2. **Single responsibility** — PTY lifecycle + I/O; no Wayland, no UI
3. **Testable on device** — Phase 0 spike uses this API surface
4. **macOS host tests** — same API where `forkpty` is available for parity tests

---

## Public API (C)

```c
#ifndef WWN_PTY_H
#define WWN_PTY_H

#include <sys/types.h>
#include <stdint.h>
#include <termios.h>

#ifdef __cplusplus
extern "C" {
#endif

struct winsize;

/** Opaque session: master fd, child pid, rootfs-validated shell path */
typedef struct wwn_pty_session wwn_pty_session;

/**
 * Open a PTY pair. On success, *master_fd and *slave_fd are set.
 * Optionally apply initial winsize to slave via TIOCSWINSZ.
 *
 * Returns 0 on success, -1 on failure with errno set.
 */
int wwn_pty_open(int *master_fd, int *slave_fd, const struct winsize *ws);

/**
 * Validate shell_path is under WAWONA_ROOTFS (from env or argument).
 * Returns 1 if allowed, 0 if rejected.
 */
int wwn_pty_is_allowed_shell_path(const char *shell_path);

/**
 * Spawn shell attached to slave_fd (already open). Does NOT close slave_fd
 * on success (caller may close after spawn). Uses posix_spawn only.
 *
 * shell_path: e.g. …/wawona-rootfs/usr/bin/zsh
 * argv: NULL-terminated; argv[0] should be basename of shell
 * envp: NULL-terminated; must include WAWONA_ROOTFS, HOME, PATH, TERM
 *
 * Returns child pid on success, -1 on failure with errno set.
 */
pid_t wwn_pty_spawn_shell(const char *shell_path, char *const argv[],
                          int slave_fd, char *const envp[]);

/** Convenience: open + spawn + store session */
wwn_pty_session *wwn_pty_session_start(const char *shell_path,
                                       char *const argv[],
                                       char *const envp[],
                                       const struct winsize *ws);

/** Read from master (non-blocking optional — TBD in impl) */
ssize_t wwn_pty_read(int master_fd, void *buf, size_t len);

/** Write to master */
ssize_t wwn_pty_write(int master_fd, const void *buf, size_t len);

/** Propagate terminal size to kernel */
int wwn_pty_set_winsize(int master_fd, const struct winsize *ws);

/** Wait for child and close fds */
int wwn_pty_reap(wwn_pty_session *session, int *exit_status);

void wwn_pty_session_destroy(wwn_pty_session *session);

#ifdef __cplusplus
}
#endif

#endif /* WWN_PTY_H */
```

---

## Spawn implementation requirements

### Must use

- `posix_spawn` with `POSIX_SPAWN_SETPGROUP`
- `posix_spawn_file_actions_adddup2` → slave to stdin, stdout, stderr
- Path validation before spawn (fail closed)

### Must not use

- `fork()` + `exec()` from compositor code paths on iOS
- `system()`, `popen()`, `/bin/sh`
- Shell paths from user paste / remote config
- `dlopen` of non-bundle libraries in child (inherit clean env)

### iOS-specific notes

- Call `setsid` in child if required for job control (validate in spike)
- If `grantpt` fails, implement **pipe-TTY fallback** documented in spike report — still bundled-only, but may not be full POSIX PTY

---

## Integration with `terminal.c`

Weston terminal expects a master fd and child pid roughly like `forkpty`:

```c
#if defined(__APPLE__) && (TARGET_OS_IPHONE || TARGET_OS_TV)
  int master, slave;
  struct winsize ws = { .ws_row = rows, .ws_col = cols, ... };
  if (wwn_pty_open(&master, &slave, &ws) < 0) { /* show error in UI */ }
  pid_t pid = wwn_pty_spawn_shell(getenv("WAWONA_SHELL"), argv, slave, environ);
  /* terminal.c event loop reads/writes `master` */
#else
  /* forkpty path — macOS, Linux */
#endif
```

Environment **`WAWONA_SHELL`** is set by `WWNWaypipeRunner` before client main runs.

---

## Error handling

| errno / return | User-visible behavior |
|----------------|----------------------|
| `EPERM` / `EACCES` on spawn | "Local shell unavailable in this configuration" |
| Path rejected | "Shell must be bundled with Wawona" (debug log path) |
| `grantpt` failure | Spike-defined message; link to support doc |
| Child exit non-zero | Terminal shows exit code; session may restart on user action |

Log to Wawona log facility (`WWNLog` / `wlog!`) with tag `PTY` — never log full env (may contain tokens).

---

## Threading

- PTY I/O from `terminal.c` runs on Weston's event loop thread (same as today for macOS)
- `wwn_pty_*` calls must be **thread-safe for distinct sessions**; single session serialized by terminal.c
- Reap on compositor session teardown: `WWNWaypipeRunner` → `stopActiveIOSBundledClient`

---

## Testing matrix

| Test | Where |
|------|-------|
| Path rejection for `/bin/zsh` | Unit test (host) |
| Path allow for rootfs prefix | Unit test |
| Open + echo | Phase 0 spike (device) |
| Winsize propagation | Phase 2 device |
| Memory leak on reap | Instruments |

---

## Nix packaging (planned)

```nix
# dependencies/libs/wawona-pty/ios.nix (sketch)
# outputs: $out/lib/libwwn-pty.a, $out/include/wwn_pty.h
# propagatedBuildInputs: (minimal — libc only)
```

Registered in `registry.nix` as `wawona-pty`. Linked from `wawona-ios-backend` and weston terminal client closure.

---

## Versioning

Add `WWN_PTY_API_VERSION` int in header. Bump when ABI changes. Terminal.c checks at compile time via `WWN_PTY_API_VERSION >= 1`.
