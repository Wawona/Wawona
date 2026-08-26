# Wawona macOS CLI (power-user)

Start the compositor and bundled clients from the shell without opening the
Machines / Settings GUI.

```bash
/Applications/Wawona.app/Contents/MacOS/Wawona --help
```

## Bundled software on PATH

`nix run .#install` copies Wawona.app to `/Applications` and also drops
wrappers in `~/.local/bin` (and `/usr/local/bin` when that directory is
writable) for every bundled CLI that does not shadow Apple `/bin` or
`/usr/bin`:

```bash
weston-terminal
niri
foot
kmscube
waypipe
wawona --help
```

Wrappers point at the installed app, kick the compositor LaunchAgent if the
Wayland socket is missing, and set `WESTON_*` / `FONTCONFIG_FILE` /
`DYLD_LIBRARY_PATH`. They are not nix-store paths, so they survive GC.

Apple names (`ssh`, `zsh`, `vi`, `login`) stay in
`/Applications/Wawona.app/Contents/Resources/bin/` so host OpenSSH and zsh
are not replaced. `nix run .#uninstall` removes the wrappers and PATH
hooks.

PATH is prepended in `~/.zprofile` (login shells: Terminal.app) and, when
administrator authorization is available, in `/etc/zshenv.local`. nix-darwin
sources that file from `/etc/zshenv` for **every** zsh, including Cursor and
a nested `zsh` (those are not login shells, so `.zprofile` never runs).
home-manager `~/.zshrc` is a nix-store symlink and is left alone.

A shell that was already open still needs:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Or add `home.sessionPath = [ "$HOME/.local/bin" ];` and rebuild home-manager.

## Informational (no GUI, no instance lock)

| Flag | Effect |
|------|--------|
| `-h`, `--help` | Print usage and exit |
| `-v`, `--version` | Print version and exit |
| `--list-clients` | Bundled client ids for `--client` |
| `--list-machines` | Saved Machines profile ids for `--machine` |

## Headless compositor

| Flag | Effect |
|------|--------|
| `--headless`, `--no-gui` | Compositor only. No Machines / Settings window |
| `--gui` | Force Machines UI (overrides implied headless) |
| `--client <id>` | Launch a bundled client (implies `--headless` unless `--gui`) |
| `--machine <id>` | Connect a saved Machines profile (implies `--headless` unless `--gui`) |
| `--backend <mode>` | `auto` \| `wayland` \| `drm` (session-only; does not rewrite Settings) |

`--backend` is the same choice as **Settings → Advanced → Display Backend**:

- **wayland**. Nest Weston / Niri as a Wayland client of Wawona
- **drm**. Drive **wwn-iland** userspace DRM/KMS/GBM (needs OpenGL driver ≠ none)
- **auto**. Nested wayland (safe default)

## Examples

```bash
# Nested Weston (Wayland backend), no Machines window
Wawona --headless --backend wayland --client weston

# Niri nested on Wawona
Wawona --headless --backend wayland --client niri

# Niri on wwn-iland userspace DRM/KMS
Wawona --headless --backend drm --client niri

# Weston nested (Wayland). Preferred until in-process weston_main +
# drm-backend.so are packaged for macOS DRM
Wawona --headless --backend wayland --client weston

# Saved Machines profile by id
Wawona --list-machines
Wawona --machine <uuid>

# Point other tools at the running compositor
export XDG_RUNTIME_DIR=/tmp/wawona-$UID
export WAYLAND_DISPLAY=wayland-0
```

## Desktop Replacement (Mode B)

Headless operator for macOS Desktop / LockScreen replacement. No Machines
window. Logs to stdout plus `/tmp/wawona-modeb-cli.log` and
`/tmp/wawona-modeb.log`.

| Flag | Effect |
|------|--------|
| `--mode-b-status` | SIP, helper, sudoers, compositor PID (EPERM-aware), WindowServer, plus Classic `VERDICT` |
| `--mode-b-ready` | Classic gate. Prints `VERDICT` and `REASON`. `takeover-now` (exit 0), `reboot` (exit 2), `blocked` (exit 3) |
| `--mode-b-prepare` | Sync helper if needed and arm Path B. Does not take over. `reboot` opens the native Restart sheet |
| `--mode-b-probe` | Wait for a live root compositor without taking the screen |
| `--mode-b-engage` | `takeover-now`: take over now. `reboot`: open the native macOS Restart sheet (`kAERestart` / QA1134, 60-second countdown). `blocked`: print the exact reason and exit 3 |
| `--mode-b-disengage` | Full teardown: restore WindowServer, kill root compositor, remove helper / sudoers / login agent / dylib / ws-guard |

`nix run .#install` syncs `/Library/Application Support/Wawona/run-modeb.sh`,
copies this build's `libwayland-mac.dylib`, refreshes sudoers, and clears a
stale `modeb.lock`.
It prompts for administrator authorization once and fails if the helper
still points at a previous nix store or still `export`s
`DYLD_INSERT_LIBRARIES` (insert is compositor-only). It does not unload
WindowServer. It does not Take Over. Opening desktop-host Wawona also syncs
when the helper is stale. Public notes:
https://wawona.io/docs/desktop/ (install and updates).

`--mode-b-engage` uses the already-installed `sudo -n` helper when present, so
it does not block on an administrator dialog after a successful install.
Engage does not install a login LaunchAgent. The next Aqua login is normal
macOS. Take Over disables kernel IOWatchdog (`wwn-iowatchdog`), unloads
watchdogd, then WindowServer, then injects. Abort if IOWatchdog disable
fails. Probe (`--mode-b-probe`) may inject while both jobs stay up. SIP
must be fully disabled (`csrutil disable` in Recovery). Partial SIP
(`csrutil enable --without debug`) is refused.

```bash
Wawona --mode-b-status
Wawona --mode-b-ready
Wawona --mode-b-prepare
Wawona --mode-b-probe
Wawona --mode-b-engage
Wawona --mode-b-disengage
```

`--mode-b-ready` and Settings → Desktop → Status share
one gate. Helper `--ack-status` prints `verdict=` and `reason=`. Path B sock
`done=1` is takeover-now. `claim-ok` `path=b sticky=1` with sock not live is
reboot (native Restart sheet, not a custom timer). Path B pending / pathb
plist without live Disable is also reboot. Anything else is blocked.

Friends use Settings → Desktop: **Enable Desktop Replacement** then
**Replace now**. Enable checks coverage, heals if needed, stages the helper,
and runs bundled `wwn-iowatchdog-claim-install --path-b`, then Restart when
needed. It never Take Over. `--mode-b-prepare` is the same setup from the CLI.

`--mode-b-engage` on reboot opens loginwindow Restart (`kAERestart`). On
blocked it does not take over. On takeover-now it engages.

Until this build of `Wawona` is installed, the same report is:

```bash
./scripts/wawona-modeb-cli.sh ready
```

Default (no flags) still opens the Machines control panel after the compositor
starts. That remains the product path for non-CLI users.
