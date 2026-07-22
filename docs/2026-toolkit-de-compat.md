# Wawona — Toolkit & Desktop-Environment Compatibility

What GTK, Qt, and KDE/GNOME/wlroots-DE clients need from Wawona, and where we
stand. Protocol presence is authoritative in
[`protocol-status.md`](./protocol-status.md); this doc maps client requirements
to those globals.

## Key semantics clients depend on

| Requirement | Protocol(s) | Wawona status |
|-------------|-------------|---------------|
| Server/client-side decorations negotiation | `zxdg_decoration_manager_v1` | advertised; SSD/CSD policy incl. force-SSD |
| Primary selection (middle-click paste) | `zwp_primary_selection_device_manager_v1` | advertised |
| Panels / bars / lock screens | `zwlr_layer_shell_v1` | desktop/dev profiles only (honest) |
| Fractional HiDPI | `wp_fractional_scale_manager_v1` + `wp_viewporter` | advertised |
| Cursor theming | `wp_cursor_shape_manager_v1` | advertised |
| Clipboard / DnD | `wl_data_device_manager` | v3 |
| Session lock | `ext_session_lock_manager_v1` | advertised |
| Text input / IME | `zwp_text_input_manager_v3`, `zwp_input_method_manager_v2` | advertised |
| Idle / inhibit | `ext_idle_notifier_v1`, `zwp_idle_inhibit_manager_v1` | advertised |

## Client matrix (target behavior)

| Client family | Runs via | Notes |
|---------------|----------|-------|
| GTK4 / libadwaita apps (nautilus, gnome-text-editor) | native / waypipe | needs decoration + fractional-scale; CSD default |
| Qt / KDE apps (konsole, dolphin, kate) | native / waypipe | needs primary-selection + decoration; set `QT_QPA_PLATFORM=wayland` |
| Toolkit demos (weston-*, foot) | native / bundled | SHM + xdg-shell only; baseline smoke |
| SDL2 / SDL2_gfx (`testgfx`) | native / bundled | `SDL_VIDEODRIVER=wayland`; software/`wl_shm` first (tvOS/watchOS-safe); port plan [#107](https://github.com/Wawona/Wawona/issues/107) |
| wlroots DEs (sway, niri, hyprland) | **nested** | run as their own compositor; layer-shell client of Wawona |
| GNOME Shell / KDE Plasma | nested / VM | heavy; prefer nested Weston or NixOS VM delivery |

## Running Qt/GTK apps — env contract

- GTK: `GDK_BACKEND=wayland`.
- Qt: `QT_QPA_PLATFORM=wayland` (fallback `xcb` only via XWayland path).
- SDL: `SDL_VIDEODRIVER=wayland`.
- Cursor: ship an XCursor theme or rely on `wp_cursor_shape_manager_v1`.

These are injected by the client launch path (`WWNWaypipeRunner` /
bundled-client env) so users don't set them manually.

## Gaps to verify (tracked by p24)

- xdg-decoration reconfigure stability under KDE force-SSD (conformance matrix
  row exists; needs Layer-3 capture).
- layer-shell exclusive-zone + anchor correctness for panels (desktop profile).
- primary-selection interop with the universal-clipboard bridge.

Nested-DE delivery rationale: [`2026-wlroots-compat.md`](./2026-wlroots-compat.md).
