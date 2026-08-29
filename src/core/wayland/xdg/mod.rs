pub mod xdg_wm_base;
pub mod shell_handler;
pub mod extension_handlers;
pub mod xdg_surface;
pub mod xdg_toplevel;
pub mod xdg_popup;
pub mod xdg_positioner;
pub mod decoration;
pub mod xdg_output;
pub mod xdg_foreign;
pub mod xdg_activation;
pub mod xdg_dialog;
pub mod xdg_toplevel_drag;
pub mod xdg_toplevel_icon;
pub mod xdg_toplevel_tag;
pub mod xdg_system_bell;

use wayland_server::DisplayHandle;
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

/// Register XDG desktop protocols.
///
/// Core shell globals are registered via `smithay_runtime::register_core_shell`.
/// Desktop extension globals use Smithay delegates (`register_xdg_extensions`).
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if policy::allow_desktop_extensions(state.protocol_profile) {
        crate::core::wayland::smithay_runtime::register_xdg_extensions(state, dh);
        // xdg_toplevel_drag_v1 has no Smithay delegate in 0.7. Custom dispatch remains.
        xdg_toplevel_drag::register_xdg_toplevel_drag(dh);

        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Registered desktop-only XDG protocols via Smithay delegates (decoration, foreign, activation, dialog, system bell, icons, tags, toplevel drag)"
        );
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping desktop-only XDG globals for profile {}",
            state.protocol_profile.as_str()
        );
    }
}
