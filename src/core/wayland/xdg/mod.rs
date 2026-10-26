pub mod decoration;
pub mod extension_handlers;
pub mod shell_handler;
pub mod surface_validation;
pub mod toplevel_state;
pub mod v6;
pub mod xdg_activation;
pub mod xdg_dialog;
pub mod xdg_foreign;
pub mod xdg_output;
pub mod xdg_popup;
pub mod xdg_positioner;
pub mod xdg_surface;
pub mod xdg_system_bell;
pub mod xdg_toplevel;
pub mod xdg_toplevel_drag;
pub mod xdg_toplevel_icon;
pub mod xdg_toplevel_tag;
pub mod xdg_wm_base;

use crate::core::state::CompositorState;
use crate::core::wayland::policy;
use wayland_server::DisplayHandle;

/// Register XDG desktop protocols.
///
/// Core shell globals are registered via `smithay_runtime::register_core_shell`.
/// `xdg_system_bell_v1` is store-safe (audible / haptic feedback only) and is
/// always registered. Other desktop extension globals use Smithay delegates
/// (`register_xdg_extensions`) when the profile allows them.
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    // Always advertise system bell (StoreSafeCore). Idempotent with the
    // desktop-extensions registration path below.
    if state.smithay_runtime.xdg_system_bell.is_none() {
        state.smithay_runtime.xdg_system_bell =
            Some(smithay::wayland::xdg_system_bell::XdgSystemBellState::new::<CompositorState>(dh));
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Registered xdg_system_bell_v1 (store-safe)"
        );
    }

    if policy::allow_desktop_extensions(state.protocol_profile) {
        crate::core::wayland::smithay_runtime::register_xdg_extensions(state, dh);
        // xdg_toplevel_drag_v1 has no Smithay delegate in 0.7. Custom dispatch remains.
        xdg_toplevel_drag::register_xdg_toplevel_drag(dh);
        v6::register(state, dh);
        crate::core::wayland::wl_shell::register(state, dh);

        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Registered desktop-only XDG protocols via Smithay delegates (decoration, foreign, activation, dialog, system bell, icons, tags, toplevel drag)"
        );
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping desktop-only XDG globals for profile {} (system bell already registered)",
            state.protocol_profile.as_str()
        );
    }
}
