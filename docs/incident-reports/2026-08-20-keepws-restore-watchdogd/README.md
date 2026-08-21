# Incident: KEEP_WS probe failure restored Apple watchdogd under Path B (2026-08-20)

## Panic

```text
panic(cpu 0 caller …): watchdogd[3885] exited -- exit reason Namespace 2 subcode 0x5
OS version: 25F80
```

Same class as prior Mode B panics: `watchdogd` exited SIGTRAP while kernel
IOWatchdog userspace monitoring was still armed.

## Sequence that led here

1. Path B reboot was healthy: `claim-ok path=b sticky=1`, live marker /
   Path B sock `done=1`, coverage OK.
2. Agent ran KEEP_WS `--mode-b-probe` (Aqua stays up; never unloads
   `watchdogd`).
3. Probe failed for unrelated reasons:
   - niri baremetal/tty path still requires a host Wayland display on this
     build (`NIRI_BACKEND=tty` / unset `WAYLAND_DISPLAY` not enough).
   - Staged `WWN_IOWATCHDOG` pointed at
     `/Library/Application Support/Wawona/wwn-iowatchdog`, which Path B
     claim-install owns as a **directory** (hook + libs). CLI invoke failed:
     `is a directory`.
4. Failure teardown always called `restore_aqua` → `restore_watchdogd`.
5. `restore_watchdogd` unconditionally `launchctl enable` + bootstrap of
   **Apple** `com.apple.watchdogd`, removed the Disable marker when present,
   and raced Path B sticky coverage.
6. Result: Apple job map flipped enabled while Path B sticky Disable was
   still live; then `watchdogd` exited SIGTRAP → XNU panic.

KEEP_WS never unloaded `watchdogd`. Restore must not reverse an unload that
did not happen.

## Fixes (same tip)

- `restore_watchdogd` no-ops unless Classic left
  `/tmp/libwayland-support/wawona-unloaded-watchdogd` (touched only by
  `stop_watchdogd_after_iowatchdog`).
- If Path A/B claim / plists are still live: refuse Apple enable and
  `wwn-iowatchdog enable`; operator uses `claim-install --heal`.
- Stage CLI to `/Library/Application Support/Wawona/bin/wwn-iowatchdog`
  so it never collides with Path B's `…/wwn-iowatchdog/` directory.
- Uninstall / file-cleanup shell uses the same unload-marker gate.

## Operator after panic

```bash
defaults write com.aspauldingcode.Wawona DesktopReplacementEnabled -bool false
sudo …/wwn-iowatchdog-claim-install --heal
sudo …/wwn-iowatchdog-claim-install --doctor   # expect Apple coverage_ok
# Do NOT Classic / KEEP_WS until helper with skip restore_watchdogd is staged
# and baremetal compositor path works (weston DRM or fixed niri tty).
```

## Related

- `docs/incident-reports/2026-08-20-stale-claim-ok-takeover/`
- `docs/agent-rules/wawona-mode-b-watchdog-safety.md`
- `docs/desktop-replacement-classic-proof.md`
