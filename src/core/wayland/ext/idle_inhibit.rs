//! WP Idle Inhibit protocol implementation.
//!
//! Clients create inhibitors while a surface should keep the session awake
//! (video, presentations, games). Hosts query [`IdleInhibitState::is_inhibited`].

use wayland_protocols::wp::idle_inhibit::zv1::server::{
    zwp_idle_inhibit_manager_v1::{self, ZwpIdleInhibitManagerV1},
    zwp_idle_inhibitor_v1::{self, ZwpIdleInhibitorV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use std::collections::HashMap;

/// Data stored with each idle inhibitor
#[derive(Debug, Clone)]
pub struct IdleInhibitorData {
    pub surface_id: u32,
    pub inhibitor_id: u32,
}

#[derive(Debug, Default)]
pub struct IdleInhibitState {
    /// inhibitor protocol id → surface id
    pub inhibitors: HashMap<u32, u32>,
    pub next_id: u32,
}

impl IdleInhibitState {
    /// True when any live inhibitor exists (any surface).
    pub fn is_inhibited(&self) -> bool {
        !self.inhibitors.is_empty()
    }

    /// True when the given surface currently holds an inhibitor.
    pub fn is_surface_inhibited(&self, surface_id: u32) -> bool {
        self.inhibitors.values().any(|&sid| sid == surface_id)
    }
}

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
                state.ext.idle_inhibit.next_id = state.ext.idle_inhibit.next_id.wrapping_add(1);

                let inhibitor = data_init.init(
                    id,
                    IdleInhibitorData {
                        surface_id,
                        inhibitor_id,
                    },
                );
                let proto_id = inhibitor.id().protocol_id();
                state
                    .ext
                    .idle_inhibit
                    .inhibitors
                    .insert(proto_id, surface_id);

                tracing::debug!(
                    "Created idle inhibitor {} (proto={}) for surface {}",
                    inhibitor_id,
                    proto_id,
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

impl Dispatch<ZwpIdleInhibitorV1, IdleInhibitorData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpIdleInhibitorV1,
        request: zwp_idle_inhibitor_v1::Request,
        _data: &IdleInhibitorData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_idle_inhibitor_v1::Request::Destroy => {
                let proto_id = resource.id().protocol_id();
                state.ext.idle_inhibit.inhibitors.remove(&proto_id);
                tracing::debug!("Idle inhibitor {} destroyed", proto_id);
            }
            _ => {}
        }
    }
}

/// Register zwp_idle_inhibit_manager_v1 global
pub fn register_idle_inhibit_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpIdleInhibitManagerV1, ()>(1, ())
}
