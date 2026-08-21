# Mode B watchdog safety (macOS 26)

**Hard forbid** for agents and humans on this machine class (macOS 26 / 25F80).

Exiting `watchdogd` with SIGTRAP (paniclog **namespace 2 / subcode 0x5**) while
kernel IOWatchdog is still armed causes an immediate XNU panic:

```text
watchdogd[pid] exited -- exit reason Namespace 2 subcode 0x5
```

Incident history: `docs/incident-reports/2026-08-19-windowserver-login/`.
Product Mode A/B: `wawona-iland-mode-b-desktop`, `docs/iland-mode-a-b-desktop.md`.
Watchdog tools repo: `github.com/Wawona/wwn-iowatchdog`
([`docs/path-a-path-b.md`](https://github.com/Wawona/wwn-iowatchdog/blob/development/docs/path-a-path-b.md)
operator guide; [`docs/macos26-iowatchdog-wall.md`](https://github.com/Wawona/wwn-iowatchdog/blob/development/docs/macos26-iowatchdog-wall.md)
investigation wall). Path B reboot sticky disable is **proven** on 25F80;
Take Over product gate consumes Path B `claim-ok` only (`path=b sticky=1`,
`WWN_MODEB_WD=iowatchdog-then-unload`). Path A ACK stays lab. Without Path B
ACK, Classic Take Over refuses; KEEP_WS `--mode-b-probe` remains available.
Operator Classic E2E: `docs/desktop-replacement-classic-proof.md`.

## Never

| Action | Why |
|--------|-----|
| Settings / CLI **Take Over Screen** without Path B sticky `claim-ok` | Unloads `watchdogd` / WindowServer only after `path=b sticky=1`; refuse otherwise |
| `launchctl` unload / `kickstart -k` on `com.apple.watchdogd` | Instant panic when monitoring is armed |
| Attach **lldb**, debugserver, or Cursor **lldb MCP** (`lldb_mcp.py`) to `watchdogd` | Attach exits the daemon with SIGTRAP |
| `thread_set_state` / soft-inject into `watchdogd` that uses set_state | Caller SIGKILL (137); also panic-class risk. Stopped after 2026-08-20 Phase 1 crash (`docs/macos26-iowatchdog-wall.md`) |
| Ad-hoc GOT write / inject / boot-arg probe loops on the daily driver | Soft-inject wall; use Path B / Path A installers instead |
| Blind `wwn-iowatchdog disable\|enable` via lldb during stage / install / healthy Aqua | Old lldb path paniced; use Path B sock or Path A claim only |
| Install `ws-guard` when Classic Take Over refuses (no ACK) | Not needed when Aqua stays up |
| Default `nix run .#install` Mode B restage | Opt-in only: `WAWONA_MODEB_STAGE=1` |

## What `status` may do

`sudo wwn-iowatchdog status` may locate the live `IOWatchdogUserClient` port
name via `task_for_pid` + `mach_port_kobject_description`. Sticky Disable
ACK comes from Path B (`claim-ok` / sock) or Path A claim. Soft-inject
`disable`/`enable`/`inject` stay fail closed. Operator guide:
`wwn-iowatchdog/docs/path-a-path-b.md`.

## Required agent behavior

1. Prefer **Mode A** in-window iland when Path B ACK is missing. Leave Aqua
   and `watchdogd` running.
2. Before any Mode B / IOWatchdog work: `pkill -f lldb_mcp.py` and confirm
   `pgrep -l watchdogd`.
3. Settings UX: Take Over is available only when Path B `claim-ok` is present;
   otherwise show arm steps. Do not stage a helper just to show a failure alert.
4. Probe-only path (Aqua stays up): `WAWONA_MODEB_STAGE=1 nix run .#install`,
   then `Wawona --mode-b-probe` (KEEP_WS). Still never unload `watchdogd`
   without Path B ACK.

## Quick check

```bash
pgrep -l watchdogd
pgrep -lf lldb_mcp || echo lldb_mcp_gone
ls "/Library/Application Support/Wawona"   # prefer: absent
defaults read com.aspauldingcode.Wawona DesktopReplacementEnabled  # prefer: 0
```

## Cursor mirror

`.cursor/rules/wawona-mode-b-watchdog-safety.mdc` (`alwaysApply: true`).
