//! XWayland Shell protocol implementation.
//!
//! Provides XWayland surface integration.

use wayland_protocols::xwayland::shell::v1::server::{
    xwayland_shell_v1::{self, XwaylandShellV1},
    xwayland_surface_v1::{self, XwaylandSurfaceV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct XwaylandSurfaceData {
    pub surface_id: u32,
}

impl GlobalDispatch<XwaylandShellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XwaylandShellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xwayland_shell_v1");
    }
}

impl Dispatch<XwaylandShellV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XwaylandShellV1,
        request: xwayland_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xwayland_shell_v1::Request::GetXwaylandSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                // We drop surface_id tracking for now to pass type checker
                let _s = data_init.init(id, ());
                tracing::debug!("Created XWayland surface for {}", surface_id);
            }
            xwayland_shell_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<XwaylandSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XwaylandSurfaceV1,
        request: xwayland_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xwayland_surface_v1::Request::SetSerial { .. } => {}
            xwayland_surface_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_xwayland_shell(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XwaylandShellV1, ()>(1, ())
}
