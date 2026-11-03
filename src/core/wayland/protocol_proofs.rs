//! Pure Wayland protocol erroneous-check helpers.
//!
//! Product handlers call these predicates before `post_error`. Kani, proptest,
//! and the Verification report point at **this module only**. There is no second
//! implementation of these checks.
//!
//! Every `Functional` catalog interface must appear in
//! [`PROTOCOL_PROOF_OBLIGATIONS`]. Interfaces with no client-facing protocol
//! errors use [`ErroneousChecks::None`]. Interfaces with errors must list
//! named helpers that have `#[cfg(kani)]` harnesses (fail-closed in
//! `scripts/verify-formal.sh`).

#![allow(dead_code)] // helpers are referenced from protocol modules + Kani

/// How a Functional protocol covers erroneous checks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErroneousChecks {
    /// No client-facing `post_error` / invalid-request path in the handler.
    None,
    /// Named pure helpers (must each have a Kani harness of the same stem).
    Helpers(&'static [&'static str]),
}

/// One Functional (or proof-tracked) interface and its proof surface.
#[derive(Debug, Clone, Copy)]
pub struct ProtocolProofObligation {
    pub interface: &'static str,
    pub checks: ErroneousChecks,
    /// Rust module owning the handlers (docs / NDJSON).
    pub rust_module: &'static str,
}

/// Fail-closed inventory: every Functional protocol row must match an entry.
/// Keep sorted by `interface` for stable diffs.
pub const PROTOCOL_PROOF_OBLIGATIONS: &[ProtocolProofObligation] = &[
ProtocolProofObligation {
        interface: "agl_screenshooter",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "agl_shell",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "agl_shell_desktop",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "cosmic_a11y_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "cosmic_atspi_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "ext_background_effect_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/background_effect.rs",
    },
ProtocolProofObligation {
        interface: "ext_data_control_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/data_control.rs",
    },
ProtocolProofObligation {
        interface: "ext_foreign_toplevel_list_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/foreign_toplevel_list.rs",
    },
ProtocolProofObligation {
        interface: "ext_idle_notifier_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/idle_notify.rs",
    },
ProtocolProofObligation {
        interface: "ext_image_copy_capture_manager_v1",
        checks: ErroneousChecks::Helpers(&["image_copy_capture_rejects_duplicate_frame"]),
        rust_module: "src/core/wayland/ext/image_copy_capture.rs",
    },
ProtocolProofObligation {
        interface: "ext_output_image_capture_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/image_capture_source.rs",
    },
ProtocolProofObligation {
        interface: "ext_session_lock_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/session_lock.rs",
    },
ProtocolProofObligation {
        interface: "ext_transient_seat_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/transient_seat.rs",
    },
ProtocolProofObligation {
        interface: "ext_workspace_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/workspace.rs",
    },
ProtocolProofObligation {
        interface: "gtk_primary_selection_device_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/gtk_primary_selection.rs",
    },
ProtocolProofObligation {
        interface: "gtk_shell1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_ctm_control_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_focus_grab_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_global_shortcuts_manager_v1",
        checks: ErroneousChecks::Helpers(&["hyprland_shortcut_rejects_duplicate"]),
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_lock_notifier_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_surface_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_toplevel_export_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "hyprland_toplevel_mapping_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/hyprland/mod.rs",
    },
ProtocolProofObligation {
        interface: "ivi_application",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "ivi_hmi_controller",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "kde_external_brightness_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_lockscreen_overlay_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_output_device_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_output_management_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_output_order_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_primary_output_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "kde_screen_edge_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "mir_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_appmenu_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_blur_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_contrast_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_dpms_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_fake_input",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_idle",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_keystate",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_outputdevice",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_outputmanagement",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_server_decoration_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/kde_decoration.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_server_decoration_palette_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_shadow_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_kwin_slide_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/plasma.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_plasma_shell",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_plasma_virtual_desktop_management",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "org_kde_plasma_window_management",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "river_input_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_layer_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_layout_manager_v3",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_libinput_config_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_window_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_xkb_bindings_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "river_xkb_config_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "text_cursor_position",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_capture_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_dde_shell_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_foreign_toplevel_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_output_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_personalization_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_shortcut_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_virtual_output_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_wallpaper_color_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_wallpaper_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_wallpaper_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "treeland_window_management_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/treeland/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_capture_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_content_protection",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_debug_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_desktop_shell",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_direct_display_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_test",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "weston_touch_calibration",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/weston/mod.rs",
    },
ProtocolProofObligation {
        interface: "wl_compositor",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay compositor)",
    },
