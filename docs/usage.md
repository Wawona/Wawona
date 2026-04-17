# Wawona Usage Guide

> How to run Weston natively on macOS, use Waypipe for remote apps, and connect Wayland clients.

---

## Native Weston on macOS (No Linux)

Wawona includes a **native port of Weston** for macOS. No Linux, no VM — Weston runs as a nested compositor client inside Wawona.

### Weston (Full Compositor)

```bash
nix run .#weston
```

Launches the full Weston compositor as a nested client. Weston runs natively on macOS, inside Wawona's Wayland session.

### Weston Terminal

```bash
nix run .#weston-terminal
```

Launches Weston Terminal — a native Wayland terminal client. Connects to Wawona's Wayland display.

### Other Weston Clients

```bash
nix run .#weston-debug      # Weston debug client
nix run .#weston-simple-shm # Simple SHM test client
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
   - `nix run ~/Wawona#weston-terminal`
   - `weston-terminal`
   - `foot`
   - `nix run ~/Wawona#weston` (full Weston compositor)
6. Tap **Run Waypipe** (or **Start Waypipe** on mobile)

### Command-Line Waypipe (macOS)

With Wawona running, you can also run waypipe from a terminal:

```bash
# Ensure Wawona has set up the socket
export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
export WAYLAND_DISPLAY="wayland-0"

# Run waypipe to a remote host
nix run .#waypipe -- ssh user@remote-host weston-terminal
```

The **Shell Setup** in Settings > Connection shows the exact `export` commands for your session.

### Remote Command Examples

| Command | Description |
|---------|-------------|
| `nix run ~/Wawona#weston-terminal` | Weston Terminal (if Wawona repo on remote) |
| `weston-terminal` | Weston Terminal (if installed on remote) |
| `foot` | Foot terminal |
| `nix run ~/Wawona#weston` | Full Weston compositor |
| `geary` | Geary email client |
| `gnome-calculator` | GNOME Calculator |

---

## Connecting Wayland Clients Locally

When Wawona is running, clients connect via the Wayland socket.

### Get Socket Path

In **Settings > Connection**, you'll see:
- **XDG_RUNTIME_DIR** — e.g. `/tmp/wawona-$(id -u)`
- **WAYLAND_DISPLAY** — e.g. `wayland-0`
- **Shell Setup** — copy-paste snippet for your terminal

### Run a Client

```bash
export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
export WAYLAND_DISPLAY="wayland-0"

# Then run any Wayland client
nix run .#weston-terminal
nix run .#foot
```

---

## Platform Notes

| Platform | Weston | Waypipe |
|----------|--------|---------|
| **Linux** | `nix run` (GTK shell + nested Wawona host service) | GUI-first Machine launcher (Native/SSH/Waypipe) |
| **macOS** | `nix run .#weston`, `.#weston-terminal` | OpenSSH process spawn; Settings > Waypipe |
| **iOS** | Via Settings > Advanced toggles | libssh2 in-process; Settings > Waypipe, SSH |
| **Android** | Via Settings > Advanced toggles | Dropbear SSH; Settings > Waypipe, SSH |

On iOS and Android, **Enable Native Weston** and **Enable Weston Terminal** in Settings > Advanced start these on app launch.
