use wayland_server::Resource;
use wayland_server::protocol::wl_pointer::{self, WlPointer};
use wayland_server::protocol::wl_surface::WlSurface;

/// Pointer state for a seat, managing position, focus, buttons, and cursor.
#[derive(Debug, Clone, Default)]
pub struct PointerState {
    /// Currently focused surface (internal compositor surface ID)
    pub focus: Option<u32>,
    /// Absolute pointer position in compositor-global coordinates
    pub x: f64,
    pub y: f64,
    /// Surface-local coordinates of the pointer within the focused surface
    pub focus_x: f64,
    pub focus_y: f64,
    /// Number of buttons currently pressed (for implicit grab tracking)
    pub button_count: u32,
    /// Cursor surface ID set by the client via wl_pointer.set_cursor
    pub cursor_surface: Option<u32>,
    /// Cursor hotspot
    pub cursor_hotspot_x: f64,
    pub cursor_hotspot_y: f64,
    /// Named cursor shape from wp_cursor_shape_device_v1 (takes precedence over cursor_surface)
    pub cursor_shape: Option<u32>,
    /// Bound pointer resources from clients
    pub resources: Vec<WlPointer>,
    /// Serial of the most recent wl_pointer.enter sent to the focused client.
    pub last_enter_serial: u32,
    /// Serial of the most recent pointer button event.
    pub last_button_serial: u32,
}

impl PointerState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a pointer resource
    pub fn add_resource(&mut self, pointer: WlPointer) {
        self.resources.push(pointer);
    }

    /// Remove a pointer resource
    pub fn remove_resource(&mut self, resource: &WlPointer) {
        self.resources.retain(|p| p.id() != resource.id());
    }

    /// Update cursor surface and hotspot (from wl_pointer.set_cursor).
    /// Clears any named cursor shape since surface-based cursor takes precedence.
    pub fn set_cursor(&mut self, surface_id: Option<u32>, hotspot_x: f64, hotspot_y: f64) {
        self.cursor_surface = surface_id;
        self.cursor_hotspot_x = hotspot_x;
        self.cursor_hotspot_y = hotspot_y;
        self.cursor_shape = None;
    }

    /// Track button press/release for implicit grab
    pub fn update_button(&mut self, pressed: bool) {
        if pressed {
            self.button_count = self.button_count.saturating_add(1);
        } else {
            self.button_count = self.button_count.saturating_sub(1);
        }
    }

    /// Whether the pointer has an implicit grab (buttons pressed)
    pub fn has_implicit_grab(&self) -> bool {
        self.button_count > 0
    }

    /// Send enter event to pointer resources matching the surface's client
    pub fn broadcast_enter(
        &self,
        serial: u32,
        surface: &WlSurface,
        x: f64,
        y: f64,
    ) {
        let client = surface.client();
        for ptr in &self.resources {
            if ptr.client() == client {
                ptr.enter(serial, surface, x, y);
            }
        }
    }

    /// Send leave event to pointer resources matching the surface's client
    pub fn broadcast_leave(&self, serial: u32, surface: &WlSurface) {
        let client = surface.client();
        for ptr in &self.resources {
            if ptr.client() == client {
                ptr.leave(serial, surface);
            }
        }
    }

    /// Send motion event to focused client's pointer resources
    pub fn broadcast_motion(
        &self,
        time: u32,
        x: f64,
        y: f64,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for ptr in &self.resources {
                if ptr.client().as_ref() == Some(focused) {
                    ptr.motion(time, x, y);
                }
            }
        }
    }

    /// Send button event to focused client's pointer resources
    pub fn broadcast_button(
        &self,
        serial: u32,
        time: u32,
        button: u32,
        state: wl_pointer::ButtonState,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for ptr in &self.resources {
                if ptr.client().as_ref() == Some(focused) {
                    ptr.button(serial, time, button, state);
                }
            }
        }
    }

    /// Send frame event to focused client's pointer resources
    pub fn broadcast_frame(&self, focused_client: Option<&wayland_server::Client>) {
        if let Some(focused) = focused_client {
            for ptr in &self.resources {
                if ptr.client().as_ref() == Some(focused) {
                    ptr.frame();
                }
            }
        }
    }

    /// Send axis event to focused client's pointer resources
    pub fn broadcast_axis(
        &self,
        time: u32,
        axis: wl_pointer::Axis,
        value: f64,
        source: wl_pointer::AxisSource,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for ptr in &self.resources {
                if ptr.client().as_ref() == Some(focused) {
                    if ptr.version() >= 5 {
                        ptr.axis_source(source);
                    }
                    ptr.axis(time, axis, value);
                }
            }
        }
    }

    /// Clean up dead pointer resources
    pub fn cleanup_resources(&mut self) {
        let before = self.resources.len();
        self.resources.retain(|p| p.is_alive());
        if before != self.resources.len() {
            crate::wlog!(
                crate::util::logging::SEAT,
                "Cleaned up {} dead pointers",
                before - self.resources.len()
            );
        }
    }
}
