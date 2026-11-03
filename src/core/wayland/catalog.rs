//! Catalog of every Wayland global Wawona may advertise, plus tracked gaps.
//!
//! Status (Functional / Partial / Stub / Missing) is a required human-reviewed
//! field. CI checks registry ⊆ catalog and that catalog rows which claim
//! advertisement on the active profile appear in the live registry. CI does
//! not infer status. `Missing` rows are docs-only: never advertised.

use super::policy::{allow_desktop_extensions, ExposureClass, ProtocolProfile};

/// Human-reviewed implementation depth. Not inferred from the registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum ProtocolStatus {
    /// Handles requests, mutates state, sends events.
    Functional,
    /// Global registered; some requests handled; incomplete semantics.
    Partial,
    /// Global registered; handlers log or no-op.
    Stub,
    /// Not registered / not implemented. Tracked for the status matrix only.
    Missing,
}

impl ProtocolStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Functional => "Functional",
            Self::Partial => "Partial",
            Self::Stub => "Stub",
            Self::Missing => "Missing",
        }
    }

    /// Table sort key: Functional first, Missing last.
    pub fn sort_rank(self) -> u8 {
        match self {
            Self::Functional => 0,
            Self::Partial => 1,
            Self::Stub => 2,
            Self::Missing => 3,
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
    Cosmic,
    River,
    Hyprland,
    Weston,
    Treeland,
    External,
}

impl ProtocolOrigin {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::WaylandCore => "wayland core",
            Self::Xdg => "xdg / wayland-protocols",
            Self::Wlr => "wlr (wlroots)",
            Self::Ext => "ext / wayland-protocols",
            Self::Plasma => "plasma (KDE)",
            Self::Cosmic => "cosmic",
            Self::River => "river",
            Self::Hyprland => "hyprland",
            Self::Weston => "weston",
            Self::Treeland => "treeland",
            Self::External => "external",
        }
    }

    pub fn heading(self) -> &'static str {
        match self {
            Self::WaylandCore => "Core",
            Self::Xdg => "XDG",
            Self::Wlr => "wlroots",
            Self::Ext => "Extensions",
            Self::Plasma => "KDE / Plasma",
            Self::Cosmic => "COSMIC",
            Self::River => "River",
            Self::Hyprland => "Hyprland",
            Self::Weston => "Weston",
            Self::Treeland => "Treeland",
            Self::External => "External",
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
        // Missing rows are documentation gaps only; never expected in the registry.
        if self.status == ProtocolStatus::Missing {
            return false;
        }
        // DRM lease needs a real DRM/KMS node (capability, not OS gate).
        // Syncobj is protocol-complete without a DRM node on every platform.
        if self.interface == "wp_drm_lease_device_v1" && !drm_lease_node_available() {
            return false;
        }
        match self.exposure {
            ExposureClass::StoreSafeCore | ExposureClass::StoreSafeConditional => true,
            ExposureClass::DesktopOnly => allow_desktop_extensions(profile),
            ExposureClass::InternalOnly => matches!(profile, ProtocolProfile::FullDev),
        }
    }
}

