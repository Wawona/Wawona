# 2026-08-23: Classic Aqua restore + Path B kickstart → IOWatchdog timeout

## Panic (25F80)

```text
panic(cpu 0 caller …): watchdog timeout: no checkins from watchdogd in 92 seconds
(8 total checkins since monitoring last enabled)
OS version: 25F80
Panicked task: launchd
Kernel extension: com.apple.driver.AppleARMWatchdogTimer
```

This is **not** the SIGTRAP class (`watchdogd[pid] exited`, namespace 2 /
subcode 0x5). Kernel IOWatchdog monitoring was **re-enabled**, `watchdogd`
checked in 8 times, then went silent for ~92s. Same family as the 2026-08-21
"no checkins / WindowServer missing" timeout.

Sleep/Wake timestamps were present in the paniclog.

## Sequence

1. Path B was healthy (`claim-ok path=b sticky=1`). Operator used **Replace
   now** (Classic Take Over). Mode B client was `igettyd` (Doorman + VT
   switcher). GUI VT was 0 (no Desktop compositor on a graphics VT).
2. Login on a text VT. Typed `niri`. `libwayland-mac.dylib` used to
   `abort()` unless euid was 0 (`must run as root`). `sudo niri` then
   started, but sudo stripped insert, so the TTY backend opened a real
   missing `/dev/dri` node (`error opening the primary GPU DRM node`,
   ENOENT). Product path: type `niri` as the login user. Insert iland
   DRM hooks only. Never sudo. Never a real DRM node.
3. Operator switched to tty02 (`[igettyd] switch VT 1 -> 2`). Ctrl+Option+F2
   is the VT chord. Ctrl+Option+Backspace is the Aqua restore chord. Aqua
   still came back (client exit and/or restore stamp).
4. `restore_aqua` restored WindowServer, then `restore_watchdogd`.
5. The Path B sticky branch **refused Apple `watchdogd` enable** (correct,
   2026-08-20 SIGTRAP) but **did** `launchctl bootstrap` + `kickstart`
   `system/com.aspauldingcode.wwn-iowatchdog-pathb`.
6. Path B wrapper execs hooked `/usr/libexec/watchdogd` with
   `WWN_IOW_AUTO_DISABLE=1`. That start re-armed kernel monitoring (8
   checkins). AUTO_DISABLE / restart then left the kernel with no checkins
   for 92s → panic.

Take Over already `bootout` Path B in `stop_watchdogd_after_iowatchdog`.
Kernel Disable is sticky after `done=1`. Post-Classic Aqua must look like
post-Prepare with WindowServer up, `claim-ok` still sticky, **kernel still
Disabled**, Apple `watchdogd` **not** started, Path B job **not**
kickstarted.

## Fixes

1. `restore_watchdogd` Path A/B sticky branch: do **not** bootstrap or
   kickstart Path B. Do **not** Apple-enable `watchdogd`. Do **not**
   `wwn-iowatchdog enable`. Drop `wawona-unloaded-watchdogd` and return.
   Keep the Disable marker so the next Replace now can treat marker + Path B
   job-down as live Disable.
2. Helper fingerprint `WWN_MODEB_WD=pathb-no-kickstart-after-classic`. Stale
   helpers that still contain `Path B bootstrap after Classic` must restage.
3. Typed `niri` / `weston` on a text VT: login user, never sudo. Wrappers
   prefix `WWN_MODEB_INSERT` on that exec only. The dylib constructor
   installs iland DRM hooks for any euid and does not spawn helpers unless
   root (Classic). `sudo niri` strips insert and hits ENOENT on a real
   `/dev/dri` path that must not exist.

## Do not

- Take Over until `WAWONA_MODEB_STAGE=1 nix run .#install` restages the
  helper (this change is dead in the installed `run-modeb.sh` until then).
- Heal Path B or `kickstart -k` Apple `watchdogd` to "fix" coverage.
- Attach lldb to `watchdogd`.

## Verify after restage

```bash
grep -q 'WWN_MODEB_WD=pathb-no-kickstart-after-classic' \
  "/Library/Application Support/Wawona/run-modeb.sh"
grep -q 'Path B bootstrap after Classic' \
  "/Library/Application Support/Wawona/run-modeb.sh" && echo STALE || echo ok
pgrep -l watchdogd
pgrep -lf lldb_mcp || echo lldb_mcp_gone
cat /var/db/wwn-iowatchdog/claim-ok
```
