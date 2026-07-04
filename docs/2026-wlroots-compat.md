# Wawona — wlroots Compatibility

Why Wawona is built on Smithay with native frontends rather than porting
wlroots, and which wlroots semantics it deliberately mirrors.

## Why not wlroots directly

- **wlroots is GBM/DRM/libinput-first.** Its backends assume Linux KMS, GBM, and
  evdev. Apple platforms have none of these; Android exposes them only through
  restricted NDK surfaces. Porting wlroots means reimplementing every backend
  anyway — the hard part — while inheriting a C API and build system that fights
  App Store sandboxing.
- **Smithay is a library, not a compositor.** It gives us the protocol state
  machines (`wayland_frontend`) without imposing a backend, so we plug in native
  present paths (CAMetalLayer, ANativeWindow, GTK) per platform. See
  [`compliance/smithay-adoption-architecture-matrix.md`](./compliance/smithay-adoption-architecture-matrix.md).
- **Memory safety + FFI.** Rust core with a thin C ABI (`src/ffi`) is easier to
  audit and to expose to Swift/Kotlin than wlroots' C internals.

## wlroots semantics we mirror

Even without wlroots code, clients expect wlroots-family protocol behavior. We
implement the wlroots protocol set natively (`src/core/wayland/wlr/`):

| Family | Protocol(s) | Status |
|--------|-------------|--------|
| Layer shell | `zwlr_layer_shell_v1` | desktop/dev profiles only (advertisement-honest) |
| Screencopy | `zwlr_screencopy_manager_v1` | platform readback (macOS `CGWindowListCreateImage`) |
| Export dmabuf | `zwlr_export_dmabuf_manager_v1` | privileged-profile gated |
| Gamma control | `zwlr_gamma_control_manager_v1` | macOS `CGSetDisplayTransferByTable` |
| Output mgmt/power | `zwlr_output_manager_v1`, `zwlr_output_power_manager_v1` | native |
| Foreign toplevel | `zwlr_foreign_toplevel_manager_v1` | v3 |
| Virtual input | `zwlr_virtual_pointer_manager_v1`, `zwp_virtual_keyboard_manager_v1` | privileged-profile gated |
| Data control | `zwlr_data_control_manager_v1` | native |

Privileged wlr globals are only advertised when the active `ProtocolProfile`
allows them (`policy::allow_privileged_wlr`), enforced by
`src/tests/protocol_matrix.rs`.

## Practical compatibility target

`sway`, `niri`, and `hyprland` are wlroots/`smithay` compositors we intend to
run **nested** (as clients) rather than replace. Their protocol needs are
tracked in [`2026-toolkit-de-compat.md`](./2026-toolkit-de-compat.md); native
ports are scaffolded under the `wwn-*` convention
([`2026-wwn-porting-convention.md`](./2026-wwn-porting-convention.md)).
