# Classic Desktop Replacement proof (macOS 26 / 25F80)

Operator checklist after product wiring (`WWN_MODEB_WD=iowatchdog-then-unload`).
Do **not** mark Phase 3 PASS until every step is green.

**Weston-first.** Classic proof uses a Weston Desktop machine (`NativeClientId=weston`,
`--backend=drm`). Niri is deferred until `NIRI_BACKEND=tty` works without a host
Wayland display.

## Hard forbids

- lldb / `lldb_mcp` on `watchdogd` or WindowServer
- `kickstart -k` on `com.apple.watchdogd`
- Take Over without `/var/db/wwn-iowatchdog/claim-ok` (`sticky=1`) **and** live
  Disable (marker or Path B sock `done=1`)
- `export DYLD_INSERT_LIBRARIES` in a parent shell
- KEEP_WS / probe while helper lacks `skip restore_watchdogd` (2026-08-20
  KEEP_WS failure re-enabled Apple under Path B and paniced)

## Preconditions

```bash
# Coverage
sudo "$(nix build --no-link --print-out-paths \
  /path/to/wwn-iowatchdog#wwn-iowatchdog)/bin/wwn-iowatchdog-claim-install" --doctor
# expect: coverage_ok yes

# SIP fully disabled (Settings → Desktop shows Fully Disabled)
csrutil status | head -1

# Staged helper must refuse restore_watchdogd unless Classic unloaded
grep -q 'skip restore_watchdogd' \
  "/Library/Application Support/Wawona/run-modeb.sh"
```

## 0. Select Weston Desktop (CLI)

```bash
Wawona --mode-b-machine weston
# creates "Weston Desktop" if needed; sets DesktopReplacementMachineId
Wawona --mode-b-status
# expect: eligible list with * on weston machine; client=weston
```

Or one-shot: `Wawona --mode-b-probe --machine <id-or-name>`.

## 1. Arm Path B (preferred)

From a desktop-host app or nix package that contains `bin/` + `lib/hook`:

```bash
PKG=…/Contents/Library/Wawona   # or nix package root
sudo "$PKG/wwn-iowatchdog-claim-install" --path-b "$PKG"
sudo "$PKG/wwn-iowatchdog-claim-install" --doctor
# expect: path_b_plist yes, pending yes, live pid, coverage_ok yes
```

**Reboot now.**

## 2. After reboot: ACK

```bash
cat /var/db/wwn-iowatchdog/claim-ok
# expect: ok path=b sticky=1 …
sudo …/wwn-iowatchdog-claim-install --doctor
# expect: coverage_ok yes (Path B or Apple process alive)
# plus live Disable: marker or Path B sock status done=1
```

## 3. Stage + KEEP_WS (before Classic)

1. `WAWONA_MODEB_STAGE=1 nix run .#install` (or `Wawona --mode-b-stage`) once.
2. Assert CLI at `/Library/Application Support/Wawona/bin/wwn-iowatchdog` (file).
3. `Wawona --mode-b-probe` with weston selected; Aqua stays up; log must **not**
   Apple-enable `watchdogd` on success or failure (`skip restore_watchdogd`).

## 4. Classic Take Over

1. Settings → Desktop → IOWatchdog ACK shows Path B sticky (+ live Disable).
2. Desktop machine = weston (CLI or Settings).
3. **Take Over Screen Now** → screen owned ≥60s, no panic.
4. Logout → Aqua + WindowServer + coverage; `--doctor` green.

## 5. Refuse path

With `claim-ok` removed (or after `--heal` / `--uninstall` that clears arms
and restores Apple **without** a new ACK): Take Over must refuse and leave
Aqua up.

## 6. Record PASS

When 0–5 are green, update:

- `wwn-iowatchdog/docs/macos26-iowatchdog-wall.md` Phase 3 → **PASS**
- `docs/iland-mode-a-b-desktop.md` status off “coming soon”
- This file: date + machine + calver tip

Until then Phase 3 stays **HOLD** after the 2026-08-20 panics.
See `docs/incident-reports/2026-08-20-stale-claim-ok-takeover/` and
`docs/incident-reports/2026-08-20-keepws-restore-watchdogd/`.
