//! XWayland Keyboard Grab protocol implementation.
//!
//! Allows XWayland to grab keyboard input for a surface. When a grab is
//! active, keyboard events are exclusively delivered to the grabbed surface.

use std::collections::HashMap;
use wayland_protocols::xwayland::keyboard_grab::zv1::server::{
    zwp_xwayland_keyboard_grab_manager_v1::{self, ZwpXwaylandKeyboardGrabManagerV1},
    zwp_xwayland_keyboard_grab_v1::{self, ZwpXwaylandKeyboardGrabV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// Compositor-wide XWayland keyboard grab state
#[derive(Debug, Default)]
pub struct XwaylandKeyboardGrabState {
    /// Active grabs: grab_id → surface_id
    pub grabs: HashMap<u32, u32>,
}

impl XwaylandKeyboardGrabState {
    /// Check if any surface currently has an active keyboard grab
    pub fn is_grabbed(&self) -> bool {
        !self.grabs.is_empty()
    }

    /// Get the surface ID that currently has the keyboard grab (if any)
    pub fn grabbed_surface(&self) -> Option<u32> {
        self.grabs.values().next().copied()
    }
}

impl GlobalDispatch<ZwpXwaylandKeyboardGrabManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpXwaylandKeyboardGrabManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_xwayland_keyboard_grab_manager_v1");
    }
}

impl Dispatch<ZwpXwaylandKeyboardGrabManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpXwaylandKeyboardGrabManagerV1,
        request: zwp_xwayland_keyboard_grab_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_xwayland_keyboard_grab_manager_v1::Request::GrabKeyboard {
                id,
                surface,
                seat: _,
            } => {
                let surface_id = surface.id().protocol_id();
                let grab = data_init.init(id, surface_id);
                let grab_id = grab.id().protocol_id();

                state
                    .ext
                    .xwayland_keyboard_grab
                    .grabs
                    .insert(grab_id, surface_id);
                tracing::info!(
                    "XWayland keyboard grab {} for surface {}",
                    grab_id,
                    surface_id
                );
            }
            zwp_xwayland_keyboard_grab_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZwpXwaylandKeyboardGrabV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpXwaylandKeyboardGrabV1,
        request: zwp_xwayland_keyboard_grab_v1::Request,
        _surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_xwayland_keyboard_grab_v1::Request::Destroy => {
                let grab_id = resource.id().protocol_id();
                state.ext.xwayland_keyboard_grab.grabs.remove(&grab_id);
                tracing::debug!("XWayland keyboard grab {} released", grab_id);
            }
            _ => {}
        }
    }
}

pub fn register_xwayland_keyboard_grab(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpXwaylandKeyboardGrabManagerV1, ()>(1, ())
}