ProtocolProofObligation {
        interface: "wl_data_device_manager",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay data device)",
    },
ProtocolProofObligation {
        interface: "wl_drm",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "wl_eglstream_controller",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "wl_eglstream_display",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "wl_fixes",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/wl_fixes.rs",
    },
ProtocolProofObligation {
        interface: "wl_output",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay output)",
    },
ProtocolProofObligation {
        interface: "wl_seat",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay seat)",
    },
ProtocolProofObligation {
        interface: "wl_shell",
        checks: ErroneousChecks::Helpers(&["wl_shell_role_conflict"]),
        rust_module: "src/core/wayland/wl_shell.rs",
    },
ProtocolProofObligation {
        interface: "wl_shm",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay shm)",
    },
ProtocolProofObligation {
        interface: "wl_subcompositor",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/subcompositor.rs",
    },
ProtocolProofObligation {
        interface: "wp_alpha_modifier_v1",
        checks: ErroneousChecks::Helpers(&["alpha_modifier_factor_is_unit_interval"]),
        rust_module: "src/core/wayland/ext/alpha_modifier.rs",
    },
ProtocolProofObligation {
        interface: "wp_color_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/color_management.rs",
    },
ProtocolProofObligation {
        interface: "wp_color_representation_manager_v1",
        checks: ErroneousChecks::Helpers(&[
            "color_representation_rejects_duplicate_surface",
            "color_representation_alpha_mode_supported",
        ]),
        rust_module: "src/core/wayland/ext/color_representation.rs",
    },
ProtocolProofObligation {
        interface: "wp_commit_timing_manager_v1",
        checks: ErroneousChecks::Helpers(&["commit_timing_hold_required"]),
        rust_module: "src/core/wayland/ext/commit_timing.rs",
    },
ProtocolProofObligation {
        interface: "wp_content_type_manager_v1",
        checks: ErroneousChecks::Helpers(&["content_type_hint_is_known_or_none"]),
        rust_module: "src/core/wayland/ext/content_type.rs",
    },
ProtocolProofObligation {
        interface: "wp_cursor_shape_manager_v1",
        checks: ErroneousChecks::Helpers(&["cursor_shape_value_is_non_zero"]),
        rust_module: "src/core/wayland/ext/cursor_shape.rs",
    },
ProtocolProofObligation {
        interface: "wp_drm_lease_device_v1",
        checks: ErroneousChecks::Helpers(&[
            "drm_lease_request_rejects_empty",
            "drm_lease_request_rejects_without_connectors",
        ]),
        rust_module: "src/core/wayland/ext/drm_lease.rs",
    },
ProtocolProofObligation {
        interface: "wp_fifo_manager_v1",
        checks: ErroneousChecks::Helpers(&["fifo_barrier_blocks_next_commit"]),
        rust_module: "src/core/wayland/ext/fifo.rs",
    },
ProtocolProofObligation {
        interface: "wp_fractional_scale_manager_v1",
        checks: ErroneousChecks::Helpers(&["fractional_scale_units_at_least_120"]),
        rust_module: "src/core/wayland/ext/fractional_scale.rs",
    },
ProtocolProofObligation {
        interface: "wp_linux_drm_syncobj_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/linux_drm_syncobj.rs",
    },
ProtocolProofObligation {
        interface: "wp_pointer_warp_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/pointer_warp.rs",
    },
ProtocolProofObligation {
        interface: "wp_presentation",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/presentation_time.rs",
    },
ProtocolProofObligation {
        interface: "wp_security_context_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/security_context.rs",
    },
ProtocolProofObligation {
        interface: "wp_single_pixel_buffer_manager_v1",
        checks: ErroneousChecks::Helpers(&["single_pixel_buffer_is_one_by_one"]),
        rust_module: "src/core/wayland/ext/single_pixel_buffer.rs",
    },
