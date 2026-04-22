//! wl_seat protocol implementation.
//!
//! The seat is the primary abstraction for input devices. It represents
//! a collection of input devices (keyboard, pointer, touch) that are
//! logically grouped together.

use wayland_server::{
    protocol::{wl_seat, wl_pointer, wl_keyboard, wl_touch},
    Dispatch, Resource, DisplayHandle, GlobalDispatch,
};

use crate::core::state::CompositorState;
use crate::core::surface::SurfaceRole;

/// Seat global data
pub struct SeatGlobal {
    pub name: String,
}

impl Default for SeatGlobal {
    fn default() -> Self {
        Self {
            name: "seat0".to_string(),
        }
    }
}

// ============================================================================
// wl_seat
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ GlobalDispatch<wl_seat::WlSeat, SeatGlobal> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wl_seat::WlSeat>,
        global_data: &SeatGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let seat = data_init.init(resource, ());
        crate::wlog!(crate::util::logging::SEAT, "DEBUG: Seat Bind Called for client {:?}", _client.id());
        state.seat_resources.insert(seat.id().protocol_id(), seat.clone());

        // Send capabilities (touch only when touch support is active).
        let mut caps = wl_seat::Capability::Pointer | wl_seat::Capability::Keyboard;
        if !state.seat.touch.resources.is_empty() || !state.seat.touch.active_points.is_empty() {
            caps |= wl_seat::Capability::Touch;
        }
        seat.capabilities(caps);
        
        // Send name (version 2+)
        if seat.version() >= 2 {
            seat.name(global_data.name.clone());
        }
        
        tracing::debug!("Bound wl_seat with pointer+keyboard capabilities");
    }
}

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<wl_seat::WlSeat, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_seat::WlSeat,
        request: wl_seat::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_seat::Request::GetPointer { id } => {
                let pointer = data_init.init(id, ());
                tracing::debug!("Created wl_pointer");
                
                state.seat.add_pointer(pointer);
            }
            wl_seat::Request::GetKeyboard { id } => {
                let keyboard = data_init.init(id, ());
                crate::wlog!(crate::util::logging::SEAT, "Created wl_keyboard resource");
                
                let serial = state.next_serial();
                state.seat.add_keyboard(keyboard, serial);
                crate::wlog!(crate::util::logging::SEAT, "Added keyboard to seat (total: {})", 
                    state.seat.keyboard.resources.len());
            }
            wl_seat::Request::GetTouch { id } => {
                let touch = data_init.init(id, ());
                tracing::debug!("Created wl_touch");
                state.seat.add_touch(touch);
            }
            wl_seat::Request::Release => {
                state.seat_resources.remove(&resource.id().protocol_id());
                tracing::debug!("wl_seat released");
            }
            _ => {}
        }
    }
}


// ============================================================================
// Helpers
// ============================================================================


// ============================================================================
// wl_keyboard
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<wl_keyboard::WlKeyboard, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_keyboard::WlKeyboard,
        request: wl_keyboard::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_keyboard::Request::Release => {
                state.seat.remove_keyboard(resource);
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_touch
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<wl_touch::WlTouch, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_touch::WlTouch,
        request: wl_touch::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_touch::Request::Release => {
                state.seat.remove_touch(resource);
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_pointer
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<wl_pointer::WlPointer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_pointer::WlPointer,
        request: wl_pointer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
             wl_pointer::Request::SetCursor { serial, surface, hotspot_x, hotspot_y } => {
                // wl_pointer.set_cursor is only valid for the latest enter serial.
                if serial != state.seat.pointer.last_enter_serial {
                    tracing::debug!(
                        "Ignoring set_cursor with stale serial {} (latest enter serial {})",
                        serial,
                        state.seat.pointer.last_enter_serial
                    );
                    return;
                }

                let mut internal_surface_id = None;
                if let Some(surface) = surface {
                    // The cursor surface must belong to the focused client.
                    if let Some(focus_id) = state.seat.pointer.focus {
                        let focus_client_id = state
                            .get_surface(focus_id)
                            .and_then(|s| s.read().ok()?.resource.as_ref().and_then(|r| r.client()))
                            .map(|c| c.id());
                        let cursor_client_id = surface.client().map(|c| c.id());
                        if focus_client_id != cursor_client_id {
                            resource.post_error(
                                wl_pointer::Error::Role,
                                "set_cursor surface must belong to focused client",
                            );
                            return;
                        }
                    }

                    let protocol_id = surface.id().protocol_id();
                    let mapped = state
                        .protocol_to_internal_surface
                        .get(&(_client.id(), protocol_id))
                        .copied()
                        .unwrap_or(protocol_id);

                    // Cursor surface must have either no role yet or cursor role.
                    if let Some(surface_ref) = state.get_surface(mapped) {
                        let mut surface_state = surface_ref.write().unwrap();
                        if let Err(err) = surface_state.set_role(SurfaceRole::Cursor) {
                            resource.post_error(
                                wl_pointer::Error::Role,
                                format!("cursor surface role conflict: {}", err),
                            );
                            return;
                        }
                    }

                    internal_surface_id = Some(mapped);
                }

                state.seat.pointer.set_cursor(
                    internal_surface_id,
                    hotspot_x as f64,
                    hotspot_y as f64,
                );

                if let Some(sid) = internal_surface_id {
                    tracing::debug!("Seat cursor set to surface {} at ({}, {})", sid, hotspot_x, hotspot_y);
                } else {
                    tracing::debug!("Seat cursor hidden");
                }
             }
             wl_pointer::Request::Release => {
                state.seat.pointer.resources.retain(|p| p.id() != resource.id());
             }
             _ => {}
        }
    }
}

