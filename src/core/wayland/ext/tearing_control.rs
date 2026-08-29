//! Tearing Control protocol implementation.
//!
//! This protocol allows clients to indicate their preference for tearing
//! vs. vsync behavior during presentation. The compositor can use this
//! hint to decide whether to allow tearing (async presentation) or
//! enforce vsync for a given surface.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::tearing_control::v1::server::{
    wp_tearing_control_manager_v1::{self, WpTearingControlManagerV1},
    wp_tearing_control_v1::{self, WpTearingControlV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Presentation hint from the client
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PresentationHint {
    /// VSync. No tearing (default)
    #[default]
    Vsync,
    /// Allow tearing for lowest latency
    Async,
}

/// Per-surface tearing control state
#[derive(Debug, Clone, Default)]
pub struct TearingControlState {
    /// Surface ID → presentation hint
    pub surface_hints: HashMap<u32, PresentationHint>,
}

impl TearingControlState {
    /// Check if a surface prefers async (tearing) presentation
    pub fn prefers_tearing(&self, surface_id: u32) -> bool {
        matches!(
            self.surface_hints.get(&surface_id),
            Some(PresentationHint::Async)
        )
    }
}

// ============================================================================
// wp_tearing_control_manager_v1
// ============================================================================

impl GlobalDispatch<WpTearingControlManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpTearingControlManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_tearing_control_manager_v1");
    }
}

impl Dispatch<WpTearingControlManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpTearingControlManagerV1,
        request: wp_tearing_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_tearing_control_manager_v1::Request::GetTearingControl { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _tc = data_init.init(id, surface_id);
                // Default to vsync
                state.ext.tearing_control.surface_hints.insert(surface_id, PresentationHint::Vsync);
                tracing::debug!("Created tearing control for surface {}", surface_id);
            }
            wp_tearing_control_manager_v1::Request::Destroy => {
                tracing::debug!("wp_tearing_control_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_tearing_control_v1. User data is surface_id: u32
// ============================================================================

impl Dispatch<WpTearingControlV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpTearingControlV1,
        request: wp_tearing_control_v1::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_tearing_control_v1::Request::SetPresentationHint { hint } => {
                let hint_val = match hint {
                    wayland_server::WEnum::Value(wp_tearing_control_v1::PresentationHint::Async) => {
                        PresentationHint::Async
                    }
                    _ => PresentationHint::Vsync,
                };
                state.ext.tearing_control.surface_hints.insert(*surface_id, hint_val);
                tracing::debug!("Surface {} presentation hint: {:?}", surface_id, hint_val);
            }
            wp_tearing_control_v1::Request::Destroy => {
                state.ext.tearing_control.surface_hints.remove(surface_id);
                tracing::debug!("Tearing control destroyed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

/// Register wp_tearing_control_manager_v1 global
pub fn register_tearing_control(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpTearingControlManagerV1, ()>(1, ())
}
