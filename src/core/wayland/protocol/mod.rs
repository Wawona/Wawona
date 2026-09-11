//! Wayland Protocol Bindings for Wawona Compositor
//!
//! This module provides unified access to all Wayland protocol types for both
//! server-side (compositor) and client-side (testing/nested) use cases.
//!
//! ## Architecture
//!
//! All protocols are re-exported from established Rust crates:
//! - `wayland-server` / `wayland-client` - Core Wayland protocol
//! - `wayland-protocols` - Official extensions (wp, xdg, ext, xwayland)
//! - `wayland-protocols-wlr` - wlroots extensions (layer_shell, screencopy, etc.)
//! - `wayland-protocols-misc` - Miscellaneous protocols (virtual_keyboard, etc.)
//!
//! ## Usage
//!
//! ```rust,ignore
//! // Server-side: implementing xdg-shell
//! use crate::core::wayland::protocol::server::xdg::shell;
//!
//! // Server-side: implementing wlr-layer-shell
//! use crate::core::wayland::protocol::server::wlroots;
//!
//! // Client-side (for testing/nested compositor)
//! use crate::core::wayland::protocol::client::xdg::shell;
//! ```

// =============================================================================
// Server-Side Protocol Bindings
// =============================================================================

/// Server-side protocol bindings for compositor implementation.
///
/// These are the types used to implement protocol interfaces that clients
/// connect to. All server bindings use `wayland-server` crate features.
pub mod server {
    // -------------------------------------------------------------------------
    // Core Wayland Protocol
    // -------------------------------------------------------------------------

    /// Core Wayland protocol (wl_compositor, wl_surface, wl_seat, etc.)
    pub use wayland_server::protocol as wayland_core;

    // -------------------------------------------------------------------------
    // Official Wayland Protocol Extensions (wayland-protocols)
    // -------------------------------------------------------------------------

    /// wp_* protocols - Wayland Presentation/Platform extensions
    ///
    /// Includes: viewporter, presentation_time, linux_dmabuf, fractional_scale,
    /// cursor_shape, fifo, tearing_control, etc.
    pub use wayland_protocols::wp;

    /// xdg_* protocols - Desktop shell protocols
    ///
    /// Includes: xdg_shell, xdg_decoration, xdg_activation, xdg_output,
    /// xdg_foreign, xdg_dialog, xdg_toplevel_drag, etc.
    pub use wayland_protocols::xdg;

    /// ext_* protocols - Extended protocols
    ///
    /// Includes: ext_session_lock, ext_idle_notify, ext_foreign_toplevel_list,
    /// ext_data_control, ext_workspace, etc.
    pub use wayland_protocols::ext;

    /// xwayland_* protocols - XWayland compatibility
    ///
    /// Includes: xwayland_keyboard_grab, xwayland_shell
    pub use wayland_protocols::xwayland;

    // -------------------------------------------------------------------------
    // wlroots Protocol Extensions
    // -------------------------------------------------------------------------

    /// wlroots protocols for Sway/Hyprland/river compatibility
    ///
    /// Includes all 10 wlroots protocols:
    /// - zwlr_layer_shell_v1 - Panels, wallpapers, overlays (CRITICAL)
    /// - zwlr_output_management_v1 - Display configuration
    /// - zwlr_foreign_toplevel_management_v1 - Task bars
    /// - zwlr_screencopy_manager_v1 - Screen capture
    /// - zwlr_gamma_control_manager_v1 - Night light
    /// - zwlr_data_control_manager_v1 - Clipboard managers
    /// - zwlr_export_dmabuf_manager_v1 - GPU buffer export
    /// - zwlr_virtual_pointer_manager_v1 - Virtual pointers
    /// - zwp_virtual_keyboard_v1 - Virtual keyboards
    /// - zwlr_input_inhibitor_v1 - Input inhibitor
    pub mod wlroots {
        pub use super::super::wlroots::*;
    }

    // -------------------------------------------------------------------------
    // Miscellaneous Protocols
    // -------------------------------------------------------------------------

    /// zwp_virtual_keyboard_v1 - Virtual keyboard input
    pub mod zwp_virtual_keyboard_v1 {
        pub use wayland_protocols_misc::zwp_virtual_keyboard_v1::server::*;
    }

    /// gtk_primary_selection - GTK primary selection (clipboard)
    pub mod gtk_primary_selection {
        pub use wayland_protocols_misc::gtk_primary_selection::server::*;
    }

    /// server_decoration - Server-side decoration negotiation (KDE protocol)
    pub mod org_kde_kwin_server_decoration {
        pub use wayland_protocols_misc::server_decoration::server::*;
    }

    pub mod plasma {
        pub use wayland_protocols_plasma::*;
    }

    /// input_method - Input method protocol (unstable, zwp)
    pub mod zwp_input_method_v2 {
        pub use wayland_protocols_misc::zwp_input_method_v2::server::*;
    }
}

// =============================================================================
// Client-Side Protocol Bindings
// =============================================================================

/// Client-side protocol bindings for testing and nested compositor support.
///
/// These are the types used to connect to a compositor as a client.
/// All client bindings use `wayland-client` crate features.
pub mod client {
    // -------------------------------------------------------------------------
    // Core Wayland Protocol
    // -------------------------------------------------------------------------

    /// Core Wayland protocol (wl_compositor, wl_surface, wl_seat, etc.)
    pub use wayland_client::protocol as wayland_core;

    // -------------------------------------------------------------------------
    // Official Wayland Protocol Extensions (wayland-protocols)
    // -------------------------------------------------------------------------

    /// wp_* protocols - Wayland Presentation/Platform extensions
    pub use wayland_protocols::wp;

    /// xdg_* protocols - Desktop shell protocols
    pub use wayland_protocols::xdg;

    /// ext_* protocols - Extended protocols
    pub use wayland_protocols::ext;

    /// xwayland_* protocols - XWayland compatibility
    pub use wayland_protocols::xwayland;

    // -------------------------------------------------------------------------
    // wlroots Protocol Extensions
    // -------------------------------------------------------------------------

    /// wlroots protocols (client-side, for testing)
    pub use wayland_protocols_wlr as wlroots;

    // -------------------------------------------------------------------------
    // Miscellaneous Protocols
    // -------------------------------------------------------------------------

    /// zwp_virtual_keyboard_v1 - Virtual keyboard input (client-side)
    pub mod zwp_virtual_keyboard_v1 {
        pub use wayland_protocols_misc::zwp_virtual_keyboard_v1::client::*;
    }

    /// gtk_primary_selection - GTK primary selection (client-side)
    pub mod gtk_primary_selection {
        pub use wayland_protocols_misc::gtk_primary_selection::client::*;
    }
}

// =============================================================================
// wlroots Protocol Submodule (Server-Side Only)
// =============================================================================
// This provides detailed server-side re-exports for wlroots protocols
pub mod wlroots;
