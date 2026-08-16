//! XDG Toplevel Drag protocol implementation.
//!
//! This protocol allows clients to initiate drag operations that move
//! entire toplevels with the pointer during a wl_data_device drag.
//! The attached toplevel follows the cursor at the specified offset.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::toplevel_drag::v1::server::{
    xdg_toplevel_drag_v1::{self, XdgToplevelDragV1},
    xdg_toplevel_drag_manager_v1::{self, XdgToplevelDragManagerV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// State for an active toplevel drag. Stored in the drag itself
#[derive(Debug, Clone)]
pub struct ToplevelDragAttachment {
    /// The toplevel resource ID being dragged
    pub toplevel_id: u32,
    /// The window ID of the toplevel (for position updates)
    pub window_id: Option<u32>,
    /// Offset from cursor to toplevel origin
    pub x_offset: i32,
    pub y_offset: i32,
}

/// Compositor-wide toplevel drag state
#[derive(Debug, Default)]
pub struct ToplevelDragState {
    /// Currently active toplevel drag attachment (set on Attach, cleared on drop/destroy)
    pub active: Option<ToplevelDragAttachment>,
}

// ============================================================================
// xdg_toplevel_drag_manager_v1
// ============================================================================

impl GlobalDispatch<XdgToplevelDragManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgToplevelDragManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xdg_toplevel_drag_manager_v1");
    }
}

impl Dispatch<XdgToplevelDragManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgToplevelDragManagerV1,
        request: xdg_toplevel_drag_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_toplevel_drag_manager_v1::Request::GetXdgToplevelDrag { id, data_source } => {
                let source_id = data_source.id().protocol_id();
                let _drag = data_init.init(id, source_id);
                tracing::debug!("Created toplevel drag for data source {}", source_id);
            }
            xdg_toplevel_drag_manager_v1::Request::Destroy => {
                tracing::debug!("xdg_toplevel_drag_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// xdg_toplevel_drag_v1. User data is source_id: u32
// ============================================================================

impl Dispatch<XdgToplevelDragV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &XdgToplevelDragV1,
        request: xdg_toplevel_drag_v1::Request,
        _source_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_toplevel_drag_v1::Request::Attach { toplevel, x_offset, y_offset } => {
                let toplevel_id = toplevel.id().protocol_id();
                let client_id = _client.id();

                // Resolve toplevel to window ID
                let window_id = state.xdg.toplevels.get(&(client_id, toplevel_id))
                    .and_then(|td| {
                        state.surface_to_window.get(&td.surface_id).copied()
                    });

                state.xdg.toplevel_drag.active = Some(ToplevelDragAttachment {
                    toplevel_id,
                    window_id,
                    x_offset,
                    y_offset,
                });

                tracing::info!(
                    "Attached toplevel {} (window {:?}) to drag at offset ({}, {})",
                    toplevel_id, window_id, x_offset, y_offset
                );
            }
            xdg_toplevel_drag_v1::Request::Destroy => {
                state.xdg.toplevel_drag.active = None;
                tracing::debug!("xdg_toplevel_drag_v1 destroyed");
            }
            _ => {}
        }
    }
}

/// Register xdg_toplevel_drag_manager_v1 global
pub fn register_xdg_toplevel_drag(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XdgToplevelDragManagerV1, ()>(1, ())
}
