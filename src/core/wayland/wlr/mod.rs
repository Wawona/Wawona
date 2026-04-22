//! wlroots Protocol Support
//!
//! This module provides implementations for wlroots-compatible protocols.

// Protocol modules for categorization
pub mod layer_shell;
pub use layer_shell::LayerSurfaceData;
pub mod output_management;
pub mod output_power_management;
pub mod foreign_toplevel_management;
pub mod screencopy;
pub mod gamma_control;
pub mod data_control;
pub mod export_dmabuf;
pub mod virtual_pointer;
pub mod virtual_keyboard;

use wayland_server::DisplayHandle;
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

/// Register wlroots-compatible protocols
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    layer_shell::register_layer_shell(dh);
    output_management::register_output_management(dh);
    output_power_management::register_output_power_management(dh);
    gamma_control::register_gamma_control(dh);
    if policy::allow_privileged_wlr(state.protocol_profile) {
        foreign_toplevel_management::register_foreign_toplevel_management(dh);
        screencopy::register_screencopy(dh);
        data_control::register_data_control(dh);
        export_dmabuf::register_export_dmabuf(dh);
        virtual_pointer::register_virtual_pointer(dh);
        virtual_keyboard::register_virtual_keyboard(dh);
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Privileged wlroots globals disabled for profile {}",
            state.protocol_profile.as_str()
        );
    }

    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered all wlroots-compatible protocols");
}
