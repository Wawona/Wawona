# Mode B watchdog safety (macOS 26)

**Hard forbid** for agents and humans on this machine class (macOS 26 / 25F80).

Exiting `watchdogd` with SIGTRAP (paniclog **namespace 2 / subcode 0x5**) while
kernel IOWatchdog is still armed causes an immediate XNU panic:

```text
watchdogd[pid] exited -- exit reason namespace 2 subcode 0x5
```

Incident history: `docs/incident-reports/2026-08-19-windowserver-login/`.
Product Mode A/B: `wawona-iland-mode-b-desktop`, `docs/iland-mode-a-b-desktop.md`.
Watchdog tools repo: `github.com/Wawona/wwn-iowatchdog`.

## Never

| Action | Why |
|--------|-----|
| Settings / CLI **Take Over Screen** | Unloads `watchdogd` / WindowServer; blocked (`WWN_MODEB_WD=blocked-no-iowatchdog`) until a non-lldb IOWatchdog disable exists |
| `launchctl` unload / `kickstart -k` on `com.apple.watchdogd` | Instant panic when monitoring is armed |
| Attach **lldb**, debugserver, or Cursor **lldb MCP** (`lldb_mcp.py`) to `watchdogd` (or WindowServer / `IOWatchdogUserClient` holders) | Attach exits the daemon with SIGTRAP |
| `wwn-iowatchdog disable\|enable` during stage, install, blind `--restore-aqua`, or healthy app open | Old lldb fallback and blind enable paniced repeatedly on 2026-08-20 |
| Install `ws-guard` on the blocked Take Over refuse path | Privileged WindowServer `launchctl` right before refuse; not needed when Aqua stays up |
| Default `nix run .#install` Mode B restage | Opt-in only: `WAWONA_MODEB_STAGE=1` for probe helper |

## Required agent behavior

1. Prefer **Mode A** in-window iland. Leave Aqua and `watchdogd` running.
2. Before any Mode B / Desktop Replacement / IOWatchdog work: kill Cursor LLDB MCP if present (`pkill -f lldb_mcp.py`) and confirm `pgrep -l watchdogd`.
3. Settings UX: Take Over is **unavailable**. Do not stage a helper just to show a failure alert.
4. Probe-only path (Aqua stays up): `WAWONA_MODEB_STAGE=1 nix run .#install`, then `Wawona --mode-b-probe` (KEEP_WS). Still never unload `watchdogd`.
5. `wwn-iowatchdog` defaults to fail-closed (no IOKit open). Experiments only with `WWN_IOWATCHDOG_ALLOW_OPEN=1`.

## Quick check

```bash
pgrep -l watchdogd
pgrep -lf lldb_mcp || echo lldb_mcp_gone
ls "/Library/Application Support/Wawona"   # prefer: absent
defaults read com.aspauldingcode.Wawona DesktopReplacementEnabled  # prefer: 0
```

## Cursor mirror

`.cursor/rules/wawona-mode-b-watchdog-safety.mdc` (`alwaysApply: true`) in the
workspace and under `Wawona/.cursor/rules/`.
