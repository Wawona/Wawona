//! Catalog of every Wayland global Wawona may advertise.
//!
//! Status (Functional / Partial / Stub) is a required human-reviewed field.
//! CI checks registry ⊆ catalog and that catalog rows which claim advertisement
//! on the active profile appear in the live registry. CI does not infer status.

use super::policy::{allow_desktop_extensions, ExposureClass, ProtocolProfile};

/// Human-reviewed implementation depth. Not inferred from the registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProtocolStatus {
    Functional,
    Partial,
    Stub,
}

impl ProtocolStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Functional => "Functional",
            Self::Partial => "Partial",
            Self::Stub => "Stub",
        }
    }
}

/// Protocol family / origin for the generated matrix.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ProtocolOrigin {
    WaylandCore,
    Xdg,
    Wlr,
    Ext,
    Plasma,
}

impl ProtocolOrigin {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::WaylandCore => "wayland core",
            Self::Xdg => "xdg / wayland-protocols",
            Self::Wlr => "wlr (wlroots)",
            Self::Ext => "ext / wayland-protocols",
            Self::Plasma => "plasma (KDE)",
        }
    }

    pub fn heading(self) -> &'static str {
        match self {
            Self::WaylandCore => "Core",
            Self::Xdg => "XDG",
            Self::Wlr => "wlroots",
            Self::Ext => "Extensions",
            Self::Plasma => "KDE / Plasma",
        }
    }
}

/// One advertised (or profile-gated) global.
#[derive(Debug, Clone, Copy)]
pub struct ProtocolCatalogEntry {
    pub interface: &'static str,
    /// wayland.app XML slug (`https://wayland.app/protocols/{slug}#{interface}`).
    /// Empty means no wayland.app page; use `spec_xml` instead.
    pub wayland_app_slug: &'static str,
    /// Upstream XML URL when wayland.app has no page.
    pub spec_xml: &'static str,
    pub origin: ProtocolOrigin,
    pub rust_module: &'static str,
    pub status: ProtocolStatus,
    pub exposure: ExposureClass,
}

impl ProtocolCatalogEntry {
    pub fn spec_url(&self) -> String {
        if !self.wayland_app_slug.is_empty() {
            format!(
                "https://wayland.app/protocols/{}#{}",
                self.wayland_app_slug, self.interface
            )
        } else {
            self.spec_xml.to_string()
        }
    }

    pub fn advertised_on(&self, profile: ProtocolProfile) -> bool {
        match self.exposure {
            ExposureClass::StoreSafeCore | ExposureClass::StoreSafeConditional => true,
            ExposureClass::DesktopOnly => allow_desktop_extensions(profile),
            ExposureClass::InternalOnly => matches!(profile, ProtocolProfile::FullDev),
        }
    }
}

macro_rules! cat {
    ($iface:literal, $slug:literal, $origin:ident, $module:literal, $status:ident, $exposure:ident) => {
        ProtocolCatalogEntry {
            interface: $iface,
            wayland_app_slug: $slug,
            spec_xml: "",
            origin: ProtocolOrigin::$origin,
            rust_module: $module,
            status: ProtocolStatus::$status,
            exposure: ExposureClass::$exposure,
        }
    };
}

