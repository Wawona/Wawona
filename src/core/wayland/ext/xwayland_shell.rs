//! XWayland Shell protocol (`xwayland_shell_v1`).
//!
//! Associates a `wl_surface` with an X11 window via matching serials from the
//! Xwayland client. State lives in Rust core for hosts that embed Xwayland.

use std::collections::HashMap;

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

#[derive(Debug, Clone, Default)]
pub struct XwaylandSurfaceState {
    pub serial_lo: Option<u32>,
    pub serial_hi: Option<u32>,
}

#[derive(Debug, Default)]
pub struct XwaylandShellState {
    /// surface_id → pending serial pair
    pub surfaces: HashMap<u32, XwaylandSurfaceState>,
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
        state: &mut Self,
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
                data_init.init(id, XwaylandSurfaceData { surface_id });
                state
                    .ext
                    .xwayland_shell
                    .surfaces
                    .entry(surface_id)
                    .or_default();
                tracing::debug!("Created XWayland surface for {}", surface_id);
            }
            xwayland_shell_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<XwaylandSurfaceV1, XwaylandSurfaceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &XwaylandSurfaceV1,
        request: xwayland_surface_v1::Request,
        data: &XwaylandSurfaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xwayland_surface_v1::Request::SetSerial {
                serial_lo,
                serial_hi,
            } => {
                let entry = state
                    .ext
                    .xwayland_shell
                    .surfaces
                    .entry(data.surface_id)
                    .or_default();
                entry.serial_lo = Some(serial_lo);
                entry.serial_hi = Some(serial_hi);
                tracing::debug!(
                    "XWayland surface {} serials lo={} hi={}",
                    data.surface_id,
                    serial_lo,
                    serial_hi
                );
            }
            xwayland_surface_v1::Request::Destroy => {
                state.ext.xwayland_shell.surfaces.remove(&data.surface_id);
            }
            _ => {}
        }
    }
}

pub fn register_xwayland_shell(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XwaylandShellV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serial_pair_defaults_unset() {
        let s = XwaylandSurfaceState::default();
        assert!(s.serial_lo.is_none());
        assert!(s.serial_hi.is_none());
    }
}
