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
Classic Take Over needs Path B `claim-ok` **and** live Disable (marker or
Path B sock `status` with `done=1`). `WWN_MODEB_WD=iowatchdog-then-unload`.
claim-ok alone is **stale** after stage re-enables plain Apple `watchdogd`
(2026-08-20 evening SIGTRAP panic). Path A ACK stays lab. KEEP_WS
`--mode-b-probe` remains available **only** after the helper refuses
`restore_watchdogd` unless Classic left `wawona-unloaded-watchdogd`
(2026-08-20 KEEP_WS failure path re-enabled Apple under live Path B and
paniced). Operator Classic E2E:
`docs/desktop-replacement-classic-proof.md`. Incidents:
`docs/incident-reports/2026-08-20-stale-claim-ok-takeover/`,
`docs/incident-reports/2026-08-20-keepws-restore-watchdogd/`.

## Never

| Action | Why |
|--------|-----|
| Settings / CLI **Take Over Screen** without Path B `claim-ok` **and** live Disable | Unloads only after `path=b sticky=1` plus marker or sock `done=1` |
| Stage `watchdogd-ensure` while Path B/A armed or `claim-ok` present | Re-enables plain Apple `watchdogd` with monitoring armed; stale claim-ok then panics on unload |
| KEEP_WS / probe **failure** calling `restore_watchdogd` / Apple enable while Path B sticky | Never unloaded; enable races Path B → SIGTRAP (2026-08-20) |
| `launchctl` unload / `kickstart -k` on `com.apple.watchdogd` | Instant panic when monitoring is armed |
| Attach **lldb**, debugserver, or Cursor **lldb MCP** (`lldb_mcp.py`) to `watchdogd` | Attach exits the daemon with SIGTRAP |
| `thread_set_state` / soft-inject into `watchdogd` that uses set_state | Caller SIGKILL (137); also panic-class risk. Stopped after 2026-08-20 Phase 1 crash (`docs/macos26-iowatchdog-wall.md`) |
| Ad-hoc GOT write / inject / boot-arg probe loops on the daily driver | Soft-inject wall; use Path B / Path A installers instead |
| Blind `wwn-iowatchdog disable\|enable` via lldb during stage / install / healthy Aqua | Old lldb path paniced; use Path B sock or Path A claim only |
| Stage CLI at `…/Wawona/wwn-iowatchdog` (file) when Path B owns that path as a directory | `WWN_IOWATCHDOG` becomes a directory; restore mis-fires. Use `…/Wawona/bin/wwn-iowatchdog` |
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
