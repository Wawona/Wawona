//! WP Idle Inhibit protocol implementation.
//!
//! This protocol allows clients to prevent the system from going idle,
//! useful for:
//! - Video players during playback
//! - Presentation software
//! - Games

use wayland_protocols::wp::idle_inhibit::zv1::server::{
    zwp_idle_inhibit_manager_v1::{self, ZwpIdleInhibitManagerV1},
    zwp_idle_inhibitor_v1::{self, ZwpIdleInhibitorV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with each idle inhibitor
#[derive(Debug, Clone)]
pub struct IdleInhibitorData {
    pub surface_id: u32,
    pub inhibitor_id: u32,
}

use std::collections::HashMap;

#[derive(Debug, Default)]
pub struct IdleInhibitState {
    pub inhibitors: HashMap<u32, u32>, // inhibitor_id -> surface_id
    pub next_id: u32,
}

// ============================================================================
// zwp_idle_inhibit_manager_v1
// ============================================================================

impl GlobalDispatch<ZwpIdleInhibitManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpIdleInhibitManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_idle_inhibit_manager_v1");
    }
}

impl Dispatch<ZwpIdleInhibitManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpIdleInhibitManagerV1,
        request: zwp_idle_inhibit_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_idle_inhibit_manager_v1::Request::CreateInhibitor { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let inhibitor_id = state.ext.idle_inhibit.next_id;
                state.ext.idle_inhibit.next_id += 1;

                // let data = IdleInhibitorData {
                //     surface_id,
                //     inhibitor_id,
                // };

                let _inhibitor = data_init.init(id, ());

                // Register the inhibitor
                state
                    .ext
                    .idle_inhibit
                    .inhibitors
                    .insert(inhibitor_id, surface_id);

                tracing::debug!(
                    "Created idle inhibitor {} for surface {}",
                    inhibitor_id,
                    surface_id
                );
            }
            zwp_idle_inhibit_manager_v1::Request::Destroy => {
                tracing::debug!("zwp_idle_inhibit_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_idle_inhibitor_v1
// ============================================================================

impl Dispatch<ZwpIdleInhibitorV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpIdleInhibitorV1,
        request: zwp_idle_inhibitor_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_idle_inhibitor_v1::Request::Destroy => {
                // state.remove_idle_inhibitor(data.inhibitor_id);
                tracing::debug!("Idle inhibitor destroyed");
            }
            _ => {}
        }
    }
}

/// Register zwp_idle_inhibit_manager_v1 global
pub fn register_idle_inhibit_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpIdleInhibitManagerV1, ()>(1, ())
}
