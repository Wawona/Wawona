//! Legacy cursor tracking for Smithay seats.
//!
//! wl_pointer client requests are handled by `smithay::delegate_seat!`.
//! Do not add a custom `Dispatch<WlPointer>` here — it breaks Smithay's
//! pointer handle and prevents Weston from receiving motion/button events.

use smithay::input::pointer::CursorImageStatus;
use smithay::input::Seat;
use wayland_server::Resource;

use crate::core::state::CompositorState;

impl CompositorState {
    pub(crate) fn track_cursor_image(&mut self, image: &CursorImageStatus) {
        match image {
            CursorImageStatus::Named(name) => {
                self.seat.pointer.cursor_shape = Some(*name as u32);
                self.seat.pointer.cursor_surface = None;
            }
            CursorImageStatus::Surface(surface) => {
                let surface_id = surface.id().protocol_id();
                self.seat.pointer.cursor_surface = Some(surface_id);
                self.seat.pointer.cursor_shape = None;
            }
            CursorImageStatus::Hidden => {
                self.seat.pointer.cursor_surface = None;
                self.seat.pointer.cursor_shape = None;
            }
            _ => {}
        }
    }
}

pub(crate) fn on_cursor_image(
    state: &mut CompositorState,
    _seat: &Seat<CompositorState>,
    image: CursorImageStatus,
) {
    state.track_cursor_image(&image);
}
