# Smithay Documentation Ingest Index

This document is the local source-of-truth for Smithay protocol coverage mapping used by Wawona migration work.

## Sources Snapshotted

- Smithay docs hub: <https://smithay.github.io/pages/documentation.html>
- Released API docs: <https://docs.rs/smithay/latest/smithay/wayland/index.html>
- Master API docs: <https://smithay.github.io/smithay/smithay/wayland/index.html>
- Smithay source module map: `inspirational_projects/smithay/src/wayland/mod.rs`

## Smithay Wayland Module Surface (0.7)

The current Smithay Wayland helper modules include:

- `compositor`, `shm`, `seat`, `output`
- `shell` (including `shell::xdg`, `shell::wlr_layer`)
- `selection`
- `dmabuf`
- `presentation`
- `fractional_scale`, `viewporter`, `single_pixel_buffer`, `alpha_modifier`, `content_type`
- `commit_timing`, `fifo`
- `idle_inhibit`, `idle_notify`, `keyboard_shortcuts_inhibit`
- `security_context`, `session_lock`
- `image_capture_source`, `image_copy_capture`
- `foreign_toplevel_list`
- `cursor_shape`, `pointer_constraints`, `pointer_gestures`, `relative_pointer`, `pointer_warp`
- `tablet_manager`, `text_input`, `input_method`, `virtual_keyboard`
- `xdg_activation`, `xdg_foreign`, `xdg_system_bell`, `xdg_toplevel_icon`, `xdg_toplevel_tag`
- `fixes`
- Linux-gated: `drm_lease`, `drm_syncobj`
- Xwayland-gated: `xwayland_keyboard_grab`, `xwayland_shell`

## Interface -> Smithay Mapping Baseline

This is the actionable mapping used to drive migration and manifest contract checks.

- `wl_compositor`/`wl_surface`/`wl_region` -> `smithay::wayland::compositor`
- `wl_subcompositor` -> `smithay::wayland::compositor` (subsurface helpers)
- `wl_shm` -> `smithay::wayland::shm`
- `wl_output` + `zxdg_output_manager_v1` -> `smithay::wayland::output`
- `wl_seat` + pointer/keyboard/touch objects -> `smithay::wayland::seat`
- `wl_data_device_manager` -> `smithay::wayland::selection::data_device`
- `wl_fixes` -> `smithay::wayland::fixes`
- `xdg_wm_base` family -> `smithay::wayland::shell::xdg`
- `zxdg_toplevel_decoration_v1` -> `smithay::wayland::shell::xdg::decoration`
- `zwlr_layer_shell_v1` -> `smithay::wayland::shell::wlr_layer`
- `xdg_activation_v1` -> `smithay::wayland::xdg_activation`
- `zxdg_exporter_v2`/`zxdg_importer_v2` -> `smithay::wayland::xdg_foreign`
- `xdg_system_bell_v1` -> `smithay::wayland::xdg_system_bell`
- `xdg_toplevel_icon_v1` -> `smithay::wayland::xdg_toplevel_icon`
- `xdg_toplevel_tag_manager_v1` -> `smithay::wayland::xdg_toplevel_tag`
- `ext_foreign_toplevel_list_v1` -> `smithay::wayland::foreign_toplevel_list`
- `wp_cursor_shape_manager_v1` -> `smithay::wayland::cursor_shape`
- `zwp_pointer_constraints_v1` -> `smithay::wayland::pointer_constraints`
- `zwp_pointer_gestures_v1` -> `smithay::wayland::pointer_gestures`
- `zwp_relative_pointer_manager_v1` -> `smithay::wayland::relative_pointer`
- `wp_pointer_warp_v1` -> `smithay::wayland::pointer_warp`
- `zwp_tablet_manager_v2` -> `smithay::wayland::tablet_manager`
- `zwp_text_input_manager_v3` -> `smithay::wayland::text_input`
- `zwp_input_method_manager_v2` -> `smithay::wayland::input_method`
- `zwp_virtual_keyboard_manager_v1` -> `smithay::wayland::virtual_keyboard`
- `zwp_primary_selection_device_manager_v1` -> `smithay::wayland::selection::primary_selection`
- `ext_data_control_manager_v1` -> `smithay::wayland::selection::ext_data_control`
- `zwlr_data_control_manager_v1` -> `smithay::wayland::selection::wlr_data_control`
- `zwp_linux_dmabuf_v1` -> `smithay::wayland::dmabuf`
- `wp_linux_drm_syncobj_manager_v1` -> `smithay::wayland::drm_syncobj` (Linux-only)
- `wp_drm_lease_device_v1` -> `smithay::wayland::drm_lease` (Linux-only)
- `wp_presentation` -> `smithay::wayland::presentation`
- `wp_commit_timing_manager_v1` -> `smithay::wayland::commit_timing`
- `wp_fifo_manager_v1` -> `smithay::wayland::fifo`
- `wp_fractional_scale_manager_v1` -> `smithay::wayland::fractional_scale`
- `wp_viewporter` -> `smithay::wayland::viewporter`
- `wp_single_pixel_buffer_manager_v1` -> `smithay::wayland::single_pixel_buffer`
- `wp_alpha_modifier_v1` -> `smithay::wayland::alpha_modifier`
- `wp_content_type_manager_v1` -> `smithay::wayland::content_type`
- `ext_background_effect_manager_v1` -> `smithay::wayland::background_effect`
- `zwp_idle_inhibit_manager_v1` -> `smithay::wayland::idle_inhibit`
- `zwp_keyboard_shortcuts_inhibit_manager_v1` -> `smithay::wayland::keyboard_shortcuts_inhibit`
- `ext_idle_notifier_v1` -> `smithay::wayland::idle_notify`
- `wp_security_context_manager_v1` -> `smithay::wayland::security_context`
- `ext_session_lock_manager_v1` -> `smithay::wayland::session_lock`
- `ext_output_image_capture_source_manager_v1` -> `smithay::wayland::image_capture_source`
- `ext_image_copy_capture_manager_v1` -> `smithay::wayland::image_copy_capture`
- `zwp_xwayland_keyboard_grab_manager_v1` -> `smithay::wayland::xwayland_keyboard_grab` (xwayland-gated)
- `xwayland_shell_v1` -> `smithay::wayland::xwayland_shell` (xwayland-gated)