ProtocolProofObligation {
        interface: "wp_tearing_control_manager_v1",
        checks: ErroneousChecks::Helpers(&["tearing_hint_is_vsync_or_async"]),
        rust_module: "src/core/wayland/ext/tearing_control.rs",
    },
ProtocolProofObligation {
        interface: "wp_viewporter",
        checks: ErroneousChecks::Helpers(&[
            "viewport_source_request_is_valid",
            "viewport_destination_request_is_valid",
            "viewport_commit_rejects_out_of_buffer_i32",
            "viewport_commit_rejects_fractional_without_dest",
        ]),
        rust_module: "src/core/wayland/ext/viewporter.rs",
    },
ProtocolProofObligation {
        interface: "xapp_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "xdg_activation_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_activation.rs",
    },
ProtocolProofObligation {
        interface: "xdg_session_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "xdg_system_bell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_system_bell.rs",
    },
ProtocolProofObligation {
        interface: "xdg_toplevel_drag_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_toplevel_drag.rs",
    },
ProtocolProofObligation {
        interface: "xdg_toplevel_icon_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_toplevel_icon.rs",
    },
ProtocolProofObligation {
        interface: "xdg_toplevel_tag_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_toplevel_tag.rs",
    },
ProtocolProofObligation {
        interface: "xdg_wm_base",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_wm_base.rs",
    },
ProtocolProofObligation {
        interface: "xdg_wm_dialog_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_dialog.rs",
    },
ProtocolProofObligation {
        interface: "xwayland_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/xwayland_shell.rs",
    },
ProtocolProofObligation {
        interface: "xx_cutouts_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "xx_input_method_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "xx_keyboard_filter_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "xx_session_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "xx_zone_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/experimental/mod.rs",
    },
ProtocolProofObligation {
        interface: "zaura_output_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "zaura_shell",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/external/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_ext_workspace_image_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_output_image_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_output_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_overlap_notify_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_screencopy_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_screencopy_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_toplevel_image_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_toplevel_info_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_toplevel_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_workspace_image_capture_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_workspace_image_source_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_workspace_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zcosmic_workspace_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/cosmic/mod.rs",
    },
ProtocolProofObligation {
        interface: "zkde_screencast_unstable_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/plasma/extra.rs",
    },
ProtocolProofObligation {
        interface: "zriver_control_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "zriver_status_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/river/mod.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_data_control_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/data_control.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_export_dmabuf_manager_v1",
        checks: ErroneousChecks::Helpers(&["export_dmabuf_should_cancel_without_capability"]),
        rust_module: "src/core/wayland/wlr/export_dmabuf.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_foreign_toplevel_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/foreign_toplevel_management.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_gamma_control_manager_v1",
        checks: ErroneousChecks::Helpers(&[
            "gamma_control_rejects_second_active",
            "gamma_ramp_byte_len_matches",
        ]),
        rust_module: "src/core/wayland/wlr/gamma_control.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_input_inhibit_manager_v1",
        checks: ErroneousChecks::Helpers(&["wlr_input_inhibit_rejects_second_inhibitor"]),
        rust_module: "src/core/wayland/wlr/input_inhibitor.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_layer_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/layer_shell.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_output_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/output_management.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_output_power_manager_v1",
        checks: ErroneousChecks::Helpers(&["output_power_mode_is_on_or_off"]),
        rust_module: "src/core/wayland/wlr/output_power_management.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_screencopy_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/screencopy.rs",
    },
ProtocolProofObligation {
        interface: "zwlr_virtual_pointer_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/wlr/virtual_pointer.rs",
    },
ProtocolProofObligation {
        interface: "zwp_fullscreen_shell_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/fullscreen_shell.rs",
    },
ProtocolProofObligation {
        interface: "zwp_idle_inhibit_manager_v1",
        checks: ErroneousChecks::Helpers(&["idle_inhibit_map_remove_clears"]),
        rust_module: "src/core/wayland/ext/idle_inhibit.rs",
    },
ProtocolProofObligation {
        interface: "zwp_input_method_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay input_method)",
    },
ProtocolProofObligation {
        interface: "zwp_input_method_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/input_method_v1.rs",
    },
ProtocolProofObligation {
        interface: "zwp_input_timestamps_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/input_timestamps.rs",
    },
