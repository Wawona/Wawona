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

Default (no flags) still opens the Machines control panel after the compositor
starts. That remains the product path for non-CLI users.
