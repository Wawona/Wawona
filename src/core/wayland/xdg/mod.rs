pub mod xdg_wm_base;
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
/// Optional XDG protocol families are only exposed for desktop-oriented profiles.
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    use wayland_protocols::xdg::xdg_output::zv1::server::zxdg_output_manager_v1::ZxdgOutputManagerV1;
    use wayland_protocols::xdg::foreign::zv2::server::zxdg_importer_v2::ZxdgImporterV2;
    
    if policy::allow_desktop_extensions(state.protocol_profile) {
        use wayland_protocols::xdg::decoration::zv1::server::zxdg_decoration_manager_v1::ZxdgDecorationManagerV1;

        dh.create_global::<CompositorState, ZxdgDecorationManagerV1, _>(1, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_decoration_manager_v1");

        xdg_foreign::register_xdg_exporter(dh);
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_exporter_v2");

        dh.create_global::<CompositorState, ZxdgImporterV2, _>(1, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_importer_v2");

        // Delegate registration to per-protocol modules for a single source of truth.
        xdg_activation::register_xdg_activation(dh);
        xdg_dialog::register_xdg_dialog(dh);
        xdg_system_bell::register_xdg_system_bell(dh);
        xdg_toplevel_drag::register_xdg_toplevel_drag(dh);
        xdg_toplevel_icon::register_xdg_toplevel_icon(dh);
        xdg_toplevel_tag::register_xdg_toplevel_tag(dh);

        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Registered desktop-only XDG protocols (decoration, foreign, activation, dialog, system bell, icons, tags)"
        );
    } else {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping desktop-only XDG globals for profile {}",
            state.protocol_profile.as_str()
        );
    }
}
