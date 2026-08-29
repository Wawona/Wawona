//! FIFO protocol implementation.
//!
//! This protocol allows clients to request FIFO (first-in-first-out)
//! buffer presentation ordering. When a barrier is set, the compositor
//! should stall the client's next commit until the previous frame has
//! been presented. When wait_barrier is called, the client blocks.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::fifo::v1::server::{
    wp_fifo_manager_v1::{self, WpFifoManagerV1},
    wp_fifo_v1::{self, WpFifoV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Per-surface FIFO barrier state
#[derive(Debug, Clone, Default)]
pub struct FifoState {
    /// surface_id → whether a barrier is currently set
    pub barriers: HashMap<u32, bool>,
}

impl FifoState {
    /// Check if a surface has an active FIFO barrier
    pub fn has_barrier(&self, surface_id: u32) -> bool {
        self.barriers.get(&surface_id).copied().unwrap_or(false)
    }
}

// ============================================================================
// wp_fifo_manager_v1
// ============================================================================

impl GlobalDispatch<WpFifoManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpFifoManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_fifo_manager_v1");
    }
}

impl Dispatch<WpFifoManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpFifoManagerV1,
        request: wp_fifo_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_fifo_manager_v1::Request::GetFifo { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _fifo = data_init.init(id, surface_id);
                state.ext.fifo.barriers.insert(surface_id, false);
                tracing::debug!("Created FIFO for surface {}", surface_id);
            }
            wp_fifo_manager_v1::Request::Destroy => {
                tracing::debug!("wp_fifo_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_fifo_v1. User data is surface_id: u32
// ============================================================================

impl Dispatch<WpFifoV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpFifoV1,
        request: wp_fifo_v1::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_fifo_v1::Request::SetBarrier => {
                state.ext.fifo.barriers.insert(*surface_id, true);
                tracing::debug!("FIFO barrier set for surface {}", surface_id);
            }
            wp_fifo_v1::Request::WaitBarrier => {
                // The barrier is cleared when the frame is presented.
                // For now, immediately clear it (since we present every frame).
                state.ext.fifo.barriers.insert(*surface_id, false);
                tracing::debug!("FIFO barrier waited (cleared) for surface {}", surface_id);
            }
            wp_fifo_v1::Request::Destroy => {
                state.ext.fifo.barriers.remove(surface_id);
                tracing::debug!("FIFO destroyed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

/// Register wp_fifo_manager_v1 global
pub fn register_fifo(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpFifoManagerV1, ()>(1, ())
}
