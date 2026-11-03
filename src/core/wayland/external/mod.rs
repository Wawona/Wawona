//! Auto-generated external protocol handlers.

mod agl_screenshooter_protocol;
mod agl_shell_desktop_protocol;
mod agl_shell_protocol;
mod aura_output_management_protocol;
mod aura_shell_protocol;
mod gtk_shell_protocol;
mod mir_shell_unstable_v1_protocol;
mod nvidia_eglstream_controller_protocol;
mod nvidia_eglstream_protocol;
mod xapp_shell_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

use agl_screenshooter_protocol::agl_screenshooter::{self, AglScreenshooter};
use agl_shell_desktop_protocol::agl_shell_desktop::{self, AglShellDesktop};
use agl_shell_protocol::agl_shell::{self, AglShell};
use agl_shell_protocol::agl_shell_ext::{self, AglShellExt};
use aura_output_management_protocol::zaura_output_manager_v2::{self, ZauraOutputManagerV2};
use aura_shell_protocol::zaura_shell::{self, ZauraShell};
use aura_shell_protocol::zaura_surface::{self, ZauraSurface};
use aura_shell_protocol::zaura_output::{self, ZauraOutput};
use aura_shell_protocol::zaura_toplevel::{self, ZauraToplevel};
use aura_shell_protocol::zaura_popup::{self, ZauraPopup};
use aura_shell_protocol::zaura_output_manager::{self, ZauraOutputManager};
use gtk_shell_protocol::gtk_shell1::{self, GtkShell1};
use gtk_shell_protocol::gtk_surface1::{self, GtkSurface1};
use mir_shell_unstable_v1_protocol::mir_shell_v1::{self, MirShellV1};
use mir_shell_unstable_v1_protocol::mir_regular_surface_v1::{self, MirRegularSurfaceV1};
use mir_shell_unstable_v1_protocol::mir_floating_regular_surface_v1::{self, MirFloatingRegularSurfaceV1};
use mir_shell_unstable_v1_protocol::mir_dialog_surface_v1::{self, MirDialogSurfaceV1};
use mir_shell_unstable_v1_protocol::mir_satellite_surface_v1::{self, MirSatelliteSurfaceV1};
use mir_shell_unstable_v1_protocol::mir_positioner_v1::{self, MirPositionerV1};
use nvidia_eglstream_controller_protocol::wl_eglstream_controller::{self, WlEglstreamController};
use nvidia_eglstream_protocol::wl_eglstream::{self, WlEglstream};
use nvidia_eglstream_protocol::wl_eglstream_display::{self, WlEglstreamDisplay};
use xapp_shell_protocol::xapp_shell_v1::{self, XappShellV1};
use xapp_shell_protocol::xapp_surface_v1::{self, XappSurfaceV1};

impl GlobalDispatch<AglScreenshooter, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<AglScreenshooter>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<AglScreenshooter, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &AglScreenshooter,
        request: agl_screenshooter::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<AglShellDesktop, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<AglShellDesktop>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<AglShellDesktop, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &AglShellDesktop,
        request: agl_shell_desktop::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<AglShell, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<AglShell>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<AglShell, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &AglShell,
        request: agl_shell::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<AglShellExt, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &AglShellExt,
        request: agl_shell_ext::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<ZauraOutputManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZauraOutputManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZauraOutputManagerV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraOutputManagerV2,
        request: zaura_output_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<ZauraShell, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZauraShell>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZauraShell, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraShell,
        request: zaura_shell::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zaura_shell::Request::GetAuraSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            zaura_shell::Request::GetAuraOutput { id, output: _ } => {
                data_init.init(id, ());
            }
            zaura_shell::Request::GetAuraToplevelForXdgToplevel { id, toplevel: _ } => {
                data_init.init(id, ());
            }
            zaura_shell::Request::GetAuraPopupForXdgPopup { id, popup: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<ZauraSurface, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraSurface,
        request: zaura_surface::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<ZauraOutput, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraOutput,
        request: zaura_output::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<ZauraToplevel, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraToplevel,
        request: zaura_toplevel::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<ZauraPopup, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraPopup,
        request: zaura_popup::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<ZauraOutputManager, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZauraOutputManager,
        request: zaura_output_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<GtkShell1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<GtkShell1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<GtkShell1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &GtkShell1,
        request: gtk_shell1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            gtk_shell1::Request::GetGtkSurface { gtk_surface, surface: _ } => {
                data_init.init(gtk_surface, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<GtkSurface1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &GtkSurface1,
        request: gtk_surface1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<MirShellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<MirShellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<MirShellV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirShellV1,
        request: mir_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            mir_shell_v1::Request::GetRegularSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            mir_shell_v1::Request::GetFloatingRegularSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            mir_shell_v1::Request::GetDialogSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            mir_shell_v1::Request::GetSatelliteSurface { id, surface: _, positioner: _ } => {
                data_init.init(id, ());
            }
            mir_shell_v1::Request::CreatePositioner { id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<MirRegularSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirRegularSurfaceV1,
        request: mir_regular_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<MirFloatingRegularSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirFloatingRegularSurfaceV1,
        request: mir_floating_regular_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<MirDialogSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirDialogSurfaceV1,
        request: mir_dialog_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<MirSatelliteSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirSatelliteSurfaceV1,
        request: mir_satellite_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<MirPositionerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &MirPositionerV1,
        request: mir_positioner_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WlEglstreamController, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlEglstreamController>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WlEglstreamController, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WlEglstreamController,
        request: wl_eglstream_controller::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<WlEglstream, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WlEglstream,
        request: wl_eglstream::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WlEglstreamDisplay, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlEglstreamDisplay>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WlEglstreamDisplay, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WlEglstreamDisplay,
        request: wl_eglstream_display::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_eglstream_display::Request::CreateStream { id, width: _, height: _, handle: _, _type: _, attribs: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<XappShellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XappShellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XappShellV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XappShellV1,
        request: xapp_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xapp_shell_v1::Request::GetXappSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XappSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XappSurfaceV1,
        request: xapp_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_desktop_extensions(state.protocol_profile) {
        return;
    }
    dh.create_global::<CompositorState, AglScreenshooter, ()>(1, ());
    dh.create_global::<CompositorState, AglShellDesktop, ()>(2, ());
    dh.create_global::<CompositorState, AglShell, ()>(11, ());
    dh.create_global::<CompositorState, ZauraOutputManagerV2, ()>(1, ());
    dh.create_global::<CompositorState, ZauraShell, ()>(65, ());
    dh.create_global::<CompositorState, GtkShell1, ()>(5, ());
    dh.create_global::<CompositorState, MirShellV1, ()>(1, ());
    dh.create_global::<CompositorState, WlEglstreamController, ()>(2, ());
    dh.create_global::<CompositorState, WlEglstreamDisplay, ()>(1, ());
    dh.create_global::<CompositorState, XappShellV1, ()>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered external protocol globals");
}

#[cfg(test)]
mod tests {
    #[test]
    fn external_register_compiles() {
        assert!(true);
    }
}
