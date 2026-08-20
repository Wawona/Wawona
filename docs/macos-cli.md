# Wawona macOS CLI (power-user)

Start the compositor and bundled clients from the shell without opening the
Machines / Settings GUI.

```bash
/Applications/Wawona.app/Contents/MacOS/Wawona --help
```

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
| `--mode-b-status` | SIP, helper, sudoers, compositor PID (EPERM-aware), WindowServer |
| `--mode-b-stage` | Install helper + dylib for this build. Does not take over the screen |
| `--mode-b-probe` | Wait for a live root compositor without taking the screen |
| `--mode-b-engage` | Enable Desktop Replacement and take over the screen |
| `--mode-b-disengage` | Full teardown: restore WindowServer, kill root compositor, remove helper / sudoers / login agent / dylib / ws-guard |

`nix run .#install` always runs `--mode-b-stage`. That restages
`/Library/Application Support/Wawona/run-modeb.sh`, copies this build's
`libwayland-mac.dylib`, refreshes sudoers, and clears a stale `modeb.lock`.
It prompts for administrator authorization once and fails if the helper
still points at a previous nix store or still `export`s
`DYLD_INSERT_LIBRARIES` (insert is compositor-only). It does not unload
WindowServer.

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
Wawona --mode-b-stage
Wawona --mode-b-probe
Wawona --mode-b-engage
Wawona --mode-b-disengage
```

Default (no flags) still opens the Machines control panel after the compositor
starts. That remains the product path for non-CLI users.