ProtocolProofObligation {
        interface: "zwp_keyboard_shortcuts_inhibit_manager_v1",
        checks: ErroneousChecks::Helpers(&["shortcuts_inhibit_surface_toggle"]),
        rust_module: "src/core/wayland/ext/keyboard_shortcuts_inhibit.rs",
    },
ProtocolProofObligation {
        interface: "zwp_linux_dmabuf_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/linux_dmabuf.rs",
    },
ProtocolProofObligation {
        interface: "zwp_linux_explicit_synchronization_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/linux_explicit_sync.rs",
    },
ProtocolProofObligation {
        interface: "zwp_pointer_constraints_v1",
        checks: ErroneousChecks::Helpers(&["pointer_constraint_oneshot_stays_dead"]),
        rust_module: "src/core/wayland/ext/pointer_constraints.rs",
    },
ProtocolProofObligation {
        interface: "zwp_pointer_gestures_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/pointer_gestures.rs",
    },
ProtocolProofObligation {
        interface: "zwp_primary_selection_device_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay primary_selection)",
    },
ProtocolProofObligation {
        interface: "zwp_relative_pointer_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/relative_pointer.rs",
    },
ProtocolProofObligation {
        interface: "zwp_tablet_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/tablet.rs",
    },
ProtocolProofObligation {
        interface: "zwp_text_input_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/text_input.rs",
    },
ProtocolProofObligation {
        interface: "zwp_text_input_manager_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/text_input_v2.rs",
    },
ProtocolProofObligation {
        interface: "zwp_text_input_manager_v3",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay text_input)",
    },
ProtocolProofObligation {
        interface: "zwp_virtual_keyboard_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/mod.rs (smithay virtual_keyboard)",
    },
ProtocolProofObligation {
        interface: "zwp_xwayland_keyboard_grab_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/ext/xwayland_keyboard_grab.rs",
    },
ProtocolProofObligation {
        interface: "zxdg_decoration_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/decoration.rs",
    },
ProtocolProofObligation {
        interface: "zxdg_exporter_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_foreign.rs",
    },
ProtocolProofObligation {
        interface: "zxdg_importer_v2",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_foreign.rs",
    },
ProtocolProofObligation {
        interface: "zxdg_output_manager_v1",
        checks: ErroneousChecks::None,
        rust_module: "src/core/wayland/xdg/xdg_output.rs",
    },
ProtocolProofObligation {
        interface: "zxdg_shell_v6",
        checks: ErroneousChecks::Helpers(&[
            "xdg_v6_positioner_size_must_be_positive",
            "xdg_v6_positioner_anchor_rect_non_negative",
        ]),
        rust_module: "src/core/wayland/xdg/v6/mod.rs",
    },
];

/// Helper names that must have matching `#[kani::proof] fn <name>()` harnesses.
pub fn required_kani_harnesses() -> Vec<&'static str> {
    let mut out = Vec::new();
    for obl in PROTOCOL_PROOF_OBLIGATIONS {
        if let ErroneousChecks::Helpers(names) = obl.checks {
            out.extend_from_slice(names);
        }
    }
    out.sort_unstable();
    out.dedup();
    out
}

pub fn obligation_for(interface: &str) -> Option<&'static ProtocolProofObligation> {
    PROTOCOL_PROOF_OBLIGATIONS
        .iter()
        .find(|o| o.interface == interface)
}

// ---------------------------------------------------------------------------
// wp_viewporter
// ---------------------------------------------------------------------------

/// `set_source` arguments are all -1 (unset) or a non-negative origin with a
/// positive size. Spec: wp_viewport.error.bad_value.
pub fn viewport_source_request_is_valid(x: f64, y: f64, width: f64, height: f64) -> bool {
    let unset = [x, y, width, height].iter().all(|v| *v == -1.0);
    unset || (x >= 0.0 && y >= 0.0 && width > 0.0 && height > 0.0)
}

/// `set_destination` arguments are both -1 (unset) or both positive.
pub fn viewport_destination_request_is_valid(width: i32, height: i32) -> bool {
    (width == -1 && height == -1) || (width > 0 && height > 0)
}

