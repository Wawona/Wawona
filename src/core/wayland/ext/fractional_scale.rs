//! Fractional Scale protocol implementation.
//!
//! This protocol allows clients to receive a preferred fractional scale
//! from the compositor, enabling smooth HiDPI rendering (GTK4, Qt, Ghostty).

use std::collections::HashMap;
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

/// Tracks live fractional-scale objects so preferred_scale can be refreshed
/// when the primary output scale changes.
#[derive(Debug, Default)]
pub struct FractionalScaleState {
    /// surface_id -> resource
    pub by_surface: HashMap<u32, WpFractionalScaleV1>,
}

impl FractionalScaleState {
    pub fn preferred_scale_units(output_scale: f32) -> u32 {
        (output_scale.max(1.0) * 120.0).round().max(120.0) as u32
    }

    pub fn notify_all(&self, output_scale: f32) {
        let preferred = Self::preferred_scale_units(output_scale);
        for (surface_id, resource) in &self.by_surface {
            resource.preferred_scale(preferred);
            tracing::debug!(
                "Fractional scale update surface={}: preferred={} (output_scale={})",
                surface_id,
                preferred,
                output_scale
            );
        }
    }
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
        state: &mut Self,
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
                let data = FractionalScaleData { surface_id };
                let fractional_scale = data_init.init(id, data);

                let output_scale = state.primary_output().scale.max(1.0);
                let preferred = FractionalScaleState::preferred_scale_units(output_scale);
                fractional_scale.preferred_scale(preferred);

                state
                    .ext
                    .fractional_scale
                    .by_surface
                    .insert(surface_id, fractional_scale);

                tracing::debug!(
                    "Created fractional scale for surface {} preferred={}",
                    surface_id,
                    preferred
                );
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

impl Dispatch<WpFractionalScaleV1, FractionalScaleData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpFractionalScaleV1,
        request: wp_fractional_scale_v1::Request,
        data: &FractionalScaleData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_fractional_scale_v1::Request::Destroy => {
                state
                    .ext
                    .fractional_scale
                    .by_surface
                    .remove(&data.surface_id);
                tracing::debug!(
                    "wp_fractional_scale_v1 destroyed for surface {}",
                    data.surface_id
                );
            }
            _ => {}
        }
    }
}

/// Register wp_fractional_scale_manager_v1 global
pub fn register_fractional_scale(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpFractionalScaleManagerV1, ()>(1, ())
}
