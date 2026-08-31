# Testing Commands ([#11](https://github.com/Wawona/Wawona/issues/11))

Copy-pasteable recipes for exercising a running Wawona session. For the
structured build matrix and per-platform smoke checklist, see
[`everywhere-matrix.md`](./everywhere-matrix.md).

Terminology: **DELIVERER** is a local Linux/NixOS machine reachable over SSH
(e.g. `alex@DELIVERER.local`) that hosts the Wayland apps Wawona connects to
through Waypipe.

## Remote apps over Waypipe (macOS)

Run a remote Wayland client through Waypipe + SSH and render it in Wawona.

Inspect the compositor a client sees (`wayland-info`):

```bash
nix run .#waypipe -- ssh alex@DELIVERER.local \
  "nix run --extra-experimental-features 'nix-command flakes' nixpkgs#wayland-utils"
```

A simple client (Weston terminal) forwarded from DELIVERER:

```bash
nix run .#waypipe -- ssh alex@DELIVERER.local "nix run ~/Wawona#weston-terminal"
```

From the app: Settings → Waypipe, set the SSH target and a Remote Command
(e.g. `nix run ~/Wawona#weston-terminal`), then tap Run Waypipe. The same path
is used for remote `sway`/`niri` sessions.

## Weston natively on macOS

```bash
nix run .#weston            # full nested compositor
nix run .#weston-terminal   # terminal client only
```

## iOS / iPadOS on-device native shell

In a `native` machine profile with the `weston-terminal` launcher, the bundled
in-process zsh runs these without any remote server. Smoke each command:

| Command | Expectation |
|---------|-------------|
| `whoami` | prints the sandbox user (`mobile`) |
| `ls` / `pwd` / `echo hello` | coreutils dispatch works |
| `fastfetch --version` | bundled client archive linked |
| `ssh -V` / `ssh user@host` | Apple-mobile stub (no OpenSSH); use `waypipe ssh` (libssh2) for remote |
| `waypipe --version` | `waypipe_main` responds |
| `nvim --version` | neovim TUI dispatch works |
| `apt --help` / `apt list` | in-process read-only `apt()` zsh function responds |

Architecture and per-command dispatch details:
[`../ios-local-shell/STATUS.md`](../ios-local-shell/STATUS.md) and
[`../ios-local-shell/ARCHITECTURE.md`](../ios-local-shell/ARCHITECTURE.md).

## Automated replays (agent-device)

Deterministic UI smoke scripts under [`.agent-device/`](../../.agent-device):

```bash
agent-device replay Wawona/.agent-device/wawona-ios-smoke.ad        # boot + panel
agent-device replay Wawona/.agent-device/wawona-ios-shell-cli.ad    # native shell CLIs
agent-device replay Wawona/.agent-device/wawona-ios-machines.ad     # machine editor
agent-device replay Wawona/.agent-device/wawona-android-smoke.ad
agent-device replay Wawona/.agent-device/wawona-android-machines.ad
```

The macOS convenience wrapper is `Wawona/scripts/agent-device-smoke.sh`.

## macOS OCI containers (Apple Containerization)

Requires `/usr/local/bin/container system start` (apiserver) and a kernel under
`~/Library/Application Support/com.apple.container/kernels/`. Prefer Wawona's
bundled CLI (`/Applications/Wawona.app/Contents/Resources/bin/container`) over
Apple's `/usr/local/bin/container` (different flags).

```bash
export PATH="/Applications/Wawona.app/Contents/Resources/bin:$PATH"
export WAWONA_CONTAINER_BACKEND=containerization
export WWN_OCI_ROOT="$HOME/.local/share/wawona/oci"
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/tmp/wawona-$(id -u)
export WWNP_WAYPIPE_BIN="$(dirname "$(command -v container)")/waypipe-fds"
export WAWONA_WAYPIPE_GUEST="$(dirname "$(command -v container)")/waypipe-guest-root"

# Terminal smoke (use a TTY or `script` so guest stdout is attached)
script -q /dev/null container run --rm --id wawona-echo alpine:3.20 /bin/echo OK-FROM-GUEST

# Desktop session: prebaked image (no nix shell at Start). Build image once:
#   nix build path:../wwn-containers#packages.aarch64-linux.wawona-container-desktop
#   container image load ./result
container run --rm --id wawona-flower --fs-size 8192 -m 2048 \
  --wayland-vsock-port 1042 \
  --waypipe-guest-root "$WAWONA_WAYPIPE_GUEST" \
  wawona-container-desktop:latest \
  weston-flower
```

