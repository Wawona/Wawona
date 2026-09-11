//! WP Relative Pointer protocol implementation.
//!
//! This protocol provides relative pointer motion events, essential for:
//! - First-person games and 3D applications
//! - CAD software with infinite panning
//! - Any application needing raw pointer motion

use wayland_protocols::wp::relative_pointer::zv1::server::{
    zwp_relative_pointer_manager_v1::{self, ZwpRelativePointerManagerV1},
    zwp_relative_pointer_v1::{self, ZwpRelativePointerV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with each relative pointer
#[derive(Debug, Clone)]
pub struct RelativePointerData {
    /// Associated wl_pointer
    pub pointer_id: u32,
}

impl RelativePointerData {
    pub fn new(pointer_id: u32) -> Self {
        Self { pointer_id }
    }
}

#[derive(Debug, Default)]
pub struct RelativePointerState {
    /// Relative pointer resources (relative_pointer_id -> resource)
    pub relative_pointers: HashMap<u32, ZwpRelativePointerV1>,
}

impl RelativePointerState {
    pub fn broadcast_relative_motion(
        &self,
        _pointer_id: u32,
        time_hi: u32,
        time_lo: u32,
        dx: f64,
        dy: f64,
        dx_unaccel: f64,
        dy_unaccel: f64,
    ) {
        for rel_ptr in self.relative_pointers.values() {
            // In a real implementation we'd check if this relative pointer
            // corresponds to the pointer_id that moved.
            // For now we broadcast to all as we usually only have one seat/pointer.
            rel_ptr.relative_motion(time_hi, time_lo, dx, dy, dx_unaccel, dy_unaccel);
        }
    }
}

// ============================================================================
// zwp_relative_pointer_manager_v1
// ============================================================================

impl GlobalDispatch<ZwpRelativePointerManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpRelativePointerManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_relative_pointer_manager_v1");
    }
}

impl Dispatch<ZwpRelativePointerManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpRelativePointerManagerV1,
        request: zwp_relative_pointer_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_relative_pointer_manager_v1::Request::GetRelativePointer { id, pointer } => {
                let pointer_id = pointer.id().protocol_id();
                // let rel_pointer_data = RelativePointerData::new(pointer_id);
                let rel_pointer = data_init.init(id, ());
                let rel_id = rel_pointer.id().protocol_id();
                state
                    .ext
                    .relative_pointers
                    .relative_pointers
                    .insert(rel_id, rel_pointer.clone());

                tracing::debug!("Created relative pointer for pointer {}", pointer_id);
            }
            zwp_relative_pointer_manager_v1::Request::Destroy => {
                tracing::debug!("zwp_relative_pointer_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_relative_pointer_v1
// ============================================================================

impl Dispatch<ZwpRelativePointerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpRelativePointerV1,
        request: zwp_relative_pointer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_relative_pointer_v1::Request::Destroy => {
                let id = resource.id().protocol_id();
                state.ext.relative_pointers.relative_pointers.remove(&id);
                tracing::debug!("Relative pointer {} destroyed", id);
            }
            _ => {}
        }
    }
}

/// Register zwp_relative_pointer_manager_v1 global
pub fn register_relative_pointer_manager(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpRelativePointerManagerV1, ()>(1, ())
}

// Helper to send relative motion would go here
// The actual sending is done when the compositor has pointer motion to report
