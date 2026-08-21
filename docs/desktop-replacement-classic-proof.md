# Classic Desktop Replacement proof (macOS 26 / 25F80)

Operator checklist after product wiring (`WWN_MODEB_WD=iowatchdog-then-unload`).
Do **not** mark Phase 3 PASS until every step is green.

## Hard forbids

- lldb / `lldb_mcp` on `watchdogd` or WindowServer
- `kickstart -k` on `com.apple.watchdogd`
- Take Over without `/var/db/wwn-iowatchdog/claim-ok` (`sticky=1`)
- `export DYLD_INSERT_LIBRARIES` in a parent shell

## Preconditions

```bash
# Coverage
sudo "$(nix build --no-link --print-out-paths \
  /path/to/wwn-iowatchdog#wwn-iowatchdog)/bin/wwn-iowatchdog-claim-install" --doctor
# expect: coverage_ok yes

# SIP fully disabled (Settings → Desktop shows Fully Disabled)
csrutil status | head -1
```

## 1. Arm Path B (preferred)

From a desktop-host app or nix package that contains `bin/` + `lib/hook`:

```bash
PKG=…/Contents/Library/Wawona   # or nix result root
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
```

## 3. Classic Take Over

1. `WAWONA_MODEB_STAGE=1 nix run .#install` (or Settings stage) once.
2. Settings → Desktop → IOWatchdog ACK shows Path B sticky.
3. Pick niri (then weston) as Desktop Machine.
4. **Take Over Screen Now** → screen owned ≥60s, no panic.
5. Logout → Aqua + WindowServer + Apple `watchdogd`; `--doctor` green.

## 4. Refuse path

With `claim-ok` removed (or after `--heal` / `--uninstall` that clears arms
and restores Apple **without** a new ACK): Take Over must refuse and leave
Aqua up.

## 5. Record PASS

When 1–4 are green, update:

- `wwn-iowatchdog/docs/macos26-iowatchdog-wall.md` Phase 3 → **PASS**
- `docs/iland-mode-a-b-desktop.md` status off “coming soon”
- This file: date + machine + calver tip

Until then Phase 3 stays **product wired; Classic E2E proof pending**.
