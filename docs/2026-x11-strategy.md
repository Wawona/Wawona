# Wawona. X11 Strategy

Authority for scope: [`2026-SOURCE-OF-TRUTH.md`](./2026-SOURCE-OF-TRUTH.md).

## Principle: no full Xorg / XQuartz

Wawona never ships or runs a full X server (`Xorg` / `XQuartz`) on any
platform. A full local X server is incompatible with App Store sandboxing
(raw device access, `setuid`, arbitrary module loading) and duplicates work
Wayland already does. Wawona stays a **Wayland compositor**.

## In-compositor X11 (product path)

**Implementation: `xwayland-satellite` only.**

Satellite attaches X11 clients onto Wawona’s Wayland seat. It is the
in-compositor X11 path. Not full Xorg. Not XQuartz. Not embedding an X
server into the Wawona process as a second display server.

Advertise so satellite / XWayland can attach:

- `xwayland_shell_v1`. Surface association.
- `zwp_xwayland_keyboard_grab_manager_v1`. X11 keyboard grabs.

(Both appear in [`protocol-status.md`](./protocol-status.md).) Wawona is the
Wayland side; it does not implement the X11 wire protocol.

## Peer-side remote X (store-safe convenience)

`waypipe --xwls` starts XWayland on the **remote** Linux host inside the
waypipe server. The X11 client talks to remote XWayland; waypipe proxies
Wayland surfaces back to Wawona. Apple/Android clients only speak Wayland.

- Preference: `waypipeXwls` (`WWNWaypipeRunner` appends `--xwls`).
- Fully App Store compliant. No local X server on the device.
- This is **peer-side only**. It is not the in-compositor X11
  implementation (that remains `xwayland-satellite`).

## Nested-Weston XWayland (non-store macOS only)

On developer/desktop macOS builds, nested Weston may launch its own
Xwayland. Prefer migrating that path to **xwayland-satellite** against
Wawona. Not used on store builds.

## Non-goals

- No full Xorg / XQuartz as Wawona’s X11 server.
- No iOS "X11 server" via jailbreak/procursus packages (violates store policy).
- No treating remote `waypipe --xwls` as the in-compositor X11 implementation.