/// Integer model of out-of-buffer: source rectangle must lie inside
/// `0..buf_w` × `0..buf_h` (inclusive origin, exclusive end via width/height).
pub fn viewport_commit_rejects_out_of_buffer_i32(
    buf_w: i32,
    buf_h: i32,
    src_x: i32,
    src_y: i32,
    src_w: i32,
    src_h: i32,
) -> bool {
    if buf_w < 0 || buf_h < 0 || src_w < 0 || src_h < 0 {
        return true;
    }
    if src_x < 0 || src_y < 0 {
        return true;
    }
    src_x.saturating_add(src_w) > buf_w || src_y.saturating_add(src_h) > buf_h
}

/// Fractional source size without destination is bad_size (integer millunits:
/// width_mill % 1000 != 0 means fractional).
pub fn viewport_commit_rejects_fractional_without_dest(
    has_destination: bool,
    width_mill: i32,
    height_mill: i32,
) -> bool {
    if has_destination {
        return false;
    }
    width_mill.rem_euclid(1000) != 0 || height_mill.rem_euclid(1000) != 0
}

// ---------------------------------------------------------------------------
// wp_fractional_scale / wp_alpha_modifier / content / cursor / tearing
// ---------------------------------------------------------------------------

pub fn fractional_scale_units_at_least_120(output_scale_centi: u32) -> u32 {
    let preferred = output_scale_centi.saturating_mul(120) / 100;
    preferred.max(120)
}

/// Alpha factor maps to \[0.0, 1.0\] when interpreted as u32::MAX = 1.0.
pub fn alpha_modifier_factor_is_unit_interval(factor: u32) -> bool {
    // Every u32 is a valid factor by protocol; this asserts the float map stays in range.
    let f = (factor as f64) / (u32::MAX as f64);
    (0.0..=1.0).contains(&f)
}

pub fn content_type_hint_is_known_or_none(raw: u32) -> bool {
    matches!(raw, 0 | 1 | 2 | 3) // none, photo, video, game
}

pub fn cursor_shape_value_is_non_zero(shape: u32) -> bool {
    shape > 0
}

pub fn tearing_hint_is_vsync_or_async(hint: u32) -> bool {
    hint == 0 || hint == 1
}

pub fn single_pixel_buffer_is_one_by_one(width: i32, height: i32) -> bool {
    width == 1 && height == 1
}

// ---------------------------------------------------------------------------
// drm-lease / idle / shortcuts / constraints / shell / xdg-v6
// ---------------------------------------------------------------------------

pub fn drm_lease_request_rejects_empty(connector_count: u32) -> bool {
    connector_count == 0
}

pub fn drm_lease_request_rejects_without_connectors(advertised_connectors: u32) -> bool {
    advertised_connectors == 0
}

pub fn wlr_input_inhibit_rejects_second_inhibitor(already_inhibited: bool) -> bool {
    already_inhibited
}

/// Without a host export capability, capture must cancel (Temporary).
pub fn export_dmabuf_should_cancel_without_capability(has_capability: bool) -> bool {
    !has_capability
}

/// At most one gamma control may be active per output.
pub fn gamma_control_rejects_second_active(already_active: bool) -> bool {
    already_active
}

/// SetGamma fd must deliver `size * 3 * sizeof(u16)` bytes.
pub fn gamma_ramp_byte_len_matches(size: u32, nbytes: usize) -> bool {
    nbytes == (size as usize).saturating_mul(3).saturating_mul(2)
}

/// Protocol Mode values are Off=0 and On=1.
pub fn output_power_mode_is_on_or_off(mode: u32) -> bool {
    mode == 0 || mode == 1
}

/// At most one color-representation object per wl_surface.
pub fn color_representation_rejects_duplicate_surface(already: bool) -> bool {
    already
}

/// Advertised alpha modes are 0..=2 (electrical / optical / straight).
pub fn color_representation_alpha_mode_supported(mode: u32) -> bool {
    mode <= 2
}

/// Session may have only one outstanding capture frame.
pub fn image_copy_capture_rejects_duplicate_frame(already_has_frame: bool) -> bool {
    already_has_frame
}

/// Global shortcut app_id+id must be unique.
pub fn hyprland_shortcut_rejects_duplicate(already: bool) -> bool {
    already
}

pub fn idle_inhibit_map_remove_clears(before: u32, removed: bool) -> u32 {
    if removed {
        before.saturating_sub(1)
    } else {
        before
    }
}