/// Every global that production `register_globals` may advertise.
/// Keep in sync with `src/core/compositor.rs` registration, not with a hand count.
pub const PROTOCOL_CATALOG: &[ProtocolCatalogEntry] = &[
    // Core (Smithay)
    cat!("wl_compositor", "wayland", WaylandCore, "src/core/wayland/mod.rs (smithay compositor)", Functional, StoreSafeCore),
    cat!("wl_shm", "wayland", WaylandCore, "src/core/wayland/mod.rs (smithay shm)", Functional, StoreSafeCore),
    cat!("wl_output", "wayland", WaylandCore, "src/core/wayland/mod.rs (smithay output)", Functional, StoreSafeCore),
    cat!("wl_seat", "wayland", WaylandCore, "src/core/wayland/mod.rs (smithay seat)", Partial, StoreSafeCore),
    cat!("wl_subcompositor", "wayland", WaylandCore, "src/core/wayland/ext/subcompositor.rs", Partial, StoreSafeCore),
    cat!("wl_data_device_manager", "wayland", WaylandCore, "src/core/wayland/mod.rs (smithay data device)", Partial, StoreSafeCore),
    // XDG
    cat!("xdg_wm_base", "xdg-shell", Xdg, "src/core/wayland/xdg/xdg_wm_base.rs", Functional, StoreSafeCore),
    cat!("zxdg_decoration_manager_v1", "xdg-decoration-unstable-v1", Xdg, "src/core/wayland/xdg/decoration.rs", Functional, DesktopOnly),
    cat!("zxdg_output_manager_v1", "xdg-output-unstable-v1", Xdg, "src/core/wayland/xdg/xdg_output.rs", Partial, DesktopOnly),
    cat!("zxdg_exporter_v2", "xdg-foreign-unstable-v2", Xdg, "src/core/wayland/xdg/xdg_foreign.rs", Stub, DesktopOnly),
    cat!("zxdg_importer_v2", "xdg-foreign-unstable-v2", Xdg, "src/core/wayland/xdg/xdg_foreign.rs", Stub, DesktopOnly),
    cat!("xdg_activation_v1", "xdg-activation-v1", Xdg, "src/core/wayland/xdg/xdg_activation.rs", Stub, DesktopOnly),
    cat!("xdg_wm_dialog_v1", "xdg-dialog-v1", Xdg, "src/core/wayland/xdg/xdg_dialog.rs", Stub, DesktopOnly),
    cat!("xdg_toplevel_drag_manager_v1", "xdg-toplevel-drag-v1", Xdg, "src/core/wayland/xdg/xdg_toplevel_drag.rs", Stub, DesktopOnly),
    cat!("xdg_toplevel_icon_manager_v1", "xdg-toplevel-icon-v1", Xdg, "src/core/wayland/xdg/xdg_toplevel_icon.rs", Stub, DesktopOnly),
    cat!("xdg_toplevel_tag_manager_v1", "xdg-toplevel-tag-v1", Xdg, "src/core/wayland/xdg/xdg_toplevel_tag.rs", Stub, DesktopOnly),
    cat!("xdg_system_bell_v1", "xdg-system-bell-v1", Xdg, "src/core/wayland/xdg/xdg_system_bell.rs", Stub, DesktopOnly),
    cat!("xwayland_shell_v1", "xwayland-shell-v1", Xdg, "src/core/wayland/ext/xwayland_shell.rs", Stub, DesktopOnly),
    // wlroots
    cat!("zwlr_layer_shell_v1", "wlr-layer-shell-unstable-v1", Wlr, "src/core/wayland/wlr/layer_shell.rs", Partial, DesktopOnly),
    cat!("zwlr_output_manager_v1", "wlr-output-management-unstable-v1", Wlr, "src/core/wayland/wlr/output_management.rs", Stub, StoreSafeCore),
    cat!("zwlr_output_power_manager_v1", "wlr-output-power-management-unstable-v1", Wlr, "src/core/wayland/wlr/output_power_management.rs", Stub, StoreSafeCore),
    cat!("zwlr_gamma_control_manager_v1", "wlr-gamma-control-unstable-v1", Wlr, "src/core/wayland/wlr/gamma_control.rs", Stub, StoreSafeCore),
    cat!("zwlr_foreign_toplevel_manager_v1", "wlr-foreign-toplevel-management-unstable-v1", Wlr, "src/core/wayland/wlr/foreign_toplevel_management.rs", Stub, DesktopOnly),
    cat!("zwlr_screencopy_manager_v1", "wlr-screencopy-unstable-v1", Wlr, "src/core/wayland/wlr/screencopy.rs", Stub, DesktopOnly),
    cat!("zwlr_data_control_manager_v1", "wlr-data-control-unstable-v1", Wlr, "src/core/wayland/wlr/data_control.rs", Stub, DesktopOnly),
    cat!("zwlr_export_dmabuf_manager_v1", "wlr-export-dmabuf-unstable-v1", Wlr, "src/core/wayland/wlr/export_dmabuf.rs", Stub, DesktopOnly),
    cat!("zwlr_virtual_pointer_manager_v1", "wlr-virtual-pointer-unstable-v1", Wlr, "src/core/wayland/wlr/virtual_pointer.rs", Stub, DesktopOnly),
    cat!("zwp_virtual_keyboard_manager_v1", "virtual-keyboard-unstable-v1", Wlr, "src/core/wayland/wlr/virtual_keyboard.rs", Stub, DesktopOnly),
    // Extensions
    cat!("wp_viewporter", "viewporter", Ext, "src/core/wayland/ext/viewporter.rs", Stub, StoreSafeCore),
    cat!("wp_presentation", "presentation-time", Ext, "src/core/wayland/ext/presentation_time.rs", Partial, StoreSafeCore),
    cat!("zwp_relative_pointer_manager_v1", "relative-pointer-unstable-v1", Ext, "src/core/wayland/ext/relative_pointer.rs", Stub, StoreSafeCore),
    cat!("zwp_pointer_constraints_v1", "pointer-constraints-unstable-v1", Ext, "src/core/wayland/ext/pointer_constraints.rs", Stub, StoreSafeCore),
    cat!("zwp_pointer_gestures_v1", "pointer-gestures-unstable-v1", Ext, "src/core/wayland/ext/pointer_gestures.rs", Stub, StoreSafeCore),
    cat!("zwp_idle_inhibit_manager_v1", "idle-inhibit-unstable-v1", Ext, "src/core/wayland/ext/idle_inhibit.rs", Stub, StoreSafeCore),
    cat!("zwp_text_input_manager_v3", "text-input-unstable-v3", Ext, "src/core/wayland/ext/text_input.rs", Stub, StoreSafeCore),
    cat!("zwp_text_input_manager_v1", "text-input-unstable-v1", Ext, "src/core/wayland/ext/text_input.rs", Stub, StoreSafeCore),
    cat!("zwp_keyboard_shortcuts_inhibit_manager_v1", "keyboard-shortcuts-inhibit-unstable-v1", Ext, "src/core/wayland/ext/keyboard_shortcuts_inhibit.rs", Stub, StoreSafeCore),
    cat!("zwp_linux_dmabuf_v1", "linux-dmabuf-v1", Ext, "src/core/wayland/ext/linux_dmabuf.rs", Partial, StoreSafeCore),
    cat!("zwp_linux_explicit_synchronization_v1", "linux-explicit-synchronization-unstable-v1", Ext, "src/core/wayland/ext/linux_explicit_sync.rs", Stub, StoreSafeCore),
    cat!("zwp_input_timestamps_manager_v1", "input-timestamps-unstable-v1", Ext, "src/core/wayland/ext/input_timestamps.rs", Stub, StoreSafeCore),
    cat!("wp_alpha_modifier_v1", "alpha-modifier-v1", Ext, "src/core/wayland/ext/alpha_modifier.rs", Stub, StoreSafeCore),
    cat!("wp_commit_timing_manager_v1", "commit-timing-v1", Ext, "src/core/wayland/ext/commit_timing.rs", Stub, StoreSafeCore),
    cat!("wp_color_manager_v1", "color-management-v1", Ext, "src/core/wayland/ext/color_management.rs", Stub, StoreSafeCore),
    cat!("wp_content_type_manager_v1", "content-type-v1", Ext, "src/core/wayland/ext/content_type.rs", Stub, StoreSafeCore),
    cat!("wp_cursor_shape_manager_v1", "cursor-shape-v1", Ext, "src/core/wayland/ext/cursor_shape.rs", Stub, StoreSafeCore),
    cat!("wp_fifo_manager_v1", "fifo-v1", Ext, "src/core/wayland/ext/fifo.rs", Stub, StoreSafeCore),
    cat!("wp_fractional_scale_manager_v1", "fractional-scale-v1", Ext, "src/core/wayland/ext/fractional_scale.rs", Stub, StoreSafeCore),
    cat!("wp_tearing_control_manager_v1", "tearing-control-v1", Ext, "src/core/wayland/ext/tearing_control.rs", Stub, StoreSafeCore),
    cat!("ext_idle_notifier_v1", "ext-idle-notify-v1", Ext, "src/core/wayland/ext/idle_notify.rs", Stub, StoreSafeCore),
    cat!("wp_single_pixel_buffer_manager_v1", "single-pixel-buffer-v1", Ext, "src/core/wayland/ext/single_pixel_buffer.rs", Stub, StoreSafeCore),
    cat!("wp_security_context_manager_v1", "security-context-v1", Ext, "src/core/wayland/ext/security_context.rs", Stub, StoreSafeCore),
    cat!("wp_color_representation_manager_v1", "color-representation-v1", Ext, "src/core/wayland/ext/color_representation.rs", Stub, StoreSafeCore),
    cat!("ext_transient_seat_manager_v1", "ext-transient-seat-v1", Ext, "src/core/wayland/ext/transient_seat.rs", Stub, StoreSafeCore),
    cat!("ext_foreign_toplevel_list_v1", "ext-foreign-toplevel-list-v1", Ext, "src/core/wayland/ext/foreign_toplevel_list.rs", Stub, StoreSafeCore),
    cat!("ext_data_control_manager_v1", "ext-data-control-v1", Ext, "src/core/wayland/ext/data_control.rs", Stub, StoreSafeConditional),
    cat!("ext_workspace_manager_v1", "ext-workspace-v1", Ext, "src/core/wayland/ext/workspace.rs", Stub, StoreSafeCore),
    cat!("ext_background_effect_manager_v1", "ext-background-effect-v1", Ext, "src/core/wayland/ext/background_effect.rs", Stub, StoreSafeCore),
    cat!("wp_pointer_warp_v1", "pointer-warp-v1", Ext, "src/core/wayland/ext/pointer_warp.rs", Stub, DesktopOnly),
    cat!("zwp_tablet_manager_v2", "tablet-v2", Ext, "src/core/wayland/ext/tablet.rs", Stub, DesktopOnly),
    cat!("zwp_primary_selection_device_manager_v1", "primary-selection-unstable-v1", Ext, "src/core/wayland/ext/primary_selection.rs", Stub, DesktopOnly),
    cat!("ext_session_lock_manager_v1", "ext-session-lock-v1", Ext, "src/core/wayland/ext/session_lock.rs", Stub, DesktopOnly),
    cat!("ext_output_image_capture_source_manager_v1", "ext-image-capture-source-v1", Ext, "src/core/wayland/ext/image_capture_source.rs", Stub, DesktopOnly),
    cat!("ext_image_copy_capture_manager_v1", "ext-image-copy-capture-v1", Ext, "src/core/wayland/ext/image_copy_capture.rs", Stub, DesktopOnly),
    cat!("zwp_xwayland_keyboard_grab_manager_v1", "xwayland-keyboard-grab-unstable-v1", Ext, "src/core/wayland/ext/xwayland_keyboard_grab.rs", Stub, DesktopOnly),
    cat!("zwp_input_method_manager_v2", "input-method-unstable-v2", Ext, "src/core/wayland/ext/input_method.rs", Stub, DesktopOnly),
    // Plasma (desktop-host / full-dev)
    cat!("org_kde_kwin_server_decoration_manager", "kde-server-decoration", Plasma, "src/core/wayland/plasma/kde_decoration.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_blur_manager", "kde-blur", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_contrast_manager", "kde-contrast", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_shadow_manager", "kde-shadow", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_dpms_manager", "kde-dpms", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_idle_timeout", "kde-idle", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
    cat!("org_kde_kwin_slide_manager", "kde-slide", Plasma, "src/core/wayland/plasma/plasma.rs", Stub, DesktopOnly),
];

pub fn catalog_by_interface(interface: &str) -> Option<&'static ProtocolCatalogEntry> {
    PROTOCOL_CATALOG.iter().find(|e| e.interface == interface)
}

pub fn slug_is_well_formed(slug: &str) -> bool {
    !slug.is_empty()
        && slug
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_core_and_plasma() {
        assert!(catalog_by_interface("wl_compositor").is_some());
        assert!(catalog_by_interface("xdg_wm_base").is_some());
        assert!(catalog_by_interface("org_kde_kwin_blur_manager").is_some());
    }

    #[test]
    fn every_catalog_row_has_spec() {
        for e in PROTOCOL_CATALOG {
            let ok_slug = slug_is_well_formed(e.wayland_app_slug);
            let ok_xml = !e.spec_xml.is_empty() && e.spec_xml.starts_with("https://");
            assert!(
                ok_slug || ok_xml,
                "{} needs a wayland.app slug or spec_xml",
                e.interface
            );
        }
    }
}
