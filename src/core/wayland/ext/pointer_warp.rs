//! Pointer Warp protocol implementation.
//!
//! Allows clients to request pointer position changes. The compositor
//! moves the pointer to the requested coordinates relative to the surface,
//! then sends normal pointer motion events to all affected surfaces.

use wayland_protocols::wp::pointer_warp::v1::server::wp_pointer_warp_v1::{self, WpPointerWarpV1};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

impl GlobalDispatch<WpPointerWarpV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpPointerWarpV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_pointer_warp_v1");
    }
}

impl Dispatch<WpPointerWarpV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpPointerWarpV1,
        request: wp_pointer_warp_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_pointer_warp_v1::Request::WarpPointer {
                surface,
                x,
                y,
                pointer: _,
                serial: _,
            } => {
                let surface_id = surface.id().protocol_id();

                // Convert surface-local coordinates to absolute by finding the surface position
                let mut abs_x = x as f64;
                let mut abs_y = y as f64;

                // Look up the surface's window to get its absolute position
                if let Some(&window_id) = state.surface_to_window.get(&surface_id) {
                    if let Some(window) = state.get_window(window_id) {
                        let window = window.read().unwrap();
                        abs_x += window.x as f64;
                        abs_y += window.y as f64;
                    }
                }

                // Move the pointer using the standard motion path (handles focus changes)
                let time = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis() as u32)
                    .unwrap_or(0);

                state.inject_pointer_motion_absolute(abs_x, abs_y, time);
                tracing::debug!(
                    "Pointer warped to surface {} ({}, {}) → absolute ({:.0}, {:.0})",
                    surface_id,
                    x,
                    y,
                    abs_x,
                    abs_y
                );
            }
            wp_pointer_warp_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_pointer_warp(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpPointerWarpV1, ()>(1, ())
}
