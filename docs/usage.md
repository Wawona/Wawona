# Wawona Usage Guide

> Machines-first. Nested Weston and Niri. Bundled clients. Public subset for
> wawona.io.

---

## Machines

Start and focus sessions from the Machines window, not from env vars. Profile
kinds in the UI: **Native Shell**, **Virtual Machine**, **Container**. Native
Shell sessions cover Terminal (Wawona Terminal), Wayland clients, Wasm, and
Waypipe (optional SSH). See [`machine-profiles.md`](./machine-profiles.md) and
rule `wawona-machine-types`.

Weston and Niri stay real ports. Install as debs or wasm from repo.wawona.io.
The app keeps the compositor, zsh, uutils, and fastfetch. Display backend is
`CompositorBackend`: `auto` | `wayland` | `drm`.

VM and container Machine kinds are **planned** on macOS, iOS, iPadOS, Android,
and Linux. **forbidden** on tvOS, watchOS, and visionOS. See
[`vms-containers.md`](./vms-containers.md). The on-device shell is bundled zsh
on a native machine, not a guest.

---

## Linux (GTK / X11 / Wayland)

Preferred run (prebuilt GTK UI):

```bash
nix run .#wawona-linux
# same binary via consumer package name / default:
nix run .#wawona
nix run .
```

Install into the user profile:

```bash
cargo xtask install
# equivalent:
nix profile install .#wawona
```

Portable AppImage (CI product artifact `Wawona-{calver}-Linux-{arch}.AppImage`):

```bash
nix build .#wawona-appimage
./result/*.AppImage
```

Autostart / systemd user units keep the **compositor host** (Wayland socket)
alive. They do **not** reopen the Machines GTK window on login (Linux analog of
macOS quit policy). Tray Quit tears units down. Override the flake with
`WAWONA_FLAKE=/path/to/checkout` when needed.

Docker / non-interactive Nix: keep LF line endings on `*.nix` (see
`.gitattributes`). CRLF checkouts break `wawona-linux-run` (issue #164).


## Guest Machines (planned)

In-app `virtual_machine` / `container` profiles (coming soon):

| Platform | Planned engine |
|----------|----------------|
| macOS | `Virtualization.framework` + Containerization |
| iOS / iPadOS | Relay. Planned. Fail closed. No QEMU / UTM |
| Android | `wwn-vms` / `wwn-containers` |
| Linux | `wwn-vms` / `wwn-containers` |

## Dev / CI hosts (not the Machines VM kind)

| Host | How |
|------|-----|
| iOS Simulator | `cargo xtask build ios`, or Run `Wawona-iOS` in Xcode |
| iOS TrollStore vphone (Mode B) | `cargo xtask package ios-mode-b`, then `agent-device packages tipa install … --device "vphone wawona-jb"` |
| iOS Sileo / jailbreak vphone (Mode B) | `cargo xtask package ios-mode-b`, then `agent-device packages apt install … --device "vphone wawona-jb"` |
| Android emulator | `cargo xtask build android`, or Run in Android Studio |
| Linux QEMU NixOS | `nix run .#wawona-linux-vm` |

---
## Native Weston on macOS (No Linux)

Wawona includes a **native port of Weston** for macOS. No Linux, no VM. Weston runs as a nested compositor client inside Wawona.

### Weston, niri and other clients

Weston and niri install as optional software from
[repo.wawona.io](https://repo.wawona.io) and start from Machines (Native
Shell). They run natively on macOS, inside Wawona's Wayland session.

The clients bundled in Wawona.app are on PATH after `cargo xtask install`
(see [`macos-cli.md`](./macos-cli.md)):

```bash
weston-terminal
foot
```

---

## Waypipe: Remote Wayland Apps

Waypipe forwards Wayland applications over SSH. Run apps on a remote Linux/Mac and display them on your device.

### Prerequisites

1. **Wawona running** on your device (macOS, iOS, or Android)
2. **Remote host** with Waypipe and the app you want to run
3. **SSH access** to the remote host

### Prepare the Remote Mac

If your remote host is a Mac:

```bash
bash scripts/prepare_mac_remote.sh
```

This checks:
- Remote Login (SSH) is enabled
- Waypipe is available (system or Nix)
- Weston Terminal is buildable

### Configure in Wawona Settings

1. Open **Wawona** → **Settings** → **Waypipe** (or **SSH**)
2. **SSH Host**: IP address or hostname of the remote machine
3. **SSH User**: Your username on the remote
4. **SSH Password** (or **Public Key**): Authentication
5. **Remote Command**: The app to run remotely, e.g.:
   - `weston-terminal`
   - `foot`
6. Tap **Run Waypipe** (or **Start Waypipe** on mobile)

### Command-Line Waypipe (macOS)

With Wawona running, you can also run waypipe from a terminal:

```bash
# Ensure Wawona has set up the socket
export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
export WAYLAND_DISPLAY="wayland-0"

# Run waypipe to a remote host
waypipe ssh user@remote-host weston-terminal
```

The **Shell Setup** in Settings > Connection shows the exact `export` commands for your session.

### Remote Command Examples

| Command | Description |
|---------|-------------|
| `weston-terminal` | Weston Terminal (if installed on remote) |
| `foot` | Foot terminal |
| `geary` | Geary email client |
| `gnome-calculator` | GNOME Calculator |

---

## Connecting Wayland Clients Locally

When Wawona is running, clients connect via the Wayland socket.

### Get Socket Path

In **Settings > Connection**, you'll see:
- **XDG_RUNTIME_DIR**. E.g. `/tmp/wawona-$(id -u)`
- **WAYLAND_DISPLAY**. E.g. `wayland-0`
- **Shell Setup**. Copy-paste snippet for your terminal

### Run a Client

```bash
export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
export WAYLAND_DISPLAY="wayland-0"

# Then run any Wayland client
weston-terminal
foot
```

---

## Platform Notes

| Platform | Weston | Waypipe |
|----------|--------|---------|
| **Linux** | `nix run` (GTK shell + nested Wawona host service) | GUI-first Machine launcher (Native/SSH/Waypipe) |
| **macOS** | Machines (optional software); bundled clients on PATH | OpenSSH process spawn; Settings > Waypipe |
| **iOS** | Via Settings > Advanced toggles | libssh2 in-process; Settings > Waypipe, SSH |
| **Android** | Via Settings > Advanced toggles | OpenSSH portable (`wwn-ssh`); Machines > Waypipe |

On iOS and Android, **Enable Native Weston** and **Enable Weston Terminal** in Settings > Advanced start these on app launch.

---

## Report a bug

If Start does nothing or a session looks wrong, copy logs from Settings and file a GitHub issue. Steps: [`reporting-bugs.md`](reporting-bugs.md).
