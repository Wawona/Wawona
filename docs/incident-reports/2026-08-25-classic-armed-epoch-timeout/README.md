# 2026-08-25: Classic DRM session + armed IOWatchdog epoch timeout

## Panic (25F80)

```text
panic(cpu 1 caller …): watchdog timeout: no checkins from watchdogd in 90 seconds
(3922 total checkins since monitoring last enabled)
OS version: 25F80
Kernel extension: com.apple.driver.AppleARMWatchdogTimer
Sleep/Wake timestamps present
```

This is the **kernel IOWatchdog** family (`no checkins from watchdogd` /
`AppleARMWatchdogTimer` / ~90s). It is **not** the SIGTRAP class
(`watchdogd[pid] exited`, namespace 2 / subcode 0x5). It is **not** the
userspace WindowServer 120s family.

Compared to [2026-08-23](../2026-08-23-vt-switch-restore-aqua-timeout/): same
panic string, but **3922** checkins (long armed epoch) vs **8** (Path B
kickstart re-arm). Different root cause.

## Session symptoms (same boot)

1. **niri** on a Doorman text VT: insert loaded (`client-only insert uid=503`)
   but TTY backend panicked on `error opening the primary GPU DRM node` (ENOENT).
   `DrmNode::from_path` uses `stat("/dev/dri/card0")`; Mode B only hooked
   `open`/`ioctl` until this fix.
2. **weston** on the same VT: DRM/EGL init succeeded (`/dev/dri/card0`, ANGLE
   Metal, DP-1), brief black flash, then TTY text returned while weston stayed
   alive. igettyd kept pageflipping console dumb BOs over the compositor.
3. **F7-F9** (kmscube / gbm-es2 / vkcube): kernel panic ~90s later. Overlay
   switch used non-blocking `stop_graphics`; typed weston was not `gfx_pid`, so
   two DRM clients fought for card0 while **watchdogd was still checking in**
   (3922 total since monitoring last enabled).

## What 3922 checkins implies

The counter is **since monitoring last enabled**. Thousands of checkins means
kernel userspace monitoring stayed **armed** with a live `watchdogd` for a long
epoch (on the order of an hour at ~1 Hz), then silence for ~90s.

That is **not** a successful Classic Take Over that applied sticky kernel
Disable and unloaded `watchdogd`. Disable + close is sticky until Reenable;
with Disable effective, this panic string cannot fire after unload.

Likely: Take Over proceeded on **stale marker** or claim-ok without Path B sock
`done=1` while plain `watchdogd` was still alive and armed.

## Fixes (this change)

1. **wwn-iland:** hook `stat`/`lstat`/`fstat`/`fstatat` for `/dev/dri/*` and
   `fstat` on `DRM_VIRTUAL_FD`; udev `devnum` returns `makedev(226,0)`. Publish
   `modeb-drm-client.pid` from the dylib while any DRM client runs.
2. **wwn-igetty:** skip text-VT scanout while `modeb-drm-client.pid` is alive
   (typed `weston`/`niri` on a login TTY is the designed path); blocking
   `stop_graphics` and `stop_external_drm_clients` before GUI / F7-F9 overlays.
3. **Wawona helper:** Classic Take Over and `--ack-status` refuse marker-only
   LIVE when `pgrep -x watchdogd` succeeds without Path B sock `done=1`.

## Operator recovery

```bash
sudo wwn-iowatchdog-claim-install --heal
sudo wwn-iowatchdog-claim-install --doctor   # coverage_ok before next Classic
# Re-arm Path B when ready:
#   sudo wwn-iowatchdog-claim-install --path-b <pkg>
# Reboot; confirm claim-ok AND sock status done=1 before Replace now.
nix run .#install   # restage helper with new gates
```

Do not Classic-test until `--doctor` is green. Never Take Over on claim-ok alone.

## Verify after restage

```bash
grep -q 'marker without Path B sock done=1' \
  "/Library/Application Support/Wawona/run-modeb.sh"
pgrep -l watchdogd
cat /var/db/wwn-iowatchdog/claim-ok
python3 -c "import socket;s=socket.socket(socket.AF_UNIX);s.connect('/var/run/wwn-iowatchdog.sock');s.send(b'status\n');print(s.recv(256).decode())"
```
