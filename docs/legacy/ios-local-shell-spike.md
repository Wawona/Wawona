> **Superseded.** Spike template. Live hub: [`../ios-local-shell/README.md`](../ios-local-shell/README.md). Do not copy to wawona.io.

# Phase 0 Device Spike Report — PTY + Bundled ZSH on iOS

**Status:** Nix packages green on host (`wawona-pty-ios`, `zsh-ios`, `wawona-rootfs-ios`, `weston-ios`, `wawona-pty-spike-ios`). **Physical device PTY/zsh tests still required** before Phase 2 production sign-off.

**Owner:** _______________  
**Device:** _______________ (model, iOS version)  
**Build:** `nix build .#wawona-pty-spike-ios` → `./result/bin/wawona-pty-spike`  
**Date:** _______________

---

## Purpose

Prove or disprove that Wawona can run **bundled native zsh** attached to a PTY inside the App Store sandbox on a **physical iPhone**. This gates the App Store–compliant local shell program documented in [ios-local-shell/](ios-local-shell/README.md).

---

## Hypothesis

`posix_openpt(3)` + `grantpt(3)` + `posix_spawn(3)` of a static `zsh` binary from `Wawona.app/Resources/wawona-rootfs/usr/bin/zsh` works on device, with stdin/stdout/stderr on the PTY slave and bidirectional I/O on the master.

---

## Test environment

| Item | Value |
|------|-------|
| Spike binary path | |
| zsh binary path in bundle | |
| Code signing | Development / TestFlight |
| Entitlements | (list from `.entitlements`) |
| Sandbox | Standard app sandbox |

---

## Test 1 — `posix_openpt`

```c
master = posix_openpt(O_RDWR | O_NOCTTY);
```

| Step | Result | errno | Notes |
|------|--------|-------|-------|
| open master | ⬜ pass / ⬜ fail | | |
| `grantpt(master)` | ⬜ pass / ⬜ fail | | |
| `unlockpt(master)` | ⬜ pass / ⬜ fail | | |
| `ptsname(master)` | | | slave path: |

---

## Test 2 — `posix_spawn` zsh

| Step | Result | Notes |
|------|--------|-------|
| spawn with slave dup2 → 0,1,2 | ⬜ pass / ⬜ fail | pid: |
| write `echo hello\n` to master | ⬜ pass / ⬜ fail | |
| read contains `hello` | ⬜ pass / ⬜ fail | output: |

---

## Test 3 — Interactive commands

| Command | Expected | Result |
|---------|----------|--------|
| `pwd` | path in container | ⬜ |
| `cd /tmp && pwd` | succeeds or clear error | ⬜ |
| `echo $SHELL` | zsh path | ⬜ |
| Ctrl-C interrupt | shell survives | ⬜ |

---

## Test 4 — Winsize

| Step | Result |
|------|--------|
| `TIOCSWINSZ` on master/slave | ⬜ |
| `stty size` in shell matches | ⬜ |

---

## Test 5 — Resource / lifecycle

| Metric | Value |
|--------|-------|
| zsh binary size | |
| Idle RSS with spike | |
| Peak RSS during command | |
| Background 30s → foreground | ⬜ ok / ⬜ jetsam |
| `waitpid` after SIGHUP | ⬜ ok |

Instruments trace attached: ⬜ yes / ⬜ no — file: _______________

---

## Test 6 — Path policy (compliance)

| Path passed to spawn | Expected | Result |
|----------------------|----------|--------|
| `…/wawona-rootfs/usr/bin/zsh` | allow | ⬜ |
| `/bin/sh` | reject | ⬜ |
| `/tmp/evil` | reject | ⬜ |

---

## Fallback assessment (if grantpt or spawn fails)

| Fallback | Viable? | Notes |
|----------|---------|-------|
| Pipe-based pseudo-TTY (master/slave pipe pair) | ⬜ | |
| In-process only (no job control) | ⬜ | |
| Defer local shell to Phase 2.1 | ⬜ | |

**Approved fallback for Phase 2:** _______________

---

## Conclusion

⬜ **GO** — proceed to Phase 2 with standard PTY  
⬜ **GO with fallback** — document: _______________  
⬜ **NO-GO** — local zsh blocked; remote-only until: _______________

**Signed:** _______________ **Date:** _______________

---

## Raw logs

```text
(paste spike stdout/stderr, relevant WWNLog lines)
```
