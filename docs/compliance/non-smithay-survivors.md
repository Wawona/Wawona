# Non-Smithay Protocol Survivors

This document lists protocol surfaces currently retained outside Smithay-backed paths. A survivor is allowed only when `equivalent = "no-equivalent"` and explicitly gated by profile policy.

Smithay-equivalent protocols are enforced by `verify-wayland-runtime-ownership.py --strict` and must not be added to this survivor list.

## Survivors (No Equivalent)

### Verified no-equivalent keepers

These interfaces remain custom-owned in the current runtime and are intentionally classified `no-equivalent` for strict ownership accounting. Their feasibility and rationale are tracked in `docs/compliance/smithay-feasibility-ledger.md`.

- `zxdg_toplevel_decoration_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xdg_wm_dialog_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xdg_activation_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zxdg_exporter_v2`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zxdg_importer_v2`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xdg_system_bell_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xdg_toplevel_icon_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xdg_toplevel_tag_manager_v1`
  - Module: `src/core/wayland/xdg/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwlr_layer_shell_v1`
  - Module: `src/core/wayland/wlr/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwlr_data_control_manager_v1`
  - Module: `src/core/wayland/wlr/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_virtual_keyboard_manager_v1`
  - Module: `src/core/wayland/wlr/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_foreign_toplevel_list_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_data_control_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_cursor_shape_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_pointer_constraints_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_pointer_gestures_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_relative_pointer_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_tablet_manager_v2`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_text_input_manager_v3`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_input_method_manager_v2`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_primary_selection_device_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_linux_dmabuf_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_presentation`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_commit_timing_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_fifo_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_fractional_scale_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_viewporter`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_single_pixel_buffer_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_alpha_modifier_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_content_type_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_idle_inhibit_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_keyboard_shortcuts_inhibit_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_idle_notifier_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_security_context_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_session_lock_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `xwayland_shell_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_xwayland_keyboard_grab_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_server_decoration_manager`
  - Module: `src/core/wayland/plasma/kde_decoration.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_blur_manager`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_contrast_manager`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_shadow_manager`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_dpms_manager`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_idle_timeout`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `org_kde_kwin_slide_manager`
  - Module: `src/core/wayland/plasma/plasma.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwp_fullscreen_shell_v1` (legacy path)
  - Module: `src/core/wayland/ext/fullscreen_shell.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: runtime opt-in + profile checks

- `wp_pointer_warp_v1`
  - Module: `src/core/wayland/ext/pointer_warp.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_output_image_capture_source_manager_v1`
  - Module: `src/core/wayland/ext/image_capture_source.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_image_copy_capture_manager_v1`
  - Module: `src/core/wayland/ext/image_copy_capture.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `ext_background_effect_manager_v1`
  - Module: `src/core/wayland/ext/background_effect.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wl_fixes`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_drm_lease_device_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `wp_linux_drm_syncobj_manager_v1`
  - Module: `src/core/wayland/ext/mod.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwlr_screencopy_manager_v1`
  - Module: `src/core/wayland/wlr/screencopy.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwlr_export_dmabuf_manager_v1`
  - Module: `src/core/wayland/wlr/export_dmabuf.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

- `zwlr_virtual_pointer_manager_v1`
  - Module: `src/core/wayland/wlr/virtual_pointer.rs`
  - Equivalent status: `no-equivalent`
  - Exposure: `desktop-host`, `full-dev`

## Optional Ecosystem Surface (Not Baseline Smithay Contract)

- `wayland-protocols-hyprland`
- `wayland-wf-shell`

These remain optional extension dependencies and are not part of baseline Smithay coverage enforcement.

## Enforcement Rules

1. Any non-Smithay protocol must carry `equivalent = "no-equivalent"` in the manifest.
2. All survivors stay behind explicit runtime/profile checks.
3. No survivor is enabled in `store-safe` unless policy traceability explicitly allows it.
