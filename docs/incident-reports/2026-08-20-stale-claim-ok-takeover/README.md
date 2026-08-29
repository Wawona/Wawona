# Incident: watchdogd SIGTRAP after stale claim-ok Take Over (2026-08-20)

## Panic

```text
panic(cpu 1 caller …): watchdogd[79191] exited -- exit reason Namespace 2 subcode 0x5
OS version: 25F80
```

Same class as prior Mode B panics: `watchdogd` exited with SIGTRAP while
kernel IOWatchdog userspace monitoring was still armed.

## Sequence that led here

1. Path B arm + reboot produced real sticky Disable and
   `/var/db/wwn-iowatchdog/claim-ok` (`path=b sticky=1`).
2. Tip desktop-host **stage** ran `watchdogd-ensure`, which
   `launchctl enable` + `bootstrap` of **Apple** `com.apple.watchdogd`.
3. After stage: Apple job **enabled** and running plain `/usr/libexec/watchdogd`
   (no Path B `DYLD_INSERT`). Path B plist was `spawn scheduled` / inactive.
   Path B sock inode stale (`Connection refused`). **Disable marker absent**.
4. `claim-ok` file still said sticky. Product Classic gate trusted the file
   alone and (in the helper) even **wrote** a fake
   `iowatchdog-userspace-disabled` marker before unload.
5. Unloading / exiting that armed `watchdogd` paniced XNU.

## Fixes (same tip)

- Stage skips Apple `watchdogd-ensure` when claim-ok / pending / Path A/B
  plists are present.
- Classic gate requires **live** Disable (marker or Path B sock `done=1`),
  not claim-ok alone.
- Helper must not invent the disable marker before unload.
- KEEP_WS probe still leaves Aqua and Apple/Path B jobs alone.

## Operator recovery

```bash
sudo "$(nix build --no-link --print-out-paths \
  /path/to/wwn-iowatchdog#wwn-iowatchdog)/bin/wwn-iowatchdog-claim-install" --heal
sudo …/wwn-iowatchdog-claim-install --doctor   # coverage_ok, no stale Path B
# Re-arm Path B only when ready for another reboot proof:
#   sudo …/wwn-iowatchdog-claim-install --path-b <pkg>
# After reboot: claim-ok AND marker or sock status done=1 before Take Over.
```

Never Take Over on claim-ok alone. Never stage-enable Apple while Path B is
armed.
