//! Fractional Scale protocol implementation.
//!
//! This protocol allows clients to receive a preferred fractional scale
//! from the compositor, enabling smooth HiDPI rendering.

use wayland_protocols::wp::fractional_scale::v1::server::{
    wp_fractional_scale_manager_v1::{self, WpFractionalScaleManagerV1},
    wp_fractional_scale_v1::{self, WpFractionalScaleV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with fractional scale object
#[derive(Debug, Clone)]
pub struct FractionalScaleData {
    pub surface_id: u32,
}

// ============================================================================
// wp_fractional_scale_manager_v1
// ============================================================================

impl GlobalDispatch<WpFractionalScaleManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpFractionalScaleManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_fractional_scale_manager_v1");
    }
}

impl Dispatch<WpFractionalScaleManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpFractionalScaleManagerV1,
        request: wp_fractional_scale_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_fractional_scale_manager_v1::Request::GetFractionalScale { id, surface } => {
                let surface_id = surface.id().protocol_id();
                // let data = FractionalScaleData { surface_id };
                let fractional_scale = data_init.init(id, ());

                // Send initial preferred scale in 1/120 units, aligned with current output scale.
                let output_scale = _state.primary_output().scale.max(1.0);
                let preferred = (output_scale * 120.0).round().max(120.0) as u32;
                fractional_scale.preferred_scale(preferred);

                tracing::debug!("Created fractional scale for surface {}", surface_id);
            }
            wp_fractional_scale_manager_v1::Request::Destroy => {
                tracing::debug!("wp_fractional_scale_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_fractional_scale_v1
// ============================================================================

impl Dispatch<WpFractionalScaleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpFractionalScaleV1,
        request: wp_fractional_scale_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_fractional_scale_v1::Request::Destroy => {
                tracing::debug!("wp_fractional_scale_v1 destroyed");
            }
            _ => {}
        }
    }
}

/// Register wp_fractional_scale_manager_v1 global
pub fn register_fractional_scale(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpFractionalScaleManagerV1, ()>(1, ())
}
