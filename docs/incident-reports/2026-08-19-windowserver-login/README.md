# Mode B WindowServer login failure, 2026-08-19

**User:** 8amps (uid 503)
**Symptom:** WindowServer dies / black screen / login instability after Aqua sign-in
**Recovery script:** `WAWONA_MODEB_RECOVERY_2026-08-19.sh` (also `/tmp/WAWONA_MODEB_RECOVERY_2026-08-19.sh`)

## Executive summary

Mode B Desktop Replacement was re-enabled after the 2026-08-18 recovery. On login, the root helper at `/Library/Application Support/Wawona/run-modeb.sh` again attacked WindowServer. The dylib path was set correctly, but take-over still failed and the session flapped.

Two distinct failure modes appear in logs:

| Time | What happened |
|------|----------------|
| **10:23-10:44** | Full take-over: WS killed, niri started with `DYLD_INSERT_LIBRARIES`, but **`framebufferd` never appeared**. Mode B display path dead for ~20 min until manual restore |
| **11:02-11:03** | Rapid helper re-entry at login: WS killed once, helper exits via `restore_aqua` within ~2s, **no compositor start**; repeats 3x in 43s. Apps see `WindowServer event port death` |
| **~15:57** | Kernel panic: `userspace watchdog timeout: no successful checkins from WindowServer`. Helper had `launchctl disable` / `unload -w`. Job gone from launchd. `ws-guard` skipped restore while `modeb.lock` existed. `watchdogd` reset the machine at 120s. |
| **evening** | Kernel panic: `watchdogd[4516] exited -- exit reason namespace 2 subcode 0x5`. Unloading `com.apple.watchdogd` with launchctl exits the daemon; the plist has `_PanicOnCrash.PanicOnConsecutiveCrash`. Kernel panics immediately. Unload WindowServer: 120s panic. Unload watchdogd: instant panic. |
| **23:12** | Same panic (`watchdogd[77500] exited`) after `--mode-b-stage` rewrote `ws-guard`. The 10s daemon did `launchctl load -w` / `bootstrap` / `kickstart -k` on watchdogd. `kickstart -k` kills the running job. Hands-off: `ws-guard` must never touch watchdogd. |
| **2026-08-20 ~install** | Same panic (`watchdogd[8399] exited`, namespace 2 subcode 0x5 = SIGTRAP) during `nix run .#install` / `--mode-b-stage`. Stage ran `wwn-iowatchdog disable` which falls back to `lldb` attach on live `watchdogd`. Bad attach exits the daemon while kernel IOWatchdog is still armed. **Fix:** stage must never call `wwn-iowatchdog disable`/`enable` or attach lldb. Only `launchctl enable`+`bootstrap` if the job was left disabled. |

This is not a SkyLight crash from injection alone. It is launchd + helper logic killing WindowServer while Mode B cannot bring up framebufferd / a stable compositor. Leaving WindowServer disabled is a kernel panic on macOS 26, not a black screen.

## Code landed in Wawona (same day)

1. Take Over does **not** install `com.aspauldingcode.wawona.modeb-login`. Logout returns normal macOS. The menubar boots out any leftover plist.
2. Take Over disables kernel IOWatchdog (`wwn-iowatchdog disable`) first, then unloads `watchdogd`, then WindowServer, then injects. Abort if IOWatchdog disable fails. Marker: `WWN_MODEB_WD=iowatchdog-then-unload`. Probe may inject while both jobs stay up.
3. WindowServer reaper loop removed. `ws-guard` restores WindowServer only. It must never enable, load, bootstrap, kickstart, or bootout `watchdogd`. `kickstart -k` on watchdogd paniced at 23:12.
4. Passwordless engage refuses helpers that lack `WWN_MODEB_WD=iowatchdog-then-unload` / `stop_watchdogd_after_iowatchdog`, that contain `WWN_MODEB_WD=hands-off` or `launchctl-unload`, that lack `WWN_MODEB_GATE=pidfile-not-pgrep`, that still contain `reap WindowServer`, or that `kickstart -k` watchdogd.

