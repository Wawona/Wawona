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

/// Register XDG desktop protocols
pub fn register(_state: &mut CompositorState, dh: &DisplayHandle) {
    use wayland_protocols::xdg::shell::server::xdg_wm_base::XdgWmBase;
    use wayland_protocols::xdg::decoration::zv1::server::zxdg_decoration_manager_v1::ZxdgDecorationManagerV1;
    use wayland_protocols::xdg::xdg_output::zv1::server::zxdg_output_manager_v1::ZxdgOutputManagerV1;
    use wayland_protocols::xdg::foreign::zv2::server::{zxdg_exporter_v2::ZxdgExporterV2, zxdg_importer_v2::ZxdgImporterV2};

    dh.create_global::<CompositorState, XdgWmBase, _>(5, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered xdg_wm_base v5");
    
    dh.create_global::<CompositorState, ZxdgDecorationManagerV1, _>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_decoration_manager_v1");
    
    dh.create_global::<CompositorState, ZxdgOutputManagerV1, _>(3, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_output_manager_v1 v3");
    
    dh.create_global::<CompositorState, ZxdgExporterV2, _>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_exporter_v2");
    
    dh.create_global::<CompositorState, ZxdgImporterV2, _>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered zxdg_importer_v2");

    // New 0.32.10 protocols
    use wayland_protocols::xdg::activation::v1::server::xdg_activation_v1::XdgActivationV1;
    use wayland_protocols::xdg::dialog::v1::server::xdg_wm_dialog_v1::XdgWmDialogV1;
    use wayland_protocols::xdg::system_bell::v1::server::xdg_system_bell_v1::XdgSystemBellV1;
    use wayland_protocols::xdg::toplevel_drag::v1::server::xdg_toplevel_drag_manager_v1::XdgToplevelDragManagerV1;
    use wayland_protocols::xdg::toplevel_icon::v1::server::xdg_toplevel_icon_manager_v1::XdgToplevelIconManagerV1;

    dh.create_global::<CompositorState, XdgActivationV1, _>(1, ());
    dh.create_global::<CompositorState, XdgWmDialogV1, _>(1, ());
    dh.create_global::<CompositorState, XdgSystemBellV1, _>(1, ());
    dh.create_global::<CompositorState, XdgToplevelDragManagerV1, _>(1, ());
    dh.create_global::<CompositorState, XdgToplevelIconManagerV1, _>(1, ());

    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered additional XDG protocols (activation, dialog, system bell, icons)");
}