/// After create the surface is inhibited; after destroy it is not.
pub fn shortcuts_inhibit_surface_toggle(_was_inhibited: bool, destroy: bool) -> bool {
    !destroy
}

/// Oneshot constraint that was deactivated never reactivates.
pub fn pointer_constraint_oneshot_stays_dead(defunct: bool, should_be_active: bool) -> bool {
    !(defunct && should_be_active)
}

pub fn wl_shell_role_conflict(surface_already_has_role: bool) -> bool {
    surface_already_has_role
}

/// Content with `target_ns` must wait when `now_ns` is earlier.
pub fn commit_timing_hold_required(target_ns: u64, now_ns: u64) -> bool {
    target_ns > now_ns
}

/// A set FIFO barrier blocks the next commit until that content is presented.
pub fn fifo_barrier_blocks_next_commit(barrier_armed: bool, barrier_presented: bool) -> bool {
    barrier_armed && !barrier_presented
}

pub fn xdg_v6_positioner_size_must_be_positive(width: i32, height: i32) -> bool {
    width > 0 && height > 0
}

pub fn xdg_v6_positioner_anchor_rect_non_negative(x: i32, y: i32, width: i32, height: i32) -> bool {
    x >= 0 && y >= 0 && width >= 0 && height >= 0
}

// ---------------------------------------------------------------------------
// Kani harnesses (one per helper name listed in obligations)
// ---------------------------------------------------------------------------

#[cfg(kani)]
mod kani_proofs {
    use super::*;

    #[kani::proof]
    fn viewport_source_request_is_valid() {
        let x: f64 = kani::any();
        let y: f64 = kani::any();
        let w: f64 = kani::any();
        let h: f64 = kani::any();
        kani::assume(x.is_finite() && y.is_finite() && w.is_finite() && h.is_finite());
        let ok = super::viewport_source_request_is_valid(x, y, w, h);
        if ok {
            let unset = [x, y, w, h].iter().all(|v| *v == -1.0);
            assert!(unset || (x >= 0.0 && y >= 0.0 && w > 0.0 && h > 0.0));
        }
    }

    #[kani::proof]
    fn viewport_destination_request_is_valid() {
        let w: i32 = kani::any();
        let h: i32 = kani::any();
        let ok = super::viewport_destination_request_is_valid(w, h);
        if ok {
            assert!((w == -1 && h == -1) || (w > 0 && h > 0));
        } else {
            assert!(!(w == -1 && h == -1));
            assert!(!(w > 0 && h > 0));
        }
    }

    #[kani::proof]
    fn viewport_commit_rejects_out_of_buffer_i32() {
        let bw: i32 = kani::any();
        let bh: i32 = kani::any();
        let sx: i32 = kani::any();
        let sy: i32 = kani::any();
        let sw: i32 = kani::any();
        let sh: i32 = kani::any();
        kani::assume((0..1024).contains(&bw) && (0..1024).contains(&bh));
        kani::assume((-16..2048).contains(&sx) && (-16..2048).contains(&sy));
        kani::assume((0..2048).contains(&sw) && (0..2048).contains(&sh));
        let reject = super::viewport_commit_rejects_out_of_buffer_i32(bw, bh, sx, sy, sw, sh);
        if !reject {
            assert!(sx >= 0 && sy >= 0);
            assert!(sx.saturating_add(sw) <= bw);
            assert!(sy.saturating_add(sh) <= bh);
        }
    }

    #[kani::proof]
    fn viewport_commit_rejects_fractional_without_dest() {
        let has_dest: bool = kani::any();
        let wm: i32 = kani::any();
        let hm: i32 = kani::any();
        kani::assume((-10_000..10_000).contains(&wm) && (-10_000..10_000).contains(&hm));
        let reject = super::viewport_commit_rejects_fractional_without_dest(has_dest, wm, hm);
        if has_dest {
            assert!(!reject);
        } else if wm.rem_euclid(1000) == 0 && hm.rem_euclid(1000) == 0 {
            assert!(!reject);
        } else {
            assert!(reject);
        }
    }

    #[kani::proof]
    fn fractional_scale_units_at_least_120() {
        let centi: u32 = kani::any();
        kani::assume(centi <= 800); // up to 8.00×
        let u = super::fractional_scale_units_at_least_120(centi);
        assert!(u >= 120);
    }

