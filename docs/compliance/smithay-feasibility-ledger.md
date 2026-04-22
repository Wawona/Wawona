# Smithay Feasibility Ledger

This ledger records why protocols are currently classified as `smithay` vs `no-equivalent` in `wayland-protocol-manifest.toml`.

## Method

- `smithay` means runtime ownership is currently treated as Smithay-backed in strict ownership checks.
- `no-equivalent` means one of:
  - no practical Smithay 0.7 delegate/state path in Wawona's current architecture, or
  - feature-gated desktop path not active for all profiles and still implemented via custom runtime dispatch.

## Current Smithay Runtime Set

- `wl_compositor`
- `wl_subcompositor`
- `wl_shm`
- `wl_output`
- `wl_seat`
- `wl_data_device_manager`
- `xdg_wm_base`
- `zxdg_output_manager_v1`

### Core Runtime Blockers

The strict verifier reports dual-registration evidence for:

- `wl_compositor`
- `xdg_wm_base`

These remain in `smithay_runtime_core` and require a dedicated runtime cutover to eliminate residual custom dispatch files.

## Reclassified Pending Runtime Ownership Migration

These entries map to known Smithay modules/APIs but are still registered via custom runtime dispatch in Wawona and therefore remain `no-equivalent` until that wiring is replaced:

- XDG family:
  - `zxdg_toplevel_decoration_v1`
  - `xdg_wm_dialog_v1`
  - `xdg_activation_v1`
  - `zxdg_exporter_v2`
  - `zxdg_importer_v2`
  - `xdg_system_bell_v1`
  - `xdg_toplevel_icon_v1`
  - `xdg_toplevel_tag_manager_v1`
- ext/wlr family:
  - `ext_foreign_toplevel_list_v1`
  - `ext_data_control_manager_v1`
  - `wp_cursor_shape_manager_v1`
  - `zwp_pointer_constraints_v1`
  - `zwp_pointer_gestures_v1`
  - `zwp_relative_pointer_manager_v1`
  - `zwp_tablet_manager_v2`
  - `zwp_text_input_manager_v3`
  - `zwp_input_method_manager_v2`
  - `zwp_primary_selection_device_manager_v1`
  - `zwp_linux_dmabuf_v1`
  - `wp_presentation`
  - `wp_commit_timing_manager_v1`
  - `wp_fifo_manager_v1`
  - `wp_fractional_scale_manager_v1`
  - `wp_viewporter`
  - `wp_single_pixel_buffer_manager_v1`
  - `wp_alpha_modifier_v1`
  - `wp_content_type_manager_v1`
  - `zwp_idle_inhibit_manager_v1`
  - `zwp_keyboard_shortcuts_inhibit_manager_v1`
  - `ext_idle_notifier_v1`
  - `wp_security_context_manager_v1`
  - `ext_session_lock_manager_v1`
  - `zwlr_layer_shell_v1`
  - `zwlr_data_control_manager_v1`
  - `zwp_virtual_keyboard_manager_v1`
  - `xwayland_shell_v1`
  - `zwp_xwayland_keyboard_grab_manager_v1`

## True No-Path Keepers

Examples currently treated as no practical Smithay runtime owner in this repo:

- `ext_background_effect_manager_v1`
- `wl_fixes`
- `wp_drm_lease_device_v1`
- `wp_linux_drm_syncobj_manager_v1`
- `zwlr_screencopy_manager_v1`
- `zwlr_export_dmabuf_manager_v1`
- `zwlr_virtual_pointer_manager_v1`

## Verification Source of Truth

- `./.github/scripts/verify-wayland-runtime-ownership.py --strict`
- `./docs/compliance/generated/wayland-runtime-ownership.json`
- `./.github/scripts/verify-wayland-no-equivalent-closure.py --json-out ./docs/compliance/generated/wayland-no-equivalent-closure.json`
- `./docs/compliance/generated/wayland-no-equivalent-closure.json`

## All-55 Closure Rule

Every interface currently classified as `equivalent = "no-equivalent"` must resolve to one of:

- `true-no-path`: no practical Smithay runtime owner in current Wawona release, or protocol is explicitly ecosystem-specific (`KDE`, `Wawona-specific`, `legacy`).
- `architecture-blocked`: Smithay-shaped target exists conceptually, but current runtime ownership is still custom and must remain profile-gated until cutover lands.

The closure verifier enforces that all 55 no-equivalent interfaces have one of these dispositions and exports a machine-readable artifact for CI.
