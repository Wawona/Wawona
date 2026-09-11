//! Color Representation protocol implementation.
//!
//! Provides color representation hints for surfaces.

use wayland_protocols::wp::color_representation::v1::server::{
    wp_color_representation_manager_v1::{self, WpColorRepresentationManagerV1},
    wp_color_representation_surface_v1::{self, WpColorRepresentationSurfaceV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct ColorRepresentationSurfaceData {
    pub surface_id: u32,
}

impl GlobalDispatch<WpColorRepresentationManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpColorRepresentationManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_color_representation_manager_v1");
    }
}

impl Dispatch<WpColorRepresentationManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorRepresentationManagerV1,
        request: wp_color_representation_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_representation_manager_v1::Request::GetSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _cr = data_init.init(id, ());
                tracing::debug!("Created color representation for surface {}", surface_id);
            }
            wp_color_representation_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpColorRepresentationSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorRepresentationSurfaceV1,
        request: wp_color_representation_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_representation_surface_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_color_representation(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpColorRepresentationManagerV1, ()>(1, ())
}