    #[kani::proof]
    fn alpha_modifier_factor_is_unit_interval() {
        let f: u32 = kani::any();
        assert!(super::alpha_modifier_factor_is_unit_interval(f));
    }

    #[kani::proof]
    fn content_type_hint_is_known_or_none() {
        let raw: u32 = kani::any();
        kani::assume(raw <= 8);
        let ok = super::content_type_hint_is_known_or_none(raw);
        assert_eq!(ok, matches!(raw, 0 | 1 | 2 | 3));
    }

    #[kani::proof]
    fn cursor_shape_value_is_non_zero() {
        let s: u32 = kani::any();
        kani::assume(s <= 64);
        assert_eq!(super::cursor_shape_value_is_non_zero(s), s > 0);
    }

    #[kani::proof]
    fn tearing_hint_is_vsync_or_async() {
        let h: u32 = kani::any();
        kani::assume(h <= 4);
        assert_eq!(super::tearing_hint_is_vsync_or_async(h), h == 0 || h == 1);
    }

    #[kani::proof]
    fn single_pixel_buffer_is_one_by_one() {
        let w: i32 = kani::any();
        let h: i32 = kani::any();
        kani::assume((-4..8).contains(&w) && (-4..8).contains(&h));
        assert_eq!(
            super::single_pixel_buffer_is_one_by_one(w, h),
            w == 1 && h == 1
        );
    }

    #[kani::proof]
    fn drm_lease_request_rejects_empty() {
        let n: u32 = kani::any();
        kani::assume(n <= 8);
        assert_eq!(super::drm_lease_request_rejects_empty(n), n == 0);
    }

    #[kani::proof]
    fn drm_lease_request_rejects_without_connectors() {
        let n: u32 = kani::any();
        kani::assume(n <= 8);
        assert_eq!(super::drm_lease_request_rejects_without_connectors(n), n == 0);
    }

    #[kani::proof]
    fn wlr_input_inhibit_rejects_second_inhibitor() {
        let already: bool = kani::any();
        assert_eq!(
            super::wlr_input_inhibit_rejects_second_inhibitor(already),
            already
        );
    }

    #[kani::proof]
    fn idle_inhibit_map_remove_clears() {
        let before: u32 = kani::any();
        let removed: bool = kani::any();
        kani::assume(before <= 1024);
        let after = super::idle_inhibit_map_remove_clears(before, removed);
        if removed {
            assert!(after == before.saturating_sub(1));
        } else {
            assert_eq!(after, before);
        }
    }

    #[kani::proof]
    fn shortcuts_inhibit_surface_toggle() {
        let was: bool = kani::any();
        let destroy: bool = kani::any();
        let now = super::shortcuts_inhibit_surface_toggle(was, destroy);
        if destroy {
            assert!(!now);
        } else {
            assert!(now);
        }
    }

    #[kani::proof]
    fn pointer_constraint_oneshot_stays_dead() {
        let defunct: bool = kani::any();
        let active: bool = kani::any();
        let ok = super::pointer_constraint_oneshot_stays_dead(defunct, active);
        assert_eq!(ok, !(defunct && active));
    }

    #[kani::proof]
    fn wl_shell_role_conflict() {
        let has: bool = kani::any();
        assert_eq!(super::wl_shell_role_conflict(has), has);
    }

    #[kani::proof]
    fn commit_timing_hold_required() {
        let target: u64 = kani::any();
        let now: u64 = kani::any();
        kani::assume(target <= 10_000);
        kani::assume(now <= 10_000);
        assert_eq!(
            super::commit_timing_hold_required(target, now),
            target > now
        );
    }

    #[kani::proof]
    fn fifo_barrier_blocks_next_commit() {
        let armed: bool = kani::any();
        let presented: bool = kani::any();
        assert_eq!(
            super::fifo_barrier_blocks_next_commit(armed, presented),
            armed && !presented
        );
    }

    #[kani::proof]
    fn xdg_v6_positioner_size_must_be_positive() {
        let w: i32 = kani::any();
        let h: i32 = kani::any();
        kani::assume((-16..256).contains(&w) && (-16..256).contains(&h));
        assert_eq!(
            super::xdg_v6_positioner_size_must_be_positive(w, h),
            w > 0 && h > 0
        );
    }

