# Wawona. X11 Strategy

Authority for scope: [`2026-SOURCE-OF-TRUTH.md`](./2026-SOURCE-OF-TRUTH.md).

## Principle: no local X server

Wawona never ships or runs an X server (`Xorg`/`XQuartz`) on any platform. A
local X server is incompatible with App Store sandboxing (raw device access,
`setuid`, arbitrary module loading) and duplicates work Wayland already does.
X11 clients are served through XWayland, hosted out-of-process.

## Delivery paths for X11 clients

### 1. Remote XWayland over waypipe (primary, store-safe)
`waypipe --xwls` starts XWayland on the **remote** host inside the waypipe
server. The X11 client talks to remote XWayland; waypipe proxies the resulting
Wayland surfaces back to Wawona. Everything X11-specific stays on the remote
Linux box; the Apple/Android client only ever speaks Wayland.

- Enabled by the `waypipeXwls` preference (`WWNWaypipeRunner` appends `--xwls`).
- Works on every platform that supports waypipe (watchOS included: native compositor plus remote).
- Fully App Store compliant. No local X server, no JIT.

### 2. Nested-Weston XWayland (non-store macOS only)
On developer/desktop macOS builds, the bundled nested Weston can launch its own
Xwayland. X11 clients connect to the nested compositor's `DISPLAY`; the nested
Weston presents as a single surface into Wawona. Not used on store builds.

## Protocol support

The compositor advertises the pieces XWayland needs to attach:

- `xwayland_shell_v1`. XWayland surface association.
- `zwp_xwayland_keyboard_grab_manager_v1`. X11 keyboard grabs.

(Both appear in [`protocol-status.md`](./protocol-status.md).) Wawona itself is
the Wayland side; it does not implement the X11 wire protocol. XWayland does.

## Non-goals

- No iOS "X11 server" via jailbreak/procursus packages (violates store policy).
- No local `DISPLAY` socket on Apple platforms.
