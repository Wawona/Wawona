// --- Core protocols (always enabled) ---
pub mod subcompositor;
pub mod data_device;
pub mod viewporter;
pub mod linux_dmabuf;
pub mod linux_explicit_sync;
pub mod single_pixel_buffer;
pub mod relative_pointer;
pub mod pointer_constraints;
pub mod pointer_gestures;
pub mod tablet;
pub mod text_input;
pub mod keyboard_shortcuts_inhibit;
pub mod cursor_shape;
pub mod primary_selection;
pub mod input_method;
pub mod input_timestamps;
pub mod pointer_warp;
pub mod presentation_time;
pub mod fractional_scale;
pub mod fifo;
pub mod tearing_control;
pub mod content_type;
pub mod commit_timing;
pub mod alpha_modifier;
pub mod color_management;
pub mod color_representation;
pub mod idle_inhibit;
pub mod idle_notify;
pub mod security_context;
pub mod transient_seat;
pub mod foreign_toplevel_list;
pub mod data_control;
pub mod workspace;
pub mod background_effect;

// --- Linux/desktop-only protocols (not for App Store) ---
// Gated behind feature flag: these are unimplemented or
// inappropriate for iOS/macOS App Store (privacy, DRM, XWayland).
#[cfg(feature = "desktop-protocols")]
pub mod linux_drm_syncobj;
#[cfg(feature = "desktop-protocols")]
pub mod drm_lease;
#[cfg(feature = "desktop-protocols")]
pub mod session_lock;
pub mod fullscreen_shell;
#[cfg(feature = "desktop-protocols")]
pub mod image_capture_source;
#[cfg(feature = "desktop-protocols")]
pub mod image_copy_capture;
#[cfg(feature = "desktop-protocols")]
pub mod xwayland_keyboard_grab;
#[cfg(feature = "desktop-protocols")]
pub mod xwayland_shell;

use wayland_server::DisplayHandle;
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

/// Register Wayland extension protocols.
///
/// Protocols are split into two tiers:
/// - **Core**: Always registered. These are essential for compositor
///   functionality and safe for App Store distribution.
/// - **Desktop**: Only registered when the `desktop-protocols` feature
///   is enabled. These include DRM, XWayland, screen capture, and
///   session lock protocols that are not applicable or allowed on
///   mobile/App Store platforms.
pub fn register(_state: &mut CompositorState, dh: &DisplayHandle) {
    // ── Core WP Protocols ─────────────────────────────────────────
    viewporter::register_viewporter(dh);
    presentation_time::register_presentation_time(dh);
    relative_pointer::register_relative_pointer_manager(dh);
    pointer_constraints::register_pointer_constraints(dh);
    pointer_gestures::register_pointer_gestures(dh);
    idle_inhibit::register_idle_inhibit_manager(dh);
    text_input::register_text_input_manager(dh);
    keyboard_shortcuts_inhibit::register_keyboard_shortcuts_inhibit_manager(dh);
    linux_dmabuf::register_linux_dmabuf(dh);
    linux_explicit_sync::register_linux_explicit_sync(dh);
    input_timestamps::register_input_timestamps(dh);

    // ── Modern Staging & Ext Protocols ────────────────────────────
    alpha_modifier::register_alpha_modifier(dh);
    content_type::register_content_type(dh);
    cursor_shape::register_cursor_shape(dh);
    fifo::register_fifo(dh);
    fractional_scale::register_fractional_scale(dh);
    tearing_control::register_tearing_control(dh);
    idle_notify::register_idle_notify(dh);
    single_pixel_buffer::register_single_pixel_buffer(dh);
    security_context::register_security_context(dh);
    color_representation::register_color_representation(dh);
    transient_seat::register_transient_seat(dh);
    foreign_toplevel_list::register_foreign_toplevel_list(dh);
    data_control::register_data_control(dh);
    workspace::register_workspace(dh);
    background_effect::register_background_effect(dh);

    if _state.advertise_fullscreen_shell && policy::allow_desktop_extensions(_state.protocol_profile) {
        fullscreen_shell::register_fullscreen_shell(dh);
        crate::wlog!(crate::util::logging::COMPOSITOR, "Fullscreen shell advertised (user setting enabled)");
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Fullscreen shell NOT advertised (disabled or disallowed by profile {})",
            _state.protocol_profile.as_str()
        );
    }

    if policy::allow_privileged_wlr(_state.protocol_profile) {
        pointer_warp::register_pointer_warp(dh);
        tablet::register_tablet(dh);
        primary_selection::register_primary_selection(dh);
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping pointer warp for profile {}",
            _state.protocol_profile.as_str()
        );
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping tablet + primary selection for profile {}",
            _state.protocol_profile.as_str()
        );
    }

    // ── Desktop-only protocols (feature-gated) ────────────────────
    #[cfg(feature = "desktop-protocols")]
    {
        if policy::allow_desktop_extensions(_state.protocol_profile) {
            session_lock::register_session_lock(dh);
            image_capture_source::register_image_capture_source(dh);
            image_copy_capture::register_image_copy_capture(dh);
            xwayland_keyboard_grab::register_xwayland_keyboard_grab(dh);
            xwayland_shell::register_xwayland_shell(dh);
            input_method::register_input_method_manager(dh);
        } else {
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "Skipping desktop-only ext globals for profile {}",
                _state.protocol_profile.as_str()
            );
        }
    }

    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered extension protocols");
}
