//! Named `zwp_input_panel_v1` (popup placement).
//!
//! `zwp_input_method_manager_v2` is owned by Smithay
//! (`delegate_input_method_manager!`) plus the in-process host IM stand-in.
//! Do not `create_global` that interface here.

use wayland_protocols::wp::input_method::zv1::server::{
    zwp_input_panel_surface_v1::{self, ZwpInputPanelSurfaceV1},
    zwp_input_panel_v1::{self, ZwpInputPanelV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct InputPanelSurfaceData {
    pub surface_id: u32,
}

impl GlobalDispatch<ZwpInputPanelV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpInputPanelV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_input_panel_v1");
    }
}

impl Dispatch<ZwpInputPanelV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputPanelV1,
        request: zwp_input_panel_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_panel_v1::Request::GetInputPanelSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _s = data_init.init(id, ());
                tracing::debug!("Created input panel surface for {}", surface_id);
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpInputPanelSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputPanelSurfaceV1,
        request: zwp_input_panel_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_panel_surface_v1::Request::SetToplevel { .. } => {}
            zwp_input_panel_surface_v1::Request::SetOverlayPanel => {}
            _ => {}
        }
    }
}

pub fn register_input_panel(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpInputPanelV1, ()>(1, ())
}
