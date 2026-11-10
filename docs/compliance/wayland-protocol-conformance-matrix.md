# Wawona Wayland Protocol Conformance Matrix

This matrix defines required behavior for Smithay-first runtime parity and is used as the release gate for compositor correctness.

## Core Protocols

| Interface | Required behaviors | Validation |
| --- | --- | --- |
| `wl_compositor` | Create/destroy surfaces and regions without client-scoped ID collisions. | Spawn multiple clients creating/destroying surfaces concurrently. |
| `wl_surface` | Attach/commit ordering, role enforcement, damage, frame callbacks. | Weston + GTK clients with resize and subsurface trees. |
| `wl_buffer` | Release exactly once per lifetime; safe when resource dies before release. | SHM stress loop and shutdown while resizing. |
| `wl_shm` | Pool create/resize and format handling (`ARGB8888`, `XRGB8888`). | Weston simple-shm and wlroots software paths. |
| `wl_seat` | Pointer/keyboard/touch capabilities and focus transitions. | Key focus switches between two active windows. |
| `wl_output` | Mode/scale/geometry correctness and per-client overrides where intended. | Nested Weston and host live-resize. |

## XDG Shell

| Interface | Required behaviors | Validation |
| --- | --- | --- |
| `xdg_wm_base` | Ping/pong liveness and serial handling. | Long-running session, no unsolicited disconnects. |
| `xdg_surface` | Configure/ack/commit contract under resize pressure. | Drag-resize host window rapidly for 30s. |
| `xdg_toplevel` | State transitions (activated, maximize/fullscreen) and close semantics. | Focus toggle, close from host, close from client. |
| `xdg_popup` | Parent-child mapping and geometry updates. | App with menus/context popups. |
| `zxdg_toplevel_decoration_v1` | SSD/CSD policy correctness and stable reconfigure path. | KDE + wlroots clients under force SSD policy. |

## WLR / Extension Coverage

| Family | Required behaviors | Validation |
| --- | --- | --- |
| Screencopy/export | Capture requests complete/fail deterministically. | `grim` / screencopy smoke while resizing. |
| Data control | Clipboard read/write survives focus changes. | `wl-copy`/`wl-paste` across two clients. |
| Pointer constraints/gestures | Protocol bind and no runtime panics. | Bind smoke + pointer lock client. |
| Relative pointer/cursor shape | Cursor updates and relative motion events coherent. | FPS-like pointer test app. |
| Text input / IME | Enter/leave and commit flows tied to focused surface. | Weston terminal + IME composition. |

## Transport Separation Rule

Remote transport failures (e.g. waypipe clock/Xwayland issues) must be classified separately from compositor protocol failures. A release can only fail compositor conformance when the same test fails in local direct client mode.

