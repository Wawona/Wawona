//! Background Effect protocol implementation.
//!
//! Allows surfaces to request background blur effects. The compositor stores
//! a blur region per surface. Platform renderers can query this to apply
//! NSVisualEffectView (macOS), UIVisualEffectView (iOS), or shader blur.

use crate::core::wayland::protocol::server::ext::background_effect::v1::server::{
    ext_background_effect_manager_v1::{self, ExtBackgroundEffectManagerV1},
    ext_background_effect_surface_v1::{self, ExtBackgroundEffectSurfaceV1},
};
use std::collections::HashMap;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// Compositor-wide background effect state
#[derive(Debug, Default)]
pub struct BackgroundEffectState {
    /// surface_id → has blur effect
    pub blur_surfaces: HashMap<u32, bool>,
}

impl BackgroundEffectState {
    pub fn has_blur(&self, surface_id: u32) -> bool {
        self.blur_surfaces
            .get(&surface_id)
            .copied()
            .unwrap_or(false)
    }
}

impl GlobalDispatch<ExtBackgroundEffectManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtBackgroundEffectManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_background_effect_manager_v1");
    }
}

impl Dispatch<ExtBackgroundEffectManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtBackgroundEffectManagerV1,
        request: ext_background_effect_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_background_effect_manager_v1::Request::GetBackgroundEffect { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _e = data_init.init(id, surface_id);
                state
                    .ext
                    .background_effect
                    .blur_surfaces
                    .insert(surface_id, false);
                tracing::debug!("Created background effect for surface {}", surface_id);
            }
            ext_background_effect_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtBackgroundEffectSurfaceV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtBackgroundEffectSurfaceV1,
        request: ext_background_effect_surface_v1::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_background_effect_surface_v1::Request::SetBlurRegion { region } => {
                // If a region is provided, blur is enabled; if None, disabled
                let has_blur = region.is_some();
                state
                    .ext
                    .background_effect
                    .blur_surfaces
                    .insert(*surface_id, has_blur);
                tracing::debug!("Surface {} blur: {}", surface_id, has_blur);
            }
            ext_background_effect_surface_v1::Request::Destroy => {
                state.ext.background_effect.blur_surfaces.remove(surface_id);
                tracing::debug!("Background effect removed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

pub fn register_background_effect(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtBackgroundEffectManagerV1, ()>(1, ())
}
