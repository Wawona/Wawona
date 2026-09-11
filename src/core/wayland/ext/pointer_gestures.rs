//! WP Pointer Gestures protocol implementation.
//!
//! This protocol provides multi-touch gesture events:
//! - Swipe: Multi-finger swipe gestures
//! - Pinch: Two-finger pinch/zoom gestures
//! - Hold: Press and hold gestures (v3+)

use std::collections::HashMap;
use wayland_protocols::wp::pointer_gestures::zv1::server::{
    zwp_pointer_gesture_pinch_v1::{self, ZwpPointerGesturePinchV1},
    zwp_pointer_gesture_swipe_v1::{self, ZwpPointerGestureSwipeV1},
    zwp_pointer_gestures_v1::{self, ZwpPointerGesturesV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with swipe gesture
#[derive(Debug, Clone)]
pub struct SwipeGestureData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub resource: ZwpPointerGestureSwipeV1,
}

/// Data stored with pinch gesture
#[derive(Debug, Clone)]
pub struct PinchGestureData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub resource: ZwpPointerGesturePinchV1,
}

/// State for pointer gestures
#[derive(Debug, Default)]
pub struct PointerGesturesState {
    pub swipe_gestures: HashMap<u32, SwipeGestureData>,
    pub pinch_gestures: HashMap<u32, PinchGestureData>,
}

impl PointerGesturesState {
    pub fn broadcast_swipe_begin(
        &self,
        surface_id: u32,
        surface: &wayland_server::protocol::wl_surface::WlSurface,
        time: u32,
        fingers: u32,
    ) {
        let serial = CompositorState::get_timestamp_ms();
        for swipe in self.swipe_gestures.values() {
            if swipe.surface_id == surface_id {
                swipe.resource.begin(serial, time, surface, fingers);
            }
        }
    }

    pub fn broadcast_swipe_update(&self, surface_id: u32, time: u32, dx: f64, dy: f64) {
        for swipe in self.swipe_gestures.values() {
            if swipe.surface_id == surface_id {
                swipe.resource.update(time, dx, dy);
            }
        }
    }

    pub fn broadcast_swipe_end(&self, surface_id: u32, time: u32, cancelled: bool) {
        let serial = CompositorState::get_timestamp_ms();
        for swipe in self.swipe_gestures.values() {
            if swipe.surface_id == surface_id {
                swipe
                    .resource
                    .end(serial, time, if cancelled { 1 } else { 0 });
            }
        }
    }

    pub fn broadcast_pinch_begin(
        &self,
        surface_id: u32,
        surface: &wayland_server::protocol::wl_surface::WlSurface,
        time: u32,
        fingers: u32,
    ) {
        let serial = CompositorState::get_timestamp_ms();
        for pinch in self.pinch_gestures.values() {
            if pinch.surface_id == surface_id {
                pinch.resource.begin(serial, time, surface, fingers);
            }
        }
    }

    pub fn broadcast_pinch_update(
        &self,
        surface_id: u32,
        time: u32,
        dx: f64,
        dy: f64,
        scale: f64,
        rotation: f64,
    ) {
        for pinch in self.pinch_gestures.values() {
            if pinch.surface_id == surface_id {
                pinch.resource.update(time, dx, dy, scale, rotation);
            }
        }
    }

    pub fn broadcast_pinch_end(&self, surface_id: u32, time: u32, cancelled: bool) {
        let serial = CompositorState::get_timestamp_ms();
        for pinch in self.pinch_gestures.values() {
            if pinch.surface_id == surface_id {
                pinch
                    .resource
                    .end(serial, time, if cancelled { 1 } else { 0 });
            }
        }
    }
}

// ============================================================================
// zwp_pointer_gestures_v1
// ============================================================================

impl GlobalDispatch<ZwpPointerGesturesV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpPointerGesturesV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_pointer_gestures_v1");
    }
}

impl Dispatch<ZwpPointerGesturesV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpPointerGesturesV1,
        request: zwp_pointer_gestures_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_pointer_gestures_v1::Request::GetSwipeGesture { id, pointer } => {
                let pointer_id = pointer.id().protocol_id();
                let surface_id = state.seat.pointer.focus.unwrap_or(0); // Gestures usually follow focus

                let swipe = data_init.init(id, ());
                let swipe_id = swipe.id().protocol_id();

                let data = SwipeGestureData {
                    surface_id,
                    pointer_id,
                    resource: swipe.clone(),
                };

                state
                    .ext
                    .pointer_gestures
                    .swipe_gestures
                    .insert(swipe_id, data);
                tracing::debug!(
                    "Created swipe gesture for pointer {} on surface {}",
                    pointer_id,
                    surface_id
                );
            }
            zwp_pointer_gestures_v1::Request::GetPinchGesture { id, pointer } => {
                let pointer_id = pointer.id().protocol_id();
                let surface_id = state.seat.pointer.focus.unwrap_or(0);

                let pinch = data_init.init(id, ());
                let pinch_id = pinch.id().protocol_id();

                let data = PinchGestureData {
                    surface_id,
                    pointer_id,
                    resource: pinch.clone(),
                };

                state
                    .ext
                    .pointer_gestures
                    .pinch_gestures
                    .insert(pinch_id, data);
                tracing::debug!(
                    "Created pinch gesture for pointer {} on surface {}",
                    pointer_id,
                    surface_id
                );
            }
            zwp_pointer_gestures_v1::Request::Release => {
                tracing::debug!("zwp_pointer_gestures_v1 released");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_pointer_gesture_swipe_v1
// ============================================================================

impl Dispatch<ZwpPointerGestureSwipeV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpPointerGestureSwipeV1,
        request: zwp_pointer_gesture_swipe_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_pointer_gesture_swipe_v1::Request::Destroy => {
                state
                    .ext
                    .pointer_gestures
                    .swipe_gestures
                    .remove(&resource.id().protocol_id());
                tracing::debug!("Swipe gesture destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_pointer_gesture_pinch_v1
// ============================================================================

impl Dispatch<ZwpPointerGesturePinchV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpPointerGesturePinchV1,
        request: zwp_pointer_gesture_pinch_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_pointer_gesture_pinch_v1::Request::Destroy => {
                state
                    .ext
                    .pointer_gestures
                    .pinch_gestures
                    .remove(&resource.id().protocol_id());
                tracing::debug!("Pinch gesture destroyed");
            }
            _ => {}
        }
    }
}

/// Register zwp_pointer_gestures_v1 global
pub fn register_pointer_gestures(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    // Version 3 adds hold gesture, but we'll start with v1
    display.create_global::<CompositorState, ZwpPointerGesturesV1, ()>(1, ())
}
