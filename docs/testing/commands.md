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

# Desktop session: weston-flower over vsock waypipe (guest-root + oneshot listen)
container run --rm --id wawona-flower --fs-size 8192 -m 2048 \
  --wayland-vsock-port 1042 \
  --waypipe-guest-root "$WAWONA_WAYPIPE_GUEST" \
  nixos/nix \
  /bin/sh -lc "nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#weston -c weston-flower"
```

GUI: Machines → container profile → **Desktop session** on → command as above
(`shell ... -c weston-flower`, not `nix run ... -- weston-flower`). Smoke helper:
`scripts/agent-device-container-smoke-macos.sh`.

## Android / Linux VM automation

```bash
nix run .#wawona-android        # Android build + adb install/launch smoke
nix run .#wawona-linux-vm     # NixOS Plasma 6 Wayland VM for Linux UI testing
```