The 12:04 take-over extracted framebufferd (pidfile on disk) but the installed helper still required `pgrep -x framebufferd` while WindowServer was up, then killed niri. That gate is a deadlock: SkyLight is already taken, so framebufferd cannot stay up, and `pgrep` is also a bad sensor after WindowServer dies.

## Primary log files

| Path | Contents |
|------|----------|
| `wawona-modeb.log` (this directory, and `/tmp/wawona-modeb.log`) | Authoritative Mode B helper timeline |
| `/tmp/wawona-menubar-503.error.log` | Wawona menubar: `HIToolbox: received notification of WindowServer event port death` at **11:02:30** |
| `/tmp/wawona-compositor-503.error.log` | Wawona compositor-host restarts after WS death |
| `/Library/Application Support/Wawona/run-modeb.sh` | Installed helper at incident time (WS reaper). After recovery: stub that only restores WindowServer |

## Key evidence from `/tmp/wawona-modeb.log`

### A) Successful WS kill, failed injection (10:24)

```text
2026-08-19 10:23:59 dylib=/Library/Application Support/Wawona/iland/libwayland-mac.dylib
2026-08-19 10:23:59 executable=/nix/store/.../niri
2026-08-19 10:23:59 disabling WindowServer for this session
2026-08-19 10:23:59 bootout_label_st=150          # SIP blocks bootout
...
2026-08-19 10:24:05 WindowServer down
2026-08-19 10:24:05 compositor pid=73712
2026-08-19 10:24:05 no framebufferd process       # injection did not spawn framebufferd
```

Dylib was configured, niri ran as root, but iland Mode B bootstrap (framebufferd) never came up. User had no working display server until 10:44 restore.

### B) Login storm / WS flap (11:02-11:03)

```text
2026-08-19 11:02:30 modeb helper start
2026-08-19 11:02:30 dylib=/Library/Application Support/Wawona/iland/libwayland-mac.dylib
2026-08-19 11:02:30 disabling WindowServer for this session
2026-08-19 11:02:30 WindowServer still pid=73723 try=0
2026-08-19 11:02:32 restore_aqua done              # no compositor pid= line

(repeats at 11:02:47 and 11:03:09)
```

Correlated app log:

```text
2026-08-19 11:02:30.563 Wawona[55661] HIToolbox: received notification of WindowServer event port death.
```

Helper begins WS teardown, kills WS PID on try 0, then aborts before launching niri (Aqua session death sends TERM; trap runs `restore_aqua`). Login agent fires again. Loop.

Killing WindowServer from an Aqua LaunchAgent is structurally broken: WS death tears down the session that owns the agent.

## Installed hooks (re-created after Aug 18 recovery)

- `~/Library/LaunchAgents/com.aspauldingcode.wawona.modeb-login.plist`: `RunAtLoad`, `sudo -n run-modeb.sh`
- `/etc/sudoers.d/wawona-modeb`: NOPASSWD engage (not restore-only)
- `/Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist`: re-enables WS when lock absent
- `DesktopReplacementEnabled = 1` in `com.aspauldingcode.wawona` prefs (before recovery)

## Recovery

Run once as **8amps** (admin):

```bash
bash /tmp/WAWONA_MODEB_RECOVERY_2026-08-19.sh
```

Then log out/in or reboot. WindowServer should stay up; Mode B will not auto-engage.

At 11:32 this machine already had: WindowServer up, no login agent, `DesktopReplacementEnabled=0`, helper replaced with the recovery stub.

## SIP status

```text
Boot-out failed: 150: Operation not permitted while System Integrity Protection is engaged
```

Mode B requires SIP fully disabled (`csrutil disable`). Partial SIP
(`csrutil enable --without debug`) is not sufficient for WindowServer
bootout (error 150) and is refused in Settings. Do not paper over that
with a WS reaper.

## Diff vs 2026-08-18 incident

| | Aug 18 | Aug 19 |
|---|--------|--------|
| `dylib=` in log | **Empty** | **Set correctly** |
| niri started | Yes, panicked (no Wayland host) | Yes at 10:24 |
| framebufferd | N/A | **Missing** |
| Login loop | Yes | Yes (faster, ~2s cycles) |
| WS reaper in helper | No | **Yes (new)** |

Same product area (Mode B login agent), different regression layer (injection incomplete + reaper + concurrent helpers).
