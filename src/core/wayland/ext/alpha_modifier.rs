//! Alpha Modifier protocol implementation.
//!
//! This protocol allows clients to specify a multiplier for the alpha channel
//! when compositing a surface. The factor is a u32 fixed-point value where
//! 0 = fully transparent and u32::MAX = fully opaque (no modification).
//! The scene graph uses this value to modulate surface opacity.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::alpha_modifier::v1::server::{
    wp_alpha_modifier_v1::{self, WpAlphaModifierV1},
    wp_alpha_modifier_surface_v1::{self, WpAlphaModifierSurfaceV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Tracks alpha multiplier per surface
#[derive(Debug, Clone, Default)]
pub struct AlphaModifierState {
    /// surface_id → alpha multiplier (u32::MAX = 1.0, 0 = 0.0)
    pub surface_alpha: HashMap<u32, u32>,
}

impl AlphaModifierState {
    /// Get the alpha multiplier for a surface as a float (0.0 to 1.0)
    pub fn get_alpha_f64(&self, surface_id: u32) -> f64 {
        match self.surface_alpha.get(&surface_id) {
            Some(&factor) => (factor as f64) / (u32::MAX as f64),
            None => 1.0,
        }
    }
}

// ============================================================================
// wp_alpha_modifier_v1
// ============================================================================

impl GlobalDispatch<WpAlphaModifierV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpAlphaModifierV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_alpha_modifier_v1");
    }
}

impl Dispatch<WpAlphaModifierV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpAlphaModifierV1,
        request: wp_alpha_modifier_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_alpha_modifier_v1::Request::GetSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _am = data_init.init(id, surface_id);
                // Default: u32::MAX = 1.0 (no modification)
                state.ext.alpha_modifier.surface_alpha.insert(surface_id, u32::MAX);
                tracing::debug!("Created alpha modifier for surface {}", surface_id);
            }
            wp_alpha_modifier_v1::Request::Destroy => {
                tracing::debug!("wp_alpha_modifier_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_alpha_modifier_surface_v1. User data is surface_id: u32
// ============================================================================

impl Dispatch<WpAlphaModifierSurfaceV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpAlphaModifierSurfaceV1,
        request: wp_alpha_modifier_surface_v1::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_alpha_modifier_surface_v1::Request::SetMultiplier { factor } => {
                state.ext.alpha_modifier.surface_alpha.insert(*surface_id, factor);
                let alpha = (factor as f64) / (u32::MAX as f64);
                tracing::debug!("Surface {} alpha multiplier: {:.4}", surface_id, alpha);
            }
            wp_alpha_modifier_surface_v1::Request::Destroy => {
                state.ext.alpha_modifier.surface_alpha.remove(surface_id);
                tracing::debug!("Alpha modifier destroyed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

/// Register wp_alpha_modifier_v1 global
pub fn register_alpha_modifier(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpAlphaModifierV1, ()>(1, ())
}
