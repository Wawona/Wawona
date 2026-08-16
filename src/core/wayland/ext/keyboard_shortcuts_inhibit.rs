//! WP Keyboard Shortcuts Inhibit protocol implementation.
//!
//! This protocol allows clients to inhibit compositor keyboard shortcuts,
//! useful for fullscreen applications and games that need full keyboard control.


use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::keyboard_shortcuts_inhibit::zv1::server::{
    zwp_keyboard_shortcuts_inhibit_manager_v1::{self, ZwpKeyboardShortcutsInhibitManagerV1},
    zwp_keyboard_shortcuts_inhibitor_v1::{self, ZwpKeyboardShortcutsInhibitorV1},
};


use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with keyboard shortcuts inhibitor
#[derive(Debug, Clone)]
pub struct KeyboardShortcutsInhibitorData {
    pub surface_id: u32,
    pub seat_id: u32,
}

impl KeyboardShortcutsInhibitorData {
    pub fn new(surface_id: u32, seat_id: u32) -> Self {
        Self { surface_id, seat_id }
    }
}

use std::collections::HashMap;

#[derive(Debug, Default)]
pub struct KeyboardShortcutsInhibitState {
    /// Map of surface_id -> (seat_id, inhibitor_resource)
    pub inhibitors: HashMap<u32, u32>,
}

impl KeyboardShortcutsInhibitState {
    /// Check if shortcuts are inhibited for the given surface
    pub fn is_inhibited(&self, surface_id: u32) -> bool {
        self.inhibitors.contains_key(&surface_id)
    }

    /// Remove inhibitor for a surface
    pub fn remove_inhibitor(&mut self, surface_id: u32) {
        self.inhibitors.remove(&surface_id);
    }
}


// ============================================================================
// zwp_keyboard_shortcuts_inhibit_manager_v1
// ============================================================================

impl GlobalDispatch<ZwpKeyboardShortcutsInhibitManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpKeyboardShortcutsInhibitManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_keyboard_shortcuts_inhibit_manager_v1");
    }
}

impl Dispatch<ZwpKeyboardShortcutsInhibitManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpKeyboardShortcutsInhibitManagerV1,
        request: zwp_keyboard_shortcuts_inhibit_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_keyboard_shortcuts_inhibit_manager_v1::Request::InhibitShortcuts {
                id,
                surface,
                seat,
            } => {
                let surface_id = surface.id().protocol_id();
                let seat_id = seat.id().protocol_id();
                
                let inhibitor = data_init.init(id, surface_id);
                
                // Register the inhibitor
                state.ext.keyboard_shortcuts_inhibit.inhibitors.insert(surface_id, seat_id);
                
                // Send active event immediately. We always honor the inhibitor
                inhibitor.active();
                
                tracing::debug!(
                    "Keyboard shortcuts inhibited for surface {} on seat {} (active)",
                    surface_id, seat_id
                );
            }
            zwp_keyboard_shortcuts_inhibit_manager_v1::Request::Destroy => {
                tracing::debug!("zwp_keyboard_shortcuts_inhibit_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_keyboard_shortcuts_inhibitor_v1
// ============================================================================

impl Dispatch<ZwpKeyboardShortcutsInhibitorV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpKeyboardShortcutsInhibitorV1,
        request: zwp_keyboard_shortcuts_inhibitor_v1::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let surface_id = *data;
        match request {
            zwp_keyboard_shortcuts_inhibitor_v1::Request::Destroy => {
                state.ext.keyboard_shortcuts_inhibit.remove_inhibitor(surface_id);
                tracing::debug!(
                    "Keyboard shortcuts inhibitor destroyed for surface {}", surface_id
                );
            }
            _ => {}
        }
    }
}

/// Register zwp_keyboard_shortcuts_inhibit_manager_v1 global
pub fn register_keyboard_shortcuts_inhibit_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpKeyboardShortcutsInhibitManagerV1, ()>(1, ())
}