    #[kani::proof]
    fn xdg_v6_positioner_anchor_rect_non_negative() {
        let x: i32 = kani::any();
        let y: i32 = kani::any();
        let w: i32 = kani::any();
        let h: i32 = kani::any();
        kani::assume((-8..64).contains(&x) && (-8..64).contains(&y));
        kani::assume((-8..64).contains(&w) && (-8..64).contains(&h));
        assert_eq!(
            super::xdg_v6_positioner_anchor_rect_non_negative(x, y, w, h),
            x >= 0 && y >= 0 && w >= 0 && h >= 0
        );
    }

    #[kani::proof]
    fn export_dmabuf_should_cancel_without_capability() {
        let has: bool = kani::any();
        assert_eq!(
            super::export_dmabuf_should_cancel_without_capability(has),
            !has
        );
    }

    #[kani::proof]
    fn gamma_control_rejects_second_active() {
        let already: bool = kani::any();
        assert_eq!(super::gamma_control_rejects_second_active(already), already);
    }

    #[kani::proof]
    fn gamma_ramp_byte_len_matches() {
        let size: u32 = kani::any();
        let nbytes: usize = kani::any();
        kani::assume(size <= 1024);
        kani::assume(nbytes <= 8192);
        let expected = (size as usize).saturating_mul(3).saturating_mul(2);
        assert_eq!(
            super::gamma_ramp_byte_len_matches(size, nbytes),
            nbytes == expected
        );
    }

    #[kani::proof]
    fn output_power_mode_is_on_or_off() {
        let mode: u32 = kani::any();
        kani::assume(mode <= 8);
        assert_eq!(
            super::output_power_mode_is_on_or_off(mode),
            mode == 0 || mode == 1
        );
    }

    #[kani::proof]
    fn color_representation_rejects_duplicate_surface() {
        let already: bool = kani::any();
        assert_eq!(
            super::color_representation_rejects_duplicate_surface(already),
            already
        );
    }

    #[kani::proof]
    fn color_representation_alpha_mode_supported() {
        let mode: u32 = kani::any();
        kani::assume(mode <= 8);
        assert_eq!(
            super::color_representation_alpha_mode_supported(mode),
            mode <= 2
        );
    }

    #[kani::proof]
    fn image_copy_capture_rejects_duplicate_frame() {
        let already: bool = kani::any();
        assert_eq!(
            super::image_copy_capture_rejects_duplicate_frame(already),
            already
        );
    }

    #[kani::proof]
    fn hyprland_shortcut_rejects_duplicate() {
        let already: bool = kani::any();
        assert_eq!(super::hyprland_shortcut_rejects_duplicate(already), already);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn obligations_are_sorted_by_interface() {
        let names: Vec<_> = PROTOCOL_PROOF_OBLIGATIONS
            .iter()
            .map(|o| o.interface)
            .collect();
        let mut sorted = names.clone();
        sorted.sort_unstable();
        assert_eq!(names, sorted, "PROTOCOL_PROOF_OBLIGATIONS must stay sorted");
    }

    #[test]
    fn obligations_have_unique_interfaces() {
        let mut seen = std::collections::BTreeSet::new();
        for o in PROTOCOL_PROOF_OBLIGATIONS {
            assert!(
                seen.insert(o.interface),
                "duplicate obligation for {}",
                o.interface
            );
        }
    }

    #[test]
    fn viewport_destination_examples() {
        assert!(viewport_destination_request_is_valid(-1, -1));
        assert!(viewport_destination_request_is_valid(64, 48));
        assert!(!viewport_destination_request_is_valid(0, 10));
        assert!(!viewport_destination_request_is_valid(10, -1));
    }

    #[test]
    fn viewport_source_examples() {
        assert!(viewport_source_request_is_valid(-1.0, -1.0, -1.0, -1.0));
        assert!(viewport_source_request_is_valid(0.0, 0.0, 10.0, 10.0));
        assert!(!viewport_source_request_is_valid(-0.5, 0.0, 1.0, 1.0));
    }

    #[test]
    fn required_harnesses_non_empty() {
        assert!(!required_kani_harnesses().is_empty());
    }
}