/// Whether `/dev/dri/*` can be opened for drm-lease advertisement honesty.
fn drm_lease_node_available() -> bool {
    #[cfg(target_os = "linux")]
    {
        use std::fs::OpenOptions;
        use std::os::unix::fs::OpenOptionsExt;
        for path in [
            "/dev/dri/card0",
            "/dev/dri/card1",
            "/dev/dri/renderD128",
            "/dev/dri/renderD129",
        ] {
            if OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(libc::O_CLOEXEC)
                .open(path)
                .is_ok()
            {
                return true;
            }
        }
        false
    }
    #[cfg(not(target_os = "linux"))]
    {
        false
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
    cat!(
        "wl_compositor",
        "wayland",
        WaylandCore,
        "src/core/wayland/mod.rs (smithay compositor)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_shm",
        "wayland",
        WaylandCore,
        "src/core/wayland/mod.rs (smithay shm)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_output",
        "wayland",
        WaylandCore,
        "src/core/wayland/mod.rs (smithay output)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_seat",
        "wayland",
        WaylandCore,
        "src/core/wayland/mod.rs (smithay seat)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_subcompositor",
        "wayland",
        WaylandCore,
        "src/core/wayland/ext/subcompositor.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_data_device_manager",
        "wayland",
        WaylandCore,
        "src/core/wayland/mod.rs (smithay data device)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_fixes",
        "wayland",
        WaylandCore,
        "src/core/wayland/ext/wl_fixes.rs",
        Functional,
        StoreSafeCore
    ),
    // XDG
    cat!(
        "xdg_wm_base",
        "xdg-shell",
        Xdg,
        "src/core/wayland/xdg/xdg_wm_base.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zxdg_shell_v6",
        "xdg-shell-unstable-v6",
        Xdg,
        "src/core/wayland/xdg/v6/mod.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wl_shell",
        "wayland",
        WaylandCore,
        "src/core/wayland/wl_shell.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "gtk_primary_selection_device_manager",
        "gtk-primary-selection",
        Ext,
        "src/core/wayland/ext/gtk_primary_selection.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_text_input_manager_v2",
        "text-input-unstable-v2",
        Plasma,
        "src/core/wayland/ext/text_input_v2.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_input_method_v1",
        "input-method-unstable-v1",
        Ext,
        "src/core/wayland/ext/input_method_v1.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zxdg_decoration_manager_v1",
        "xdg-decoration-unstable-v1",
        Xdg,
        "src/core/wayland/xdg/decoration.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zxdg_output_manager_v1",
        "xdg-output-unstable-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_output.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zxdg_exporter_v2",
        "xdg-foreign-unstable-v2",
        Xdg,
        "src/core/wayland/xdg/xdg_foreign.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zxdg_importer_v2",
        "xdg-foreign-unstable-v2",
        Xdg,
        "src/core/wayland/xdg/xdg_foreign.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_activation_v1",
        "xdg-activation-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_activation.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_wm_dialog_v1",
        "xdg-dialog-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_dialog.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_toplevel_drag_manager_v1",
        "xdg-toplevel-drag-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_toplevel_drag.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_toplevel_icon_manager_v1",
        "xdg-toplevel-icon-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_toplevel_icon.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_toplevel_tag_manager_v1",
        "xdg-toplevel-tag-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_toplevel_tag.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xdg_system_bell_v1",
        "xdg-system-bell-v1",
        Xdg,
        "src/core/wayland/xdg/xdg_system_bell.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "xwayland_shell_v1",
        "xwayland-shell-v1",
        Xdg,
        "src/core/wayland/ext/xwayland_shell.rs",
        Functional,
        DesktopOnly
    ),
    // wlroots
    cat!(
        "zwlr_layer_shell_v1",
        "wlr-layer-shell-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/layer_shell.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_output_manager_v1",
        "wlr-output-management-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/output_management.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwlr_output_power_manager_v1",
        "wlr-output-power-management-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/output_power_management.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwlr_gamma_control_manager_v1",
        "wlr-gamma-control-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/gamma_control.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwlr_foreign_toplevel_manager_v1",
        "wlr-foreign-toplevel-management-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/foreign_toplevel_management.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_screencopy_manager_v1",
        "wlr-screencopy-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/screencopy.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_data_control_manager_v1",
        "wlr-data-control-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/data_control.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_export_dmabuf_manager_v1",
        "wlr-export-dmabuf-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/export_dmabuf.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_virtual_pointer_manager_v1",
        "wlr-virtual-pointer-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/virtual_pointer.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_virtual_keyboard_manager_v1",
        "virtual-keyboard-unstable-v1",
        Wlr,
        "src/core/wayland/mod.rs (smithay virtual_keyboard)",
        Functional,
        DesktopOnly
    ),
    // Extensions
    cat!(
        "wp_viewporter",
        "viewporter",
        Ext,
        "src/core/wayland/ext/viewporter.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_presentation",
        "presentation-time",
        Ext,
        "src/core/wayland/ext/presentation_time.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_relative_pointer_manager_v1",
        "relative-pointer-unstable-v1",
        Ext,
        "src/core/wayland/ext/relative_pointer.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_pointer_constraints_v1",
        "pointer-constraints-unstable-v1",
        Ext,
        "src/core/wayland/ext/pointer_constraints.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_pointer_gestures_v1",
        "pointer-gestures-unstable-v1",
        Ext,
        "src/core/wayland/ext/pointer_gestures.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_idle_inhibit_manager_v1",
        "idle-inhibit-unstable-v1",
        Ext,
        "src/core/wayland/ext/idle_inhibit.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_text_input_manager_v3",
        "text-input-unstable-v3",
        Ext,
        "src/core/wayland/mod.rs (smithay text_input)",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_text_input_manager_v1",
        "text-input-unstable-v1",
        Ext,
        "src/core/wayland/ext/text_input.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_keyboard_shortcuts_inhibit_manager_v1",
        "keyboard-shortcuts-inhibit-unstable-v1",
        Ext,
        "src/core/wayland/ext/keyboard_shortcuts_inhibit.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_linux_dmabuf_v1",
        "linux-dmabuf-v1",
        Ext,
        "src/core/wayland/ext/linux_dmabuf.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_linux_explicit_synchronization_v1",
        "linux-explicit-synchronization-unstable-v1",
        Ext,
        "src/core/wayland/ext/linux_explicit_sync.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "zwp_input_timestamps_manager_v1",
        "input-timestamps-unstable-v1",
        Ext,
        "src/core/wayland/ext/input_timestamps.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_alpha_modifier_v1",
        "alpha-modifier-v1",
        Ext,
        "src/core/wayland/ext/alpha_modifier.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_commit_timing_manager_v1",
        "commit-timing-v1",
        Ext,
        "src/core/wayland/ext/commit_timing.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_color_manager_v1",
        "color-management-v1",
        Ext,
        "src/core/wayland/ext/color_management.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_content_type_manager_v1",
        "content-type-v1",
        Ext,
        "src/core/wayland/ext/content_type.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_cursor_shape_manager_v1",
        "cursor-shape-v1",
        Ext,
        "src/core/wayland/ext/cursor_shape.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_fifo_manager_v1",
        "fifo-v1",
        Ext,
        "src/core/wayland/ext/fifo.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_fractional_scale_manager_v1",
        "fractional-scale-v1",
        Ext,
        "src/core/wayland/ext/fractional_scale.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_tearing_control_manager_v1",
        "tearing-control-v1",
        Ext,
        "src/core/wayland/ext/tearing_control.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "ext_idle_notifier_v1",
        "ext-idle-notify-v1",
        Ext,
        "src/core/wayland/ext/idle_notify.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_single_pixel_buffer_manager_v1",
        "single-pixel-buffer-v1",
        Ext,
        "src/core/wayland/ext/single_pixel_buffer.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_security_context_manager_v1",
        "security-context-v1",
        Ext,
        "src/core/wayland/ext/security_context.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_color_representation_manager_v1",
        "color-representation-v1",
        Ext,
        "src/core/wayland/ext/color_representation.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "ext_transient_seat_manager_v1",
        "ext-transient-seat-v1",
        Ext,
        "src/core/wayland/ext/transient_seat.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "ext_foreign_toplevel_list_v1",
        "ext-foreign-toplevel-list-v1",
        Ext,
        "src/core/wayland/ext/foreign_toplevel_list.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "ext_data_control_manager_v1",
        "ext-data-control-v1",
        Ext,
        "src/core/wayland/ext/data_control.rs",
        Functional,
        StoreSafeConditional
    ),
    cat!(
        "ext_workspace_manager_v1",
        "ext-workspace-v1",
        Ext,
        "src/core/wayland/ext/workspace.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "ext_background_effect_manager_v1",
        "ext-background-effect-v1",
        Ext,
        "src/core/wayland/ext/background_effect.rs",
        Functional,
        StoreSafeCore
    ),
    cat!(
        "wp_pointer_warp_v1",
        "pointer-warp-v1",
        Ext,
        "src/core/wayland/ext/pointer_warp.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_tablet_manager_v2",
        "tablet-v2",
        Ext,
        "src/core/wayland/ext/tablet.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_primary_selection_device_manager_v1",
        "primary-selection-unstable-v1",
        Ext,
        "src/core/wayland/mod.rs (smithay primary_selection)",
        Functional,
        DesktopOnly
    ),
    cat!(
        "ext_session_lock_manager_v1",
        "ext-session-lock-v1",
        Ext,
        "src/core/wayland/ext/session_lock.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "ext_output_image_capture_source_manager_v1",
        "ext-image-capture-source-v1",
        Ext,
        "src/core/wayland/ext/image_capture_source.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "ext_image_copy_capture_manager_v1",
        "ext-image-copy-capture-v1",
        Ext,
        "src/core/wayland/ext/image_copy_capture.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_xwayland_keyboard_grab_manager_v1",
        "xwayland-keyboard-grab-unstable-v1",
        Ext,
        "src/core/wayland/ext/xwayland_keyboard_grab.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwp_input_method_manager_v2",
        "input-method-unstable-v2",
        Ext,
        "src/core/wayland/mod.rs (smithay input_method)",
        Functional,
        DesktopOnly
    ),
    // Plasma (desktop-host / full-dev)
    cat!(
        "org_kde_kwin_server_decoration_manager",
        "kde-server-decoration",
        Plasma,
        "src/core/wayland/plasma/kde_decoration.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_blur_manager",
        "kde-blur",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_contrast_manager",
        "kde-contrast",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_shadow_manager",
        "kde-shadow",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_dpms_manager",
        "kde-dpms",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_idle",
        "kde-idle",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "org_kde_kwin_slide_manager",
        "kde-slide",
        Plasma,
        "src/core/wayland/plasma/plasma.rs",
        Functional,
        DesktopOnly
    ),
    // Opt-in shell: implemented, but only advertised when
    // `advertise_fullscreen_shell` is enabled (not the default desktop-host path).
    // InternalOnly keeps honesty tests from requiring it on desktop-host.
    cat!(
        "zwp_fullscreen_shell_v1",
        "fullscreen-shell-unstable-v1",
        Ext,
        "src/core/wayland/ext/fullscreen_shell.rs",
        Functional,
        InternalOnly
    ),
    cat!(
        "wp_drm_lease_device_v1",
        "drm-lease-v1",
        Ext,
        "src/core/wayland/ext/drm_lease.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "wp_linux_drm_syncobj_manager_v1",
        "linux-drm-syncobj-v1",
        Ext,
        "src/core/wayland/ext/linux_drm_syncobj.rs",
        Functional,
        DesktopOnly
    ),
    cat!(
        "zwlr_input_inhibit_manager_v1",
        "wlr-input-inhibitor-unstable-v1",
        Wlr,
        "src/core/wayland/wlr/input_inhibitor.rs",
        Functional,
        DesktopOnly
    ),

    // -------------------------------------------------------------------------
    // Explorer gaps (Missing): tracked vs wayland.app / Wayland Explorer.
    // Not registered. Portable core must eventually implement these without
    // Linux-only semantic assumptions in the protocol layer.
    // -------------------------------------------------------------------------

    // KDE / Plasma (remaining vs Explorer)
    cat!("org_kde_plasma_shell", "kde-plasma-shell", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_plasma_window_management", "kde-plasma-window-management", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_plasma_virtual_desktop_management", "kde-plasma-virtual-desktop", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_appmenu_manager", "kde-appmenu", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_fake_input", "kde-fake-input", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_keystate", "kde-keystate", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_lockscreen_overlay_v1", "kde-lockscreen-overlay-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_output_management_v2", "kde-output-management-v2", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_output_device_v2", "kde-output-device-v2", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_output_order_v1", "kde-output-order-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_primary_output_v1", "kde-primary-output-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_screen_edge_manager_v1", "kde-screen-edge-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("zkde_screencast_unstable_v1", "kde-screencast-unstable-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_server_decoration_palette_manager", "kde-server-decoration-palette", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("kde_external_brightness_v1", "kde-external-brightness-v1", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_outputmanagement", "kde-output-management", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),
    cat!("org_kde_kwin_outputdevice", "kde-output-device", Plasma, "src/core/wayland/plasma/extra.rs", Functional, DesktopOnly),

    // wayland-protocols experimental / not yet catalogued
    cat!("xx_session_manager_v1", "xx-session-management-v1", Ext, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),
    cat!("xdg_session_manager_v1", "xdg-session-management-v1", Xdg, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),
    cat!("xx_cutouts_manager_v1", "xx-cutouts-v1", Ext, "src/core/wayland/experimental/mod.rs", Functional, StoreSafeCore),
    cat!("xx_zone_manager_v1", "xx-zones-v1", Ext, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),
    cat!("xx_keyboard_filter_manager_v1", "keyboard-filter-experimental-v1", Ext, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),
    cat!("xx_input_method_manager_v2", "input-method-experimental-v2", Ext, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),

    // COSMIC
    cat!("cosmic_a11y_manager_v1", "cosmic-a11y-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("cosmic_atspi_manager_v1", "cosmic-atspi", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_workspace_image_capture_source_manager_v1", "cosmic-image-capture-source", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_output_image_source_manager_v1", "cosmic-image-source-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_workspace_image_source_manager_v1", "cosmic-image-source-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_ext_workspace_image_source_manager_v1", "cosmic-image-source-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_toplevel_image_source_manager_v1", "cosmic-image-source-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_output_manager_v1", "cosmic-output-management-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_overlap_notify_v1", "cosmic-overlap-notify-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_screencopy_manager_v1", "cosmic-screencopy-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_screencopy_manager_v2", "cosmic-screencopy-unstable-v2", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_toplevel_info_v1", "cosmic-toplevel-info-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_toplevel_manager_v1", "cosmic-toplevel-management-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_workspace_manager_v1", "cosmic-workspace-unstable-v1", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),
    cat!("zcosmic_workspace_manager_v2", "cosmic-workspace-unstable-v2", Cosmic, "src/core/wayland/cosmic/mod.rs", Functional, DesktopOnly),

    // River
    cat!("zriver_control_v1", "river-control", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_input_manager_v1", "river-input-management", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_layer_shell_v1", "river-layer-shell", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_layout_manager_v3", "river-window-layout", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_libinput_config_v1", "river-libinput-configuration", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("zriver_status_manager_v1", "river-status", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_window_manager_v1", "river-window-management", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_xkb_bindings_v1", "river-xkb-bindings", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),
    cat!("river_xkb_config_v1", "river-xkb-config", River, "src/core/wayland/river/mod.rs", Functional, DesktopOnly),

    // Hyprland
    cat!("hyprland_ctm_control_manager_v1", "hyprland-ctm-control-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_focus_grab_manager_v1", "hyprland-focus-grab-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_global_shortcuts_manager_v1", "hyprland-global-shortcuts-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_surface_manager_v1", "hyprland-surface-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_toplevel_export_manager_v1", "hyprland-toplevel-export-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_lock_notifier_v1", "hyprland-lock-notify-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),
    cat!("hyprland_toplevel_mapping_manager_v1", "hyprland-toplevel-mapping-v1", Hyprland, "src/core/wayland/hyprland/mod.rs", Functional, DesktopOnly),

    // Weston / IVI
    cat!("ivi_application", "ivi-application", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("ivi_hmi_controller", "ivi-hmi-controller", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("text_cursor_position", "text-cursor-position", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_content_protection", "weston-content-protection", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_debug_v1", "weston-debug", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_desktop_shell", "weston-desktop-shell", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_direct_display_v1", "weston-direct-display", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_capture_v1", "weston-output-capture", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),
    cat!("weston_test", "weston-test", Weston, "src/core/wayland/weston/mod.rs", Functional, InternalOnly),
    cat!("weston_touch_calibration", "weston-touch-calibration", Weston, "src/core/wayland/weston/mod.rs", Functional, DesktopOnly),

    // Treeland
    cat!("treeland_capture_manager_v1", "treeland-capture", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_dde_shell_manager_v1", "treeland-dde-shell", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_foreign_toplevel_manager_v1", "treeland-foreign-toplevel-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_output_manager_v1", "treeland-output-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_personalization_manager_v1", "treeland-personalization-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_shortcut_manager_v1", "treeland-shortcut-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_virtual_output_manager_v1", "treeland-virtual-output-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_wallpaper_color_manager_v1", "treeland-wallpaper-color", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_window_management_v1", "treeland-window-management", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_wallpaper_manager_v1", "treeland-wallpaper-manager", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),
    cat!("treeland_wallpaper_shell_v1", "treeland-wallpaper-shell", Treeland, "src/core/wayland/treeland/mod.rs", Functional, DesktopOnly),

    // External / vendor shells
    cat!("gtk_shell1", "gtk-shell", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("wl_eglstream_display", "nvidia-eglstream", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("wl_eglstream_controller", "nvidia-eglstream-controller", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("mir_shell_v1", "mir-shell", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("xapp_shell_v1", "xapp-shell", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("agl_shell", "agl-shell", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("agl_shell_desktop", "agl-shell-desktop", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("agl_screenshooter", "agl-screenshooter", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("zaura_shell", "aura-shell", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("zaura_output_manager_v2", "aura-output-management", External, "src/core/wayland/external/mod.rs", Functional, DesktopOnly),
    cat!("wl_drm", "mesa-drm", External, "src/core/wayland/experimental/mod.rs", Functional, DesktopOnly),

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

    #[test]
    fn status_sort_rank_is_functional_to_missing() {
        assert!(ProtocolStatus::Functional.sort_rank() < ProtocolStatus::Partial.sort_rank());
        assert!(ProtocolStatus::Partial.sort_rank() < ProtocolStatus::Stub.sort_rank());
        assert!(ProtocolStatus::Stub.sort_rank() < ProtocolStatus::Missing.sort_rank());
    }

    #[test]
    fn missing_rows_are_never_advertised() {
        let missing: Vec<_> = PROTOCOL_CATALOG
            .iter()
            .filter(|e| e.status == ProtocolStatus::Missing)
            .collect();
        for profile in [
            ProtocolProfile::StoreSafe,
            ProtocolProfile::StoreSafeRemote,
            ProtocolProfile::DesktopHost,
            ProtocolProfile::FullDev,
        ] {
            for e in &missing {
                assert!(
                    !e.advertised_on(profile),
                    "{} Missing must not advertise on {}",
                    e.interface,
                    profile.as_str()
                );
            }
        }
    }

    #[test]
    fn missing_rows_track_explorer_gaps() {
        let missing: Vec<_> = PROTOCOL_CATALOG
            .iter()
            .filter(|e| e.status == ProtocolStatus::Missing)
            .map(|e| e.interface)
            .collect();
        // Explorer closure: every tracked family is Functional. Reintroduce
        // Missing rows only when a new Explorer interface is intentionally deferred.
        assert!(
            missing.is_empty(),
            "expected 0 Missing rows after Explorer family closure; found {missing:?}"
        );
        for iface in [
            "zcosmic_toplevel_info_v1",
            "zriver_status_manager_v1",
            "hyprland_toplevel_export_manager_v1",
            "org_kde_plasma_shell",
            "treeland_foreign_toplevel_manager_v1",
            "ivi_application",
        ] {
            let entry = catalog_by_interface(iface)
                .unwrap_or_else(|| panic!("catalog must track {iface}"));
            assert_eq!(
                entry.status,
                ProtocolStatus::Functional,
                "{iface} must be Functional after Explorer closure"
            );
        }
    }

    #[test]
    fn every_functional_protocol_has_proof_obligation() {
        use crate::core::wayland::protocol_proofs::{
            obligation_for, required_kani_harnesses, ErroneousChecks,
            PROTOCOL_PROOF_OBLIGATIONS,
        };

        let functional: Vec<_> = PROTOCOL_CATALOG
            .iter()
            .filter(|e| e.status == ProtocolStatus::Functional)
            .map(|e| e.interface)
            .collect();
        let mut missing = Vec::new();
        for iface in &functional {
            if obligation_for(iface).is_none() {
                missing.push(*iface);
            }
        }
        assert!(
            missing.is_empty(),
            "Functional protocols missing PROTOCOL_PROOF_OBLIGATIONS (add helpers + Kani): {missing:?}"
        );

        // Obligations must not track non-Functional rows (avoids stale proofs).
        let func_set: std::collections::BTreeSet<_> = functional.iter().copied().collect();
        let mut stale = Vec::new();
        for o in PROTOCOL_PROOF_OBLIGATIONS {
            if !func_set.contains(o.interface) {
                stale.push(o.interface);
            }
        }
        assert!(
            stale.is_empty(),
            "PROTOCOL_PROOF_OBLIGATIONS entries are not Functional: {stale:?}"
        );

        // Every Helpers(...) name must be unique and non-empty.
        for o in PROTOCOL_PROOF_OBLIGATIONS {
            if let ErroneousChecks::Helpers(names) = o.checks {
                assert!(!names.is_empty(), "{} Helpers list is empty", o.interface);
            }
        }
        assert!(!required_kani_harnesses().is_empty());
    }
}