`wwn-containerd` is **prebuilt** in the app bundle. Machines Start shows
**Starting container…** while the Apple Containerization VM boots (ready
markers), not a compile. Guest `nix shell` is gone from CLI recipes.

GUI: Machines → container profile → **Desktop session** on → image
`wawona-container-desktop:latest` → command `weston-flower`. Smoke helper:
`scripts/agent-device-container-smoke-macos.sh`.

### Container desktop client matrix (CLI)

CLI and GUI stay in sync. Prefer:

```bash
Wawona run flower    # auto-creates Machines card if missing
Wawona run sway      # sway + swaybg + Alt+Enter (ghostty/foot)
Wawona run hyprland
Wawona run ghostty
Wawona machines list
```

Legacy wrapper (calls `Wawona run`):

```bash
scripts/container-desktop-clients-macos.sh flower
scripts/container-desktop-clients-macos.sh sway
scripts/container-desktop-matrix-macos.sh
```

| Client | Notes | Status |
|---|---|---|
| `flower` | 200×200 weston-flower; entry has no `nix` | PASS once image loaded |
| `weston` / `niri` | native bundled (`Wawona run`) or container via script | PASS |
| `labwc` | container (prebaked) | PASS once image loaded |
| `sway` | config + Mod1+Return → ghostty/foot; no nix shell | PASS once image loaded |
| `hyprland` | prebaked Hyprland | PASS once image loaded |
| `ghostty` | container guest (or host `nix shell` for HiDPI debug) | PASS once image loaded |
| `plasma` / `gnome` | in prebaked image; need guest dbus | PARTIAL |

Assert no-compile: `Wawona run flower` then inspect profile
`containerSettings.entryCommand` (must not contain `nix shell`).

Sway binds: **Alt+Enter** opens Ghostty (falls back to foot under `--no-gpu` waypipe).
**Alt+Shift+E** exits.

Container profiles must **not** set `runtimeOverrides.bundledAppID` (that forces
fill-host for flower). Use **Container command** only.

### macOS / iOS Machines parity checklist

| Kind | macOS | iOS Mode A (store) |
|---|---|---|
| Native weston/niri/clients | available | available (in-process) |
| Container | Apple Containerization + prebaked OCI | container-in-VM (QEMU-TCTI); `WWN_CONTAINERS=1` until shipping |
| VM | QEMU+HVF; `WWN_VMS=1` | QEMU-TCTI; `WWN_VMS=1`; embed guest+engine |
| Wasm Runtime | available | available (interpreter; no JIT) |
| Hyprland / Ghostty | container-only | container-in-VM only (same guests) |

iOS Simulator: set `WAWONA_MOBILE_GUEST_DIR` + `WAWONA_MOBILE_VM_ENGINE_DIR` for
embed phases; without them Start fails closed with a clear error.

## Ghostty / GTK HiDPI (Retina quadrant check)

GTK4 clients (Ghostty) use `wp_fractional_scale` + `wp_viewporter`
destination. On a 2x display they must fill the window, not only the
bottom-left quadrant.

**Root cause (fixed):** `wp_viewporter.get_viewport` must map the
`wl_surface` to the compositor **internal** surface id (same as
`ensure_internal_surface_mapping` / scene). Keying by Wayland
`protocol_id` alone made destination apply miss on commit, so present
kept buffer-sized logical geometry at scale 1.

```bash
# Product path: Machines → Nix Weston Container (nixos/nix) with
#   nix shell nixpkgs#ghostty -c ghostty
# Or: Wawona run ghostty when the prebaked image includes ghostty.
# Expect: full window content on Retina, not one quadrant.
# Expect: a real terminal (not "Unable to acquire an OpenGL context").
# GPU transport is default (Disable GPU off + bundled Vulkan ICD).
# Disable GPU on → SHM; foot / weston-flower still work for that check.
```

Compare with `weston-terminal` / `foot` (integer buffer_scale path) on the same
Retina output.

## Android / Linux VM automation

```bash
nix run .#wawona-android        # Android build + adb install/launch smoke
nix run .#wawona-linux-vm     # NixOS Plasma 6 Wayland VM for Linux UI testing
```
