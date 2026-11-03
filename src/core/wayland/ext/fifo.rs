//! FIFO protocol implementation.
//!
//! Clients request FIFO buffer presentation ordering. `set_barrier` marks the
//! current content update; the next content update waits until that barrier
//! content has been presented. `wait_barrier` clears the wait once presented.

use std::collections::HashMap;
use wayland_protocols::wp::fifo::v1::server::{
    wp_fifo_manager_v1::{self, WpFifoManagerV1},
    wp_fifo_v1::{self, WpFifoV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

use crate::core::wayland::protocol_proofs::fifo_barrier_blocks_next_commit;

/// Per-surface FIFO barrier state
#[derive(Debug, Clone, Default)]
pub struct FifoState {
    /// surface_id → barrier armed on last set_barrier (not yet presented)
    pub barriers: HashMap<u32, bool>,
    /// surface_id → barrier content has been presented (clears wait)
    pub presented: HashMap<u32, bool>,
}

impl FifoState {
    /// Check if a surface has an active (unpresented) FIFO barrier.
    pub fn has_barrier(&self, surface_id: u32) -> bool {
        let armed = self.barriers.get(&surface_id).copied().unwrap_or(false);
        let presented = self.presented.get(&surface_id).copied().unwrap_or(false);
        fifo_barrier_blocks_next_commit(armed, presented)
    }

    /// Mark barrier content presented (call from presentation path).
    pub fn on_presented(&mut self, surface_id: u32) {
        if self.barriers.get(&surface_id).copied().unwrap_or(false) {
            self.presented.insert(surface_id, true);
        }
    }

    /// Clear barrier after wait or destroy.
    pub fn clear(&mut self, surface_id: u32) {
        self.barriers.insert(surface_id, false);
        self.presented.insert(surface_id, false);
    }
}

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
                state.ext.fifo.clear(surface_id);
                tracing::debug!("Created FIFO for surface {}", surface_id);
            }
            wp_fifo_manager_v1::Request::Destroy => {
                tracing::debug!("wp_fifo_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

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
                state.ext.fifo.presented.insert(*surface_id, false);
                tracing::debug!("FIFO barrier set for surface {}", surface_id);
            }
            wp_fifo_v1::Request::WaitBarrier => {
                // Spec: wait until the barrier content is presented, then clear.
                if state
                    .ext
                    .fifo
                    .presented
                    .get(surface_id)
                    .copied()
                    .unwrap_or(false)
                    || !state
                        .ext
                        .fifo
                        .barriers
                        .get(surface_id)
                        .copied()
                        .unwrap_or(false)
                {
                    state.ext.fifo.clear(*surface_id);
                }
                tracing::debug!("FIFO wait_barrier for surface {}", surface_id);
            }
            wp_fifo_v1::Request::Destroy => {
                state.ext.fifo.barriers.remove(surface_id);
                state.ext.fifo.presented.remove(surface_id);
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn barrier_blocks_until_presented() {
        assert!(fifo_barrier_blocks_next_commit(true, false));
        assert!(!fifo_barrier_blocks_next_commit(true, true));
        assert!(!fifo_barrier_blocks_next_commit(false, false));
    }

    #[test]
    fn on_presented_clears_block() {
        let mut st = FifoState::default();
        st.barriers.insert(3, true);
        st.presented.insert(3, false);
        assert!(st.has_barrier(3));
        st.on_presented(3);
        assert!(!st.has_barrier(3));
    }
}

