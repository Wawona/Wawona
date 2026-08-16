use std::sync::Arc;
use wayland_server::protocol::wl_keyboard::WlKeyboard;
use wayland_server::protocol::wl_pointer::WlPointer;
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::protocol::wl_touch::WlTouch;

use super::keyboard::KeyboardState;
use super::pointer::PointerState;
use super::touch::TouchState;
use super::xkb::XkbContext;

/// A Wayland seat aggregating keyboard, pointer, and touch input devices.
///
/// Following Smithay's pattern, the Seat owns its sub-device states and
/// provides a unified interface for the compositor.
#[derive(Debug)]
pub struct Seat {
    /// Seat name (sent to clients via wl_seat.name)
    pub name: String,
    /// Keyboard sub-state
    pub keyboard: KeyboardState,
    /// Pointer sub-state
    pub pointer: PointerState,
    /// Touch sub-state
    pub touch: TouchState,
    /// Active popup grab stack (protocol IDs)
    pub popup_grab_stack: Vec<u32>,
    /// Clipboard selection source (kept here for seat-level clipboard)
    pub current_selection: Option<crate::core::state::SelectionSource>,
}

impl Seat {
    pub fn new(name: &str) -> Self {
        let xkb_context = Arc::new(XkbContext::new());
        Self {
            name: name.to_string(),
            keyboard: KeyboardState::new(xkb_context),
            pointer: PointerState::new(),
            touch: TouchState::new(),
            popup_grab_stack: Vec::new(),
            current_selection: None,
        }
    }

    /// Seat capabilities bitmask for wl_seat.capabilities
    pub fn capabilities(&self) -> u32 {
        use wayland_server::protocol::wl_seat::Capability;
        let mut caps = Capability::empty();
        caps |= Capability::Pointer;
        caps |= Capability::Keyboard;
        // Touch is always advertised. The platform injects touch events when supported
        caps |= Capability::Touch;
        caps.bits()
    }

    /// Add a pointer resource
    pub fn add_pointer(&mut self, pointer: WlPointer) {
        self.pointer.add_resource(pointer);
    }

    /// Add a keyboard resource, sending current keymap
    pub fn add_keyboard(&mut self, keyboard: WlKeyboard, serial: u32) {
        self.keyboard.add_resource(keyboard, serial);
    }

    /// Add a touch resource
    pub fn add_touch(&mut self, touch: WlTouch) {
        self.touch.add_resource(touch);
    }

    /// Remove a keyboard resource
    pub fn remove_keyboard(&mut self, resource: &WlKeyboard) {
        self.keyboard.remove_resource(resource);
    }

    /// Remove a touch resource
    pub fn remove_touch(&mut self, resource: &WlTouch) {
        self.touch.remove_resource(resource);
    }

    /// Focus a surface for keyboard input. Sends leave to old and enter to new.
    pub fn set_keyboard_focus(
        &mut self,
        serial: u32,
        new_surface: Option<(&WlSurface, u32)>,
        surfaces: &std::collections::HashMap<u32, crate::core::surface::surface::Surface>,
    ) {
        let old_focus = self.keyboard.focus;

        if let Some(old_id) = old_focus {
            if let Some(old_surface) = surfaces.get(&old_id) {
                if let Some(ref wl) = old_surface.resource {
                    self.keyboard.broadcast_leave(serial, wl);
                }
            }
        }

        if let Some((wl_surface, surface_id)) = new_surface {
            self.keyboard.focus = Some(surface_id);
            // Clone pressed_keys to avoid borrow conflict
            let keys = self.keyboard.pressed_keys.clone();
            self.keyboard.broadcast_enter(serial, wl_surface, &keys);
        } else {
            self.keyboard.focus = None;
        }
    }

    /// Clean up all dead resources across keyboard, pointer, and touch
    pub fn cleanup_resources(&mut self) {
        self.keyboard.cleanup_resources();
        self.pointer.cleanup_resources();
        self.touch.cleanup_resources();
    }
}
