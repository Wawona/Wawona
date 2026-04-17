//! Global compositor state.
//!
//! This module contains the `CompositorState` struct which holds all the
//! "business logic" state of the compositor, separate from the Wayland
//! protocol mechanics or the platform UI.
//!
//! The state is designed to be:
//! - Thread-safe (accessed via Arc<RwLock<CompositorState>>)
//! - Serializable for debugging
//! - Decoupled from Wayland protocol types where possible

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use crate::core::input::xkb::{XkbContext, XkbState};
use crate::core::input::keyboard::KeyboardState;
use crate::core::input::pointer::PointerState;
use crate::core::input::touch::TouchState;

use wayland_server::Resource;

use wayland_server::protocol::wl_callback::WlCallback;
use wayland_server::backend::{ClientData, ClientId, DisconnectReason};



use crate::core::surface::Surface;
use crate::core::window::{Window, DecorationMode};
use crate::core::window::tree::WindowTree;
use crate::core::window::focus::FocusManager;

use crate::core::compositor::CompositorEvent;

use crate::core::wayland::protocol::server::xdg::shell::server::{
    xdg_surface, xdg_toplevel, xdg_popup, xdg_wm_base,
};



use crate::core::wayland::ext::pointer_constraints::PointerConstraintsState;
use crate::core::wayland::ext::relative_pointer::RelativePointerState;
use crate::core::wayland::ext::pointer_gestures::PointerGesturesState;
use crate::core::wayland::ext::viewporter::{ViewportData, ViewporterState};
use crate::core::wayland::wlr::export_dmabuf::{DmabufExportFrame, ExportDmabufState};

use crate::core::wayland::ext::presentation_time::PresentationState;
use crate::core::wayland::ext::linux_dmabuf::LinuxDmabufState;
use crate::core::wayland::ext::idle_inhibit::IdleInhibitState;
use crate::core::wayland::ext::keyboard_shortcuts_inhibit::KeyboardShortcutsInhibitState;

use crate::core::wayland::xdg::xdg_activation::ActivationState;
use crate::core::wayland::xdg::xdg_foreign::XdgForeignState;

use crate::core::render::scene::Scene;
use crate::core::render::damage::SceneDamage;
use crate::core::render::node::SceneNode;
use crate::ffi::types::ContentRect;
use crate::core::wayland::xdg::xdg_output::XdgOutputState;
use crate::core::wayland::xdg::decoration::DecorationState;

use crate::core::wayland::wlr::data_control::DataControlState;
use crate::core::wayland::wlr::screencopy::PendingScreencopy;

use crate::core::wayland::wlr::virtual_pointer::VirtualPointerState;
use crate::core::wayland::wlr::virtual_keyboard::VirtualKeyboardState;

use crate::core::wayland::ext::data_device::DataDeviceState;
#[cfg(feature = "desktop-protocols")]
use crate::core::wayland::ext::linux_drm_syncobj::SyncObjState;
#[cfg(feature = "desktop-protocols")]
use crate::core::wayland::ext::drm_lease::DrmLeaseState;

use crate::core::traits::ProtocolState;

// Sub-modules containing extracted CompositorState impl blocks
mod scene;
mod input;
mod surfaces;
mod windows;

// ============================================================================
// Subsurface State
// ============================================================================

/// Subsurface tracking information
#[derive(Debug, Clone)]
pub struct SubsurfaceState {
    /// Surface ID of the subsurface
    pub surface_id: u32,
    /// Parent surface ID
    pub parent_id: u32,
    /// Position relative to parent
    pub position: (i32, i32),
    /// Pending position (before commit)
    pub pending_position: (i32, i32),
    /// Whether in synchronized mode
    pub sync: bool,
    /// Z-order relative to siblings (higher = on top)
    pub z_order: i32,
}

// ============================================================================
// SHM Pool State (for buffer pixel access)
// ============================================================================

use std::os::unix::io::{AsRawFd, OwnedFd};

/// Shared memory pool for SHM buffer pixel data
pub struct ShmPool {
    /// File descriptor for the pool (owned - keeps fd alive!)
    pub fd: OwnedFd,
    /// Size of the pool in bytes
    pub size: usize,
    /// mmap'd data pointer (None until first access)
    pub data: Option<*mut u8>,
}

impl ShmPool {
    /// Create a new SHM pool from file descriptor
    pub fn new(fd: OwnedFd, size: i32) -> Self {
        Self {
            fd,  // Store the OwnedFd directly to keep it alive
            size: size as usize,
            data: None,
        }
    }
    
    /// mmap the pool and return pointer to data
    pub fn map(&mut self) -> Option<*mut u8> {
        if self.data.is_some() {
            return self.data;
        }
        
        // SAFETY: mmap the file descriptor (read+write for compositor read and screencopy write)
        unsafe {
            let ptr = libc::mmap(
                std::ptr::null_mut(),
                self.size,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                self.fd.as_raw_fd(),
                0,
            );
            
            if ptr == libc::MAP_FAILED {
                tracing::error!("Failed to mmap SHM pool (fd={}, size={})", self.fd.as_raw_fd(), self.size);
                return None;
            }
            
            self.data = Some(ptr as *mut u8);
            self.data
        }
    }

    /// Resize the pool
    pub fn resize(&mut self, new_size: i32) {
        let new_size = new_size as usize;
        if new_size == self.size {
            return;
        }

        // If already mapped, we need to unmap and remap at the new size
        if let Some(ptr) = self.data {
            unsafe {
                libc::munmap(ptr as *mut libc::c_void, self.size);
            }
            self.data = None;
        }

        self.size = new_size;
        
        // We don't mmap immediately here, it will be mapped on the next map() call
        // which usually happens when the compositor tries to access pixels.
        tracing::debug!("Resized SHM pool to {} bytes", self.size);
    }
}

impl Drop for ShmPool {
    fn drop(&mut self) {
        if let Some(ptr) = self.data {
            unsafe {
                libc::munmap(ptr as *mut libc::c_void, self.size);
            }
        }
    }
}

// Safety: ShmPool manages an mmap region. We wrap access with RwLock in state.
unsafe impl Send for ShmPool {}
unsafe impl Sync for ShmPool {}

// ============================================================================
// Layer Shell State
// ============================================================================

/// Layer surface state (wlr-layer-shell-unstable-v1)
#[derive(Debug, Clone)]
pub struct LayerSurface {
    /// Associated surface ID
    pub surface_id: u32,
    /// Associated output ID
    pub output_id: u32,
    /// Layer (background, bottom, top, overlay)
    pub layer: u32,
    /// Namespace
    pub namespace: String,
    /// Anchor edges
    pub anchor: u32,
    /// Margin (top, right, bottom, left)
    pub margin: (i32, i32, i32, i32),
    /// Exclusive zone
    pub exclusive_zone: i32,
    /// Keyboard interactivity
    pub interactivity: u32,
    /// Desired width
    pub width: u32,
    /// Desired height
    pub height: u32,
    /// Calculated X position
    pub x: i32,
    /// Calculated Y position
    pub y: i32,
    /// Whether initial configure was acked
    pub configured: bool,
    /// Pending configure serial
    pub pending_serial: u32,
    /// Protocol resource (optional as it might be held in a wrapper)
    pub resource: Option<crate::core::wayland::protocol::wlroots::wlr_layer_shell_unstable_v1::zwlr_layer_surface_v1::ZwlrLayerSurfaceV1>,
}

impl LayerSurface {
    pub fn new(surface_id: u32, output_id: u32, layer: u32, namespace: String) -> Self {
        Self {
            surface_id,
            output_id,
            layer,
            namespace,
            anchor: 0,
            margin: (0, 0, 0, 0),
            exclusive_zone: 0,
            interactivity: 0,
            width: 0,
            height: 0,
            x: 0,
            y: 0,
            configured: false,
            pending_serial: 0,
            resource: None,
        }
    }
}


// ============================================================================
// XDG Shell Data Types
// ============================================================================

/// Data stored with each xdg_surface
#[derive(Debug, Clone)]
pub struct XdgSurfaceData {
    /// The underlying wl_surface ID
    pub surface_id: u32,
    /// Associated window ID (if toplevel)
    pub window_id: Option<u32>,
    /// Serial number for configuration
    pub pending_serial: u32,
    /// Most recently acknowledged configure serial.
    pub last_acked_serial: u32,
    /// Whether initial configure was acked
    pub configured: bool,
    /// The actual protocol resource
    pub resource: Option<xdg_surface::XdgSurface>,
    /// Window geometry from set_window_geometry (content rect for CSD); (x, y, width, height)
    pub geometry: Option<(i32, i32, i32, i32)>,
}

impl XdgSurfaceData {
    pub fn new(surface_id: u32) -> Self {
        Self {
            surface_id,
            window_id: None,
            pending_serial: 0,
            last_acked_serial: 0,
            configured: false,
            resource: None,
            geometry: None,
        }
    }
}

unsafe impl Send for XdgSurfaceData {}
unsafe impl Sync for XdgSurfaceData {}

/// Data stored with each xdg_toplevel
#[derive(Debug, Clone)]
pub struct XdgToplevelData {
    /// Associated window ID
    pub window_id: u32,
    /// Associated wl_surface ID
    pub surface_id: u32,
    /// Associated XDG surface protocol ID
    pub xdg_surface_id: u32,
    /// Title
    pub title: String,
    /// App ID
    pub app_id: String,
    /// Parent toplevel (if any)
    pub parent: Option<u32>,
    /// Current width
    pub width: u32,
    /// Current height
    pub height: u32,
    /// Minimum size constraints (0 means no minimum)
    pub min_width: i32,
    pub min_height: i32,
    /// Maximum size constraints (0 means no maximum)
    pub max_width: i32,
    pub max_height: i32,
    /// Saved geometry before maximize/fullscreen (x, y, width, height)
    pub saved_geometry: Option<(i32, i32, u32, u32)>,
    /// Pending configure serial
    pub pending_serial: u32,
    /// Most recently acknowledged configure serial.
    pub last_acked_serial: u32,
    /// Activation state
    pub activated: bool,
    /// If the window is currently maximized
    pub maximized: bool,
    /// If the window is currently fullscreen
    pub fullscreen: bool,
    /// Pending maximized state
    pub pending_maximized: bool,
    /// Pending fullscreen state
    pub pending_fullscreen: bool,
    /// The actual protocol resource
    pub resource: Option<xdg_toplevel::XdgToplevel>,
}

impl XdgToplevelData {
    pub fn new(window_id: u32, surface_id: u32, xdg_surface_id: u32) -> Self {
        Self {
            window_id,
            surface_id,
            xdg_surface_id,
            title: String::new(),
            app_id: String::new(),
            parent: None,
            width: 0,
            height: 0,
            min_width: 0,
            min_height: 0,
            max_width: 0,
            max_height: 0,
            saved_geometry: None,
            pending_serial: 0,
            last_acked_serial: 0,
            activated: false,
            maximized: false,
            fullscreen: false,
            pending_maximized: false,
            pending_fullscreen: false,
            resource: None,
        }
    }

    /// Clamp a proposed size to the client's min/max constraints.
    /// Returns the clamped (width, height).
    pub fn clamp_size(&self, width: u32, height: u32) -> (u32, u32) {
        let mut w = width;
        let mut h = height;

        if self.min_width > 0 {
            w = w.max(self.min_width as u32);
        }
        if self.min_height > 0 {
            h = h.max(self.min_height as u32);
        }
        if self.max_width > 0 {
            w = w.min(self.max_width as u32);
        }
        if self.max_height > 0 {
            h = h.min(self.max_height as u32);
        }
        (w, h)
    }
}

unsafe impl Send for XdgToplevelData {}
unsafe impl Sync for XdgToplevelData {}

/// Data stored with each xdg_popup
#[derive(Debug, Clone)]
pub struct XdgPopupData {
    pub surface_id: u32,
    pub xdg_surface_id: u32,
    pub window_id: u32,
    pub parent_id: Option<u32>,
    pub geometry: (i32, i32, i32, i32), // x, y, width, height
    pub anchor_rect: (i32, i32, i32, i32),
    pub grabbed: bool,
    pub repositioned_token: Option<u32>,
    /// The actual protocol resource
    pub resource: Option<xdg_popup::XdgPopup>,
}

unsafe impl Send for XdgPopupData {}
unsafe impl Sync for XdgPopupData {}

/// Data stored with each xdg_positioner
#[derive(Debug, Clone, Copy)]
pub struct XdgPositionerData {
    pub width: i32,
    pub height: i32,
    pub anchor_rect: (i32, i32, i32, i32),
    pub anchor: u32, // xdg_positioner::Anchor
    pub gravity: u32, // xdg_positioner::Gravity
    pub constraint_adjustment: u32, // xdg_positioner::ConstraintAdjustment
    pub offset: (i32, i32),
}

impl XdgPositionerData {
    /// Calculate final position relative to parent anchor rect, bounded by output_rect
    pub fn calculate_position(&self, output_rect: crate::util::geometry::Rect) -> (i32, i32) {
        let (ax, ay, aw, ah) = self.anchor_rect;
        let mut x = ax;
        let mut y = ay;

        // 1. Calculate base position from anchor
        if (self.anchor & 4) != 0 { // Left
             // x = ax
        } else if (self.anchor & 8) != 0 { // Right
            x += aw;
        } else { // Center
            x += aw / 2;
        }

        if (self.anchor & 1) != 0 { // Top
            // y = ay
        } else if (self.anchor & 2) != 0 { // Bottom
            y += ah;
        } else { // Center
            y += ah / 2;
        }

        // 2. Apply gravity and offset
        let mut px = x + self.offset.0;
        let mut py = y + self.offset.1;

        if (self.gravity & 4) != 0 { // Left
            px -= self.width;
        } else if (self.gravity & 8) != 0 { // Right
            // px stays
        } else { // Center
            px -= self.width / 2;
        }

        if (self.gravity & 1) != 0 { // Top
            py -= self.height;
        } else if (self.gravity & 2) != 0 { // Bottom
            // py stays
        } else { // Center
            py -= self.height / 2;
        }

        // 3. Apply constraint adjustments (basic Slide and Flip)
        // Adjustments: Slide X(1), Slide Y(2), Flip X(4), Flip Y(8)
        
        // Horizontal adjustment
        if px < output_rect.x {
            if (self.constraint_adjustment & 4) != 0 { // Flip X
                // Simple flip: try mirroring across anchor point
                let flipped_px = x - (px - x) - self.width;
                if flipped_px + self.width <= (output_rect.x + output_rect.width as i32) {
                    px = flipped_px;
                }
            }
            if px < output_rect.x && (self.constraint_adjustment & 1) != 0 { // Slide X
                px = output_rect.x;
            }
        } else if px + self.width > (output_rect.x + output_rect.width as i32) {
            if (self.constraint_adjustment & 4) != 0 { // Flip X
                let flipped_px = x - (px - x) - self.width;
                if flipped_px >= output_rect.x {
                    px = flipped_px;
                }
            }
            if px + self.width > (output_rect.x + output_rect.width as i32) && (self.constraint_adjustment & 1) != 0 { // Slide X
                px = (output_rect.x + output_rect.width as i32) - self.width;
            }
        }

        // Vertical adjustment
        if py < output_rect.y {
            if (self.constraint_adjustment & 8) != 0 { // Flip Y
                let flipped_py = y - (py - y) - self.height;
                if flipped_py + self.height <= (output_rect.y + output_rect.height as i32) {
                    py = flipped_py;
                }
            }
            if py < output_rect.y && (self.constraint_adjustment & 2) != 0 { // Slide Y
                py = output_rect.y;
            }
        } else if py + self.height > (output_rect.y + output_rect.height as i32) {
             if (self.constraint_adjustment & 8) != 0 { // Flip Y
                let flipped_py = y - (py - y) - self.height;
                if flipped_py >= output_rect.y {
                    py = flipped_py;
                }
            }
            if py + self.height > (output_rect.y + output_rect.height as i32) && (self.constraint_adjustment & 2) != 0 { // Slide Y
                py = (output_rect.y + output_rect.height as i32) - self.height;
            }
        }

        (px, py)
    }
}

impl Default for XdgPositionerData {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            anchor_rect: (0, 0, 0, 0),
            anchor: 0,
            gravity: 0,
            constraint_adjustment: 0,
            offset: (0, 0),
        }
    }
}

// ============================================================================
// Subcompositor Data Types
// ============================================================================

/// Per-subsurface data
#[derive(Debug, Clone)]
pub struct SubsurfaceData {
    /// The parent surface ID this subsurface is attached to
    pub parent_id: u32,
    /// Position relative to parent (pending)
    pub pending_position: (i32, i32),
    /// Position relative to parent (committed)
    pub position: (i32, i32),
    /// Whether this subsurface is in synchronized mode
    pub sync: bool,
}

impl SubsurfaceData {
    pub fn new(parent_id: u32) -> Self {
        Self {
            parent_id,
            pending_position: (0, 0),
            position: (0, 0),
            sync: true, // Default is synchronized mode
        }
    }
}




// ============================================================================
// Client State
// ============================================================================

/// Data stored with each Wayland client
#[derive(Default, Clone)]
pub struct ClientState {
    /// Client identifier
    pub id: Option<u32>,
}

impl ClientData for ClientState {
    fn initialized(&self, client_id: ClientId) {
        tracing::info!("Client initialized: {:?}", client_id);
    }
    
    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        let reason_str = match reason {
            DisconnectReason::ConnectionClosed => "connection closed",
            DisconnectReason::ProtocolError(_) => "protocol error",
        };
        tracing::info!("Client disconnected: {:?} ({})", client_id, reason_str);
    }
}

// ============================================================================
// Output State
// ============================================================================

/// Output (display/monitor) state
#[derive(Debug, Clone)]
pub struct OutputMode {
    pub width: u32,
    pub height: u32,
    pub refresh: u32,
    pub preferred: bool,
}

/// Output (display/monitor) state
#[derive(Debug, Clone)]
pub struct OutputState {
    /// Output identifier
    pub id: u32,
    /// Output name
    pub name: String,
    /// Description
    pub description: String,
    /// Manufacturer
    pub make: String,
    /// Model
    pub model: String,
    /// Serial number
    pub serial_number: String,
    /// Position X
    pub x: i32,
    /// Position Y
    pub y: i32,
    /// Physical width in mm
    pub physical_width: u32,
    /// Physical height in mm
    pub physical_height: u32,
    /// Current width in pixels
    pub width: u32,
    /// Current height in pixels
    pub height: u32,
    /// Refresh rate in mHz
    pub refresh: u32,
    /// Scale factor
    pub scale: f32,
    /// List of modes
    pub modes: Vec<OutputMode>,
    /// Power mode (0 = off, 1 = on)
    pub power_mode: u32,
    /// Usable area for windows (output area minus exclusive zones and safe area insets)
    pub usable_area: crate::util::geometry::Rect,
    /// Platform safe area insets (top, right, bottom, left) in pixels.
    /// On iOS these come from `safeAreaInsets` (notch, home indicator, etc.).
    /// These are treated as implicit exclusive zones for layer-shell positioning.
    pub safe_area_insets: (i32, i32, i32, i32),
}

impl OutputState {
    pub fn new(id: u32, name: String, width: u32, height: u32) -> Self {
        let mode = OutputMode {
            width,
            height,
            refresh: 60000,
            preferred: true,
        };
        Self {
            id,
            name: name.clone(),
            description: format!("Virtual Display {}", name),
            make: "Wawona".to_string(),
            model: "Virtual".to_string(),
            serial_number: format!("WAW-{}", id),
            x: 0,
            y: 0,
            // Calculate physical dimensions assuming ~96 DPI for defaults
            // 96 DPI = ~3.78 pixels/mm
            physical_width: (width as f32 / 3.78) as u32,
            physical_height: (height as f32 / 3.78) as u32,
            width,
            height,
            refresh: 60000, // 60Hz
            scale: 1.0,
            modes: vec![mode],
            power_mode: 1, // Default to ON
            usable_area: crate::util::geometry::Rect::new(0, 0, width, height),
            safe_area_insets: (0, 0, 0, 0),
        }
    }

    pub fn update(&mut self, width: u32, height: u32, scale: f32) {
        self.width = width;
        self.height = height;
        self.scale = scale;
        // 96 DPI = ~3.78 pixels/mm
        self.physical_width = (width as f32 / 3.78) as u32;
        self.physical_height = (height as f32 / 3.78) as u32;
        
        // Update or add mode
        if let Some(mode) = self.modes.get_mut(0) {
            mode.width = width;
            mode.height = height;
        } else {
            self.modes.push(OutputMode {
                width,
                height,
                refresh: 60000,
                preferred: true,
            });
        }
    }
}

impl Default for OutputState {
    fn default() -> Self {
        Self::new(0, "default".to_string(), 1920, 1080)
    }
}

// ============================================================================
// Seat State
// ============================================================================

// ============================================================================
// Seat Resources Tracking
// ============================================================================

use wayland_server::protocol::{wl_pointer, wl_keyboard, wl_touch};


use crate::core::wayland::protocol::wlroots::wlr_data_control_unstable_v1::zwlr_data_control_source_v1;

/// Abstract selection source (standard or wlr)
#[derive(Debug, Clone)]
pub enum SelectionSource {
    Wayland(wayland_server::protocol::wl_data_source::WlDataSource),
    Wlr(zwlr_data_control_source_v1::ZwlrDataControlSourceV1),
}

/// Collection of seat resources bound by clients.
/// Delegates to sub-state modules: KeyboardState, PointerState, TouchState.
#[derive(Debug)]
pub struct SeatState {
    /// Seat name
    pub name: String,
    /// Current clipboard selection
    pub current_selection: Option<SelectionSource>,
    /// Keyboard sub-state (focus, pressed keys, XKB, repeat, resources)
    pub keyboard: KeyboardState,
    /// Pointer sub-state (focus, position, buttons, cursor, resources)
    pub pointer: PointerState,
    /// Touch sub-state (active points, resources)
    pub touch: TouchState,
    /// Active popup grab stack (ClientId, protocol_id)
    pub popup_grab_stack: Vec<(wayland_server::backend::ClientId, u32)>,
}

impl Clone for SeatState {
    fn clone(&self) -> Self {
        // SeatState contains non-Clone fields (Wayland resources in sub-states).
        // We create a new default SeatState preserving configuration values.
        Self::new(&self.name)
    }
}

impl Default for SeatState {
    fn default() -> Self {
        Self::new("default")
    }
}

// Backward-compatible accessors that delegate to sub-states.
// These allow existing code to access `seat.pointer_focus`, `seat.keyboards`, etc.
// without changing every call site at once.
impl SeatState {
    // -- Pointer field accessors (delegate to self.pointer) --
    pub fn get_pointer_focus(&self) -> Option<u32> { self.pointer.focus }
    pub fn set_pointer_focus(&mut self, v: Option<u32>) { self.pointer.focus = v; }

    pub fn get_pointer_x(&self) -> f64 { self.pointer.x }
    pub fn get_pointer_y(&self) -> f64 { self.pointer.y }
    pub fn set_pointer_pos(&mut self, x: f64, y: f64) { self.pointer.x = x; self.pointer.y = y; }

    pub fn get_pointer_button_count(&self) -> u32 { self.pointer.button_count }

    pub fn get_cursor_surface(&self) -> Option<u32> { self.pointer.cursor_surface }
    pub fn get_cursor_hotspot(&self) -> (f64, f64) { (self.pointer.cursor_hotspot_x, self.pointer.cursor_hotspot_y) }

    // -- Keyboard field accessors (delegate to self.keyboard) --
    pub fn get_keyboard_focus(&self) -> Option<u32> { self.keyboard.focus }
    pub fn set_keyboard_focus_id(&mut self, v: Option<u32>) { self.keyboard.focus = v; }
    pub fn get_pressed_keys(&self) -> &[u32] { &self.keyboard.pressed_keys }
    pub fn get_mods(&self) -> (u32, u32, u32, u32) {
        (self.keyboard.mods_depressed, self.keyboard.mods_latched, self.keyboard.mods_locked, self.keyboard.mods_group)
    }

    // -- Resource accessors for backward compat --
    pub fn get_pointers(&self) -> &[wl_pointer::WlPointer] { &self.pointer.resources }
    pub fn get_keyboards(&self) -> &[wl_keyboard::WlKeyboard] { &self.keyboard.resources }
    pub fn get_touches(&self) -> &[wl_touch::WlTouch] { &self.touch.resources }

    // -- XKB accessors --
    pub fn get_xkb_context(&self) -> &Arc<XkbContext> { &self.keyboard.xkb_context }
    pub fn get_xkb_state(&self) -> &Option<Arc<std::sync::Mutex<XkbState>>> { &self.keyboard.xkb_state }
}

impl SeatState {
    pub fn new(name: &str) -> Self {
        let xkb_context = Arc::new(XkbContext::new());
        Self {
            name: name.to_string(),
            current_selection: None,
            keyboard: KeyboardState::new(xkb_context),
            pointer: PointerState::new(),
            touch: TouchState::new(),
            popup_grab_stack: Vec::new(),
        }
    }

    /// Add a pointer resource
    pub fn add_pointer(&mut self, pointer: wl_pointer::WlPointer) {
        self.pointer.add_resource(pointer);
    }

    /// Add a keyboard resource
    pub fn add_keyboard(&mut self, keyboard: wl_keyboard::WlKeyboard, serial: u32) {
        self.keyboard.add_resource(keyboard, serial);
    }

    /// Add a touch resource
    pub fn add_touch(&mut self, touch: wl_touch::WlTouch) {
        self.touch.add_resource(touch);
    }

    /// Remove a keyboard resource
    pub fn remove_keyboard(&mut self, resource: &wl_keyboard::WlKeyboard) {
        self.keyboard.remove_resource(resource);
    }

    /// Remove a touch resource
    pub fn remove_touch(&mut self, resource: &wl_touch::WlTouch) {
        self.touch.remove_resource(resource);
    }

    /// Clean up dead resources
    pub fn cleanup_resources(&mut self) {
        self.pointer.cleanup_resources();
        self.keyboard.cleanup_resources();
        self.touch.cleanup_resources();
    }

    // =========================================================================
    // Broadcast methods — delegate to sub-state modules
    // =========================================================================

    pub fn broadcast_pointer_motion(&mut self, time: u32, x: f64, y: f64, focused_client: Option<&wayland_server::Client>) {
        self.pointer.broadcast_motion(time, x, y, focused_client);
    }

    pub fn broadcast_pointer_button(&mut self, serial: u32, time: u32, button: u32, state: wl_pointer::ButtonState, focused_client: Option<&wayland_server::Client>) {
        self.pointer.broadcast_button(serial, time, button, state, focused_client);
    }

    pub fn broadcast_pointer_enter(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface, x: f64, y: f64) {
        self.pointer.broadcast_enter(serial, surface, x, y);
    }

    pub fn broadcast_pointer_leave(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        self.pointer.broadcast_leave(serial, surface);
    }

    pub fn broadcast_pointer_frame(&mut self, focused_client: Option<&wayland_server::Client>) {
        self.pointer.broadcast_frame(focused_client);
    }

    pub fn broadcast_pointer_axis(&mut self, time: u32, axis: wl_pointer::Axis, value: f64, focused_client: Option<&wayland_server::Client>) {
        self.pointer.broadcast_axis(time, axis, value, focused_client);
    }

    pub fn broadcast_key(&mut self, serial: u32, time: u32, key: u32, state: wl_keyboard::KeyState, focused_client: Option<&wayland_server::Client>) {
        self.keyboard.broadcast_key(serial, time, key, state, focused_client);
    }

    pub fn broadcast_modifiers(&mut self, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32, focused_client: Option<&wayland_server::Client>) {
        // Update cached state in keyboard
        self.keyboard.mods_depressed = depressed;
        self.keyboard.mods_latched = latched;
        self.keyboard.mods_locked = locked;
        self.keyboard.mods_group = group;
        self.keyboard.broadcast_modifiers(serial, focused_client);
    }

    pub fn broadcast_keyboard_enter(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface, keys: &[u32]) {
        self.keyboard.broadcast_enter(serial, surface, keys);
    }

    pub fn broadcast_keyboard_leave(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        self.keyboard.broadcast_leave(serial, surface);
    }

    pub fn broadcast_touch_down(&mut self, serial: u32, time: u32, surface: &wayland_server::protocol::wl_surface::WlSurface, id: i32, x: f64, y: f64) {
        self.touch.broadcast_down(serial, time, surface, id, x, y);
    }

    pub fn broadcast_touch_up(&mut self, serial: u32, time: u32, id: i32, focused_client: Option<&wayland_server::Client>) {
        self.touch.broadcast_up(serial, time, id, focused_client);
    }

    pub fn broadcast_touch_motion(&mut self, time: u32, id: i32, x: f64, y: f64, focused_client: Option<&wayland_server::Client>) {
        self.touch.broadcast_motion(time, id, x, y, focused_client);
    }

    pub fn broadcast_touch_frame(&mut self, focused_client: Option<&wayland_server::Client>) {
        self.touch.broadcast_frame(focused_client);
    }

    pub fn broadcast_touch_cancel(&mut self, focused_client: Option<&wayland_server::Client>) {
        self.touch.broadcast_cancel(focused_client);
    }
}

// ============================================================================
// Focus State
// ============================================================================



// ============================================================================
// Frame Callback State
// ============================================================================

/// Pending frame callback
#[derive(Debug)]
pub struct PendingFrameCallback {
    /// Surface ID
    pub surface_id: u32,
    /// Wayland callback object
    pub callback: WlCallback,
    /// Queued time
    pub queued_at: Instant,
}

// ============================================================================
// Decoration State
// ============================================================================

/// Global decoration policy
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecorationPolicy {
    /// Prefer client-side decorations
    PreferClient,
    /// Prefer server-side decorations
    PreferServer,
    /// Force server-side decorations
    ForceServer,
}

impl Default for DecorationPolicy {
    fn default() -> Self {
        Self::PreferClient
    }
}

// ============================================================================
// Domain Sub-State: XDG Shell
// ============================================================================

/// XDG shell protocol state — surfaces, toplevels, popups, positioners,
/// activation tokens, foreign toplevel export/import, decorations, outputs.
pub struct XdgState {
    /// Active xdg_wm_base resources (for pinging)
    pub shell_resources: HashMap<(ClientId, u32), xdg_wm_base::XdgWmBase>,
    /// Mapping of xdg_surface IDs to their data
    pub surfaces: HashMap<(ClientId, u32), XdgSurfaceData>,
    /// Mapping of xdg_toplevel IDs to their data
    pub toplevels: HashMap<(ClientId, u32), XdgToplevelData>,
    /// Mapping of xdg_popup IDs to their data
    pub popups: HashMap<(ClientId, u32), XdgPopupData>,
    /// Mapping of xdg_positioner IDs to their data
    pub positioners: HashMap<(ClientId, u32), XdgPositionerData>,
    /// Activation protocol state
    pub activation: ActivationState,
    /// Foreign toplevel (exporter/importer) state
    pub foreign: XdgForeignState,
    /// XDG output state
    pub output: XdgOutputState,
    /// Decoration state
    pub decoration: DecorationState,
    /// Ping tracking: maps serial → (client_id, shell_resource_id, timestamp)
    pub pending_pings: HashMap<u32, (ClientId, u32, Instant)>,
    /// Toplevel drag state (xdg_toplevel_drag_v1)
    pub toplevel_drag: crate::core::wayland::xdg::xdg_toplevel_drag::ToplevelDragState,
    /// Toplevel icon state (xdg_toplevel_icon_v1)
    pub toplevel_icon: crate::core::wayland::xdg::xdg_toplevel_icon::ToplevelIconState,
}


impl Default for XdgState {
    fn default() -> Self {
        Self {
            shell_resources: HashMap::new(),
            surfaces: HashMap::new(),
            toplevels: HashMap::new(),
            popups: HashMap::new(),
            positioners: HashMap::new(),
            activation: ActivationState::default(),
            foreign: XdgForeignState::default(),
            output: XdgOutputState::default(),
            decoration: DecorationState::default(),
            pending_pings: HashMap::new(),
            toplevel_drag: crate::core::wayland::xdg::xdg_toplevel_drag::ToplevelDragState::default(),
            toplevel_icon: crate::core::wayland::xdg::xdg_toplevel_icon::ToplevelIconState::default(),
        }
    }
}

// ============================================================================
// Domain Sub-State: Extension Protocols
// ============================================================================

/// Extension protocol state — pointer constraints, relative pointers,
/// viewporter, dmabuf, sync objects, presentation, idle inhibit, etc.
pub struct ExtProtocolState {
    /// Relative pointer state
    pub relative_pointers: RelativePointerState,
    /// Pointer constraints state (locked/confined pointers)
    pub pointer_constraints: PointerConstraintsState,

    /// Viewports (viewport_id -> data)
    pub viewports: HashMap<u32, ViewportData>,
    /// Viewporter State
    pub viewporter: ViewporterState,

    /// Linux DMABUF state
    pub linux_dmabuf: LinuxDmabufState,

    /// Surface synchronization state (linux-drm-syncobj)
    #[cfg(feature = "desktop-protocols")]
    pub linux_drm_syncobj: SyncObjState,

    /// DRM Lease state
    #[cfg(feature = "desktop-protocols")]
    pub drm_lease: DrmLeaseState,

    /// Presentation time state
    pub presentation: PresentationState,

    /// Idle inhibit state
    pub idle_inhibit: IdleInhibitState,

    /// Keyboard shortcuts inhibit state
    pub keyboard_shortcuts_inhibit: KeyboardShortcutsInhibitState,
    /// Pointer gestures state
    pub pointer_gestures: PointerGesturesState,
    /// Content type hints per surface
    pub content_type: crate::core::wayland::ext::content_type::ContentTypeState,
    /// Tearing control hints per surface
    pub tearing_control: crate::core::wayland::ext::tearing_control::TearingControlState,
    /// Alpha modifier per surface
    pub alpha_modifier: crate::core::wayland::ext::alpha_modifier::AlphaModifierState,
    /// Primary selection (middle-click paste) state
    pub primary_selection: crate::core::wayland::ext::primary_selection::PrimarySelectionState,
    /// Input timestamps subscriptions
    pub input_timestamps: crate::core::wayland::ext::input_timestamps::InputTimestampsState,
    /// Idle notification state
    pub idle_notify: crate::core::wayland::ext::idle_notify::IdleNotifyState,
    /// FIFO barrier state per surface
    pub fifo: crate::core::wayland::ext::fifo::FifoState,
    /// Commit timing (target presentation time) per surface
    pub commit_timing: crate::core::wayland::ext::commit_timing::CommitTimingState,
    /// Text input (IME) state
    pub text_input: crate::core::wayland::ext::text_input::TextInputState,
    /// Input method v2 state (desktop-only, for IBus/Fcitx)
    #[cfg(feature = "desktop-protocols")]
    pub input_method: crate::core::wayland::ext::input_method::InputMethodState,
    /// Session lock state
    #[cfg(feature = "desktop-protocols")]
    pub session_lock: crate::core::wayland::ext::session_lock::SessionLockState,
    /// Security context metadata
    pub security_context: crate::core::wayland::ext::security_context::SecurityContextState,
    /// Workspace state
    pub workspace: crate::core::wayland::ext::workspace::WorkspaceState,
    /// Background effect (blur) state
    pub background_effect: crate::core::wayland::ext::background_effect::BackgroundEffectState,
    /// Fullscreen shell state (always available — used as the primary shell on iOS)
    pub fullscreen_shell: crate::core::wayland::ext::fullscreen_shell::FullscreenShellState,
    /// XWayland keyboard grab state
    #[cfg(feature = "desktop-protocols")]
    pub xwayland_keyboard_grab: crate::core::wayland::ext::xwayland_keyboard_grab::XwaylandKeyboardGrabState,
    /// Image copy capture: session ObjectId -> (width, height) for active frame tracking
    #[cfg(feature = "desktop-protocols")]
    pub image_copy_capture_active_frame: HashMap<wayland_server::backend::ObjectId, (u32, u32)>,
}


impl Default for ExtProtocolState {
    fn default() -> Self {
        Self {
            relative_pointers: RelativePointerState::default(),
            pointer_constraints: PointerConstraintsState::default(),
            viewports: HashMap::new(),
            viewporter: ViewporterState::default(),
            linux_dmabuf: LinuxDmabufState::default(),
            #[cfg(feature = "desktop-protocols")]
            linux_drm_syncobj: SyncObjState::default(),
            #[cfg(feature = "desktop-protocols")]
            drm_lease: DrmLeaseState::default(),
            presentation: PresentationState::default(),
            idle_inhibit: IdleInhibitState::default(),
            keyboard_shortcuts_inhibit: KeyboardShortcutsInhibitState::default(),
            pointer_gestures: PointerGesturesState::default(),
            content_type: crate::core::wayland::ext::content_type::ContentTypeState::default(),
            tearing_control: crate::core::wayland::ext::tearing_control::TearingControlState::default(),
            alpha_modifier: crate::core::wayland::ext::alpha_modifier::AlphaModifierState::default(),
            primary_selection: crate::core::wayland::ext::primary_selection::PrimarySelectionState::default(),
            input_timestamps: crate::core::wayland::ext::input_timestamps::InputTimestampsState::default(),
            idle_notify: crate::core::wayland::ext::idle_notify::IdleNotifyState::default(),
            fifo: crate::core::wayland::ext::fifo::FifoState::default(),
            commit_timing: crate::core::wayland::ext::commit_timing::CommitTimingState::default(),
            text_input: crate::core::wayland::ext::text_input::TextInputState::default(),
            #[cfg(feature = "desktop-protocols")]
            input_method: crate::core::wayland::ext::input_method::InputMethodState::default(),
            #[cfg(feature = "desktop-protocols")]
            session_lock: crate::core::wayland::ext::session_lock::SessionLockState::default(),
            security_context: crate::core::wayland::ext::security_context::SecurityContextState::default(),
            workspace: crate::core::wayland::ext::workspace::WorkspaceState::default(),
            background_effect: crate::core::wayland::ext::background_effect::BackgroundEffectState::default(),
            fullscreen_shell: crate::core::wayland::ext::fullscreen_shell::FullscreenShellState::default(),
            #[cfg(feature = "desktop-protocols")]
            xwayland_keyboard_grab: crate::core::wayland::ext::xwayland_keyboard_grab::XwaylandKeyboardGrabState::default(),
            #[cfg(feature = "desktop-protocols")]
            image_copy_capture_active_frame: HashMap::new(),
        }
    }
}



// ============================================================================
// Domain Sub-State: wlroots Protocols
// ============================================================================

/// wlroots protocol state — layer shell, virtual pointers/keyboards,
/// data control (clipboard managers), output management.
pub struct WlrState {
    /// All active layer surfaces, keyed by (ClientId, surface_id)
    pub layer_surfaces: HashMap<(ClientId, u32), Arc<RwLock<LayerSurface>>>,
    /// Surface ID to layer surface ID mapping (for buffer handling), keyed by (ClientId, surface_id)
    pub surface_to_layer: HashMap<(ClientId, u32), u32>,
    /// Active virtual pointers (client_id, resource_id) -> pointer_state
    pub virtual_pointers: HashMap<(ClientId, u32), VirtualPointerState>,
    /// Active virtual keyboards (client_id, resource_id) -> keyboard_state
    pub virtual_keyboards: HashMap<(ClientId, u32), VirtualKeyboardState>,
    /// Data control state
    pub data_control: DataControlState,
    /// Export DMABUF state
    pub export_dmabuf: ExportDmabufState,
    /// Last output manager config serial
    pub last_output_manager_serial: u32,
    /// Pending screencopy captures (platform polls, writes, then signals done)
    pub pending_screencopies: Vec<PendingScreencopy>,
    /// Next capture ID for FFI
    pub next_screencopy_id: u64,
    /// Gamma control: pending apply (platform applies) or restore (platform restores)
    pub gamma_control: GammaControlState,
    /// Pending image copy captures (desktop-protocols, platform writes pixels then signals done)
    #[cfg(feature = "desktop-protocols")]
    pub pending_image_copy_captures: Vec<crate::core::wayland::ext::image_copy_capture::PendingImageCopyCapture>,
    /// Next image copy capture ID for FFI
    #[cfg(feature = "desktop-protocols")]
    pub next_image_copy_capture_id: u64,
}


impl Default for WlrState {
    fn default() -> Self {
        Self {
            layer_surfaces: HashMap::new(),
            surface_to_layer: HashMap::new(),
            virtual_pointers: HashMap::new(),
            virtual_keyboards: HashMap::new(),
            data_control: DataControlState::default(),
            export_dmabuf: ExportDmabufState::default(),
            last_output_manager_serial: 1,
            pending_screencopies: Vec::new(),
            next_screencopy_id: 1,
            gamma_control: GammaControlState::default(),
            #[cfg(feature = "desktop-protocols")]
            pending_image_copy_captures: Vec::new(),
            #[cfg(feature = "desktop-protocols")]
            next_image_copy_capture_id: 1,
        }
    }
}

/// Gamma ramp for one channel (u16 values, protocol little-endian)
pub type GammaRamp = Vec<u16>;

/// Pending gamma apply — platform calls CGSetDisplayTransferByTable
#[cfg_attr(
    not(any(target_os = "ios", target_os = "visionos", target_os = "watchos")),
    derive(uniffi::Record)
)]
#[derive(Debug, Clone)]
pub struct GammaRampApply {
    pub output_id: u32,
    pub size: u32,
    pub red: GammaRamp,
    pub green: GammaRamp,
    pub blue: GammaRamp,
}

/// Gamma control state
#[derive(Debug, Default)]
pub struct GammaControlState {
    /// Active control per output: output_id -> (control_protocol_id, client_id)
    pub active_controls: HashMap<u32, (u32, wayland_server::backend::ClientId)>,
    /// Pending apply (platform polls and applies)
    pub pending_apply: Option<GammaRampApply>,
    /// Pending restore for output_id (platform restores original gamma)
    pub pending_restore: Option<u32>,
}



// ============================================================================
// Main Compositor State
// ============================================================================

/// Global compositor state.
///
/// This struct holds all the "business logic" state of the compositor.
/// Protocol-specific state is grouped into domain sub-states for clarity.
pub struct CompositorState {
    // =========================================================================
    // Core State
    // =========================================================================
    
    /// Connected clients
    pub clients: HashMap<wayland_server::backend::ClientId, ClientState>,

    /// All active surfaces, keyed by their Wayland object ID.
    pub surfaces: HashMap<u32, Arc<RwLock<Surface>>>,
    
    /// All active windows (Toplevels), keyed by their ID.
    pub windows: HashMap<u32, Arc<RwLock<Window>>>,
    
    /// Surface ID to Window ID mapping
    pub surface_to_window: HashMap<u32, u32>,
    
    /// Subsurface registry, keyed by subsurface's surface ID
    pub subsurfaces: HashMap<u32, SubsurfaceState>,
    
    /// Parent to children mapping for subsurface hierarchy
    pub subsurface_children: HashMap<u32, Vec<u32>>,
    
    /// Protocol surface ID to internal surface ID mapping, keyed by (ClientId, protocol_id)
    pub protocol_to_internal_surface: HashMap<(wayland_server::backend::ClientId, u32), u32>,
    
    /// All active buffers, keyed by their (ClientId, protocol_id).
    pub buffers: HashMap<(ClientId, u32), Arc<RwLock<crate::core::surface::Buffer>>>,

    /// Buffers to be released after the next frame is presented
    pub pending_buffer_releases: Vec<(ClientId, u32)>,

    // =========================================================================
    // Focus & Input State
    // =========================================================================
    
    /// Focus manager
    pub focus: FocusManager,
    
    /// Window tree
    pub window_tree: WindowTree,
    
    /// Primary seat state
    pub seat: SeatState,
    
    // =========================================================================
    // Output State
    // =========================================================================
    
    /// Output states
    pub outputs: Vec<OutputState>,
    
    /// Primary output index
    pub primary_output: usize,
    
    /// Bound wl_output resources
    pub output_resources: HashMap<wayland_server::backend::ObjectId, wayland_server::protocol::wl_output::WlOutput>,
    /// wl_output ObjectId -> output_id (for image capture source resolution)
    pub output_id_by_resource: HashMap<wayland_server::backend::ObjectId, u32>,
    /// Image capture source ObjectId -> output_id (for CreateSession lookup)
    pub image_capture_source_output: HashMap<wayland_server::backend::ObjectId, u32>,
    
    // =========================================================================
    // Frame Callbacks
    // =========================================================================
    
    /// Pending frame callbacks per surface.
    pub frame_callbacks: HashMap<u32, Vec<WlCallback>>,
    
    // =========================================================================
    // Configuration
    // =========================================================================
    
    /// Decoration policy
    pub decoration_policy: DecorationPolicy,
    
    /// Keyboard repeat rate (Hz)
    pub keyboard_repeat_rate: i32,
    
    /// Keyboard repeat delay (ms)
    pub keyboard_repeat_delay: i32,
    
    /// Whether to advertise zwp_fullscreen_shell_v1
    pub advertise_fullscreen_shell: bool,
    
    // =========================================================================
    // ID Generators
    // =========================================================================
    
    /// Next surface ID
    next_surface_id: u32,
    
    /// Next window ID
    next_window_id: u32,
    
    /// Serial counter for Wayland events
    serial: u32,

    /// Number of commits observed while an xdg_surface configure is still pending.
    pub commit_before_ack_count: u64,
    
    // =========================================================================
    // Protocol Domain State (grouped by domain)
    // =========================================================================
    
    /// XDG shell protocol state
    pub xdg: XdgState,
    
    /// Extension protocol state (pointer constraints, viewporter, dmabuf, etc.)
    pub ext: ExtProtocolState,
    
    /// wlroots protocol state (layer shell, virtual devices, data control)
    pub wlr: WlrState,
    
    /// Data device protocol state (clipboard, DnD)
    pub data: DataDeviceState,
    
    // =========================================================================
    // Core Protocol Resources
    // =========================================================================
    
    /// Bound wl_seat resources
    pub seat_resources: HashMap<u32, wayland_server::protocol::wl_seat::WlSeat>,
    
    /// Pending compositor events (pushed by protocol handlers)
    pub pending_compositor_events: Vec<CompositorEvent>,
    
    /// SHM pools for buffer pixel access ((client_id, pool_id) -> pool)
    pub shm_pools: HashMap<(ClientId, u32), ShmPool>,

    /// Regions for wl_region ((client_id, region_id) -> list of rects)
    pub regions: HashMap<(ClientId, u32), Vec<crate::core::surface::damage::DamageRegion>>,

    // =========================================================================
    // Scene Graph
    // =========================================================================
    
    /// Global scene graph
    pub scene: Scene,
    
    /// Global damage tracking
    pub scene_damage: SceneDamage,
    
    /// Next scene node ID
    next_node_id: u32,
}

impl CompositorState {
    pub fn new(config: Option<crate::core::compositor::CompositorConfig>) -> Self {
        let (decoration_policy, advertise_fullscreen_shell) = if let Some(cfg) = config {
             let policy = if cfg.force_ssd {
                 DecorationPolicy::ForceServer
             } else {
                 DecorationPolicy::default()
             };
             (policy, cfg.advertise_fullscreen_shell)
        } else {
            (DecorationPolicy::default(), false)
        };

        Self {
            clients: HashMap::new(),
            surfaces: HashMap::new(),
            windows: HashMap::new(),
            surface_to_window: HashMap::new(),
            subsurfaces: HashMap::new(),
            subsurface_children: HashMap::new(),
            protocol_to_internal_surface: HashMap::new(),
            buffers: HashMap::new(),
            pending_buffer_releases: Vec::new(),
            focus: FocusManager::new(),
            window_tree: WindowTree::new(),
            seat: SeatState::new("seat0"),
            outputs: vec![OutputState::default()],
            primary_output: 0,
            output_resources: HashMap::new(),
            output_id_by_resource: HashMap::new(),
            image_capture_source_output: HashMap::new(),
            frame_callbacks: HashMap::new(),
            decoration_policy,
            keyboard_repeat_rate: 33,
            keyboard_repeat_delay: 500,
            advertise_fullscreen_shell,
            next_surface_id: 1,
            next_window_id: 1,
            serial: 0,
            commit_before_ack_count: 0,
            
            // Protocol domain sub-states
            xdg: XdgState::default(),
            ext: ExtProtocolState::default(),
            wlr: WlrState::default(),
            data: DataDeviceState::default(),
            seat_resources: HashMap::new(),
            
            pending_compositor_events: Vec::new(),
            shm_pools: HashMap::new(),
            regions: HashMap::new(),
            
            scene: Scene::new(),
            scene_damage: SceneDamage::new(),
            next_node_id: 1,
        }
    }

    /// Generate next window ID
    pub fn next_window_id(&mut self) -> u32 {
        let id = self.next_window_id;
        self.next_window_id += 1;
        id
    }
    
    /// Generate next serial for Wayland events
    pub fn next_serial(&mut self) -> u32 {
        let serial = self.serial;
        self.serial = self.serial.wrapping_add(1);
        serial
    }

    /// Resolve window ID for a surface, walking up the subsurface tree if needed.
    /// Returns Some(window_id) for toplevels, popups, and subsurfaces (resolved
    /// via their parent chain); None for layer surfaces or unmapped surfaces.
    pub fn resolve_window_id_for_surface(&self, surface_id: u32) -> Option<u32> {
        if let Some(&wid) = self.surface_to_window.get(&surface_id) {
            return Some(wid);
        }
        if let Some(sub) = self.subsurfaces.get(&surface_id) {
            let mut parent_id = sub.parent_id;
            for _ in 0..16 {
                if let Some(&wid) = self.surface_to_window.get(&parent_id) {
                    return Some(wid);
                }
                if let Some(psub) = self.subsurfaces.get(&parent_id) {
                    parent_id = psub.parent_id;
                } else {
                    break;
                }
            }
        }
        None
    }

    // =========================================================================
    // Frame Callbacks
    // =========================================================================
    
    /// Queue a frame callback for a surface.
    pub fn queue_frame_callback(&mut self, surface_id: u32, callback: WlCallback) {
        self.frame_callbacks
            .entry(surface_id)
            .or_insert_with(Vec::new)
            .push(callback);
    }
    
    /// Flush all pending frame callbacks for a surface.
    pub fn flush_frame_callbacks(&mut self, surface_id: u32, timestamp: Option<u32>) {
        if let Some(callbacks) = self.frame_callbacks.remove(&surface_id) {
            let _count = callbacks.len();
            let timestamp = timestamp.unwrap_or_else(Self::get_timestamp_ms);
            crate::wtrace!(crate::util::logging::STATE, "Flushing {} frame callbacks for surface {} (timestamp={})", 
                callbacks.len(), surface_id, timestamp);
            for callback in callbacks {
                callback.done(timestamp);
            }
        }
    }
    
    /// Flush all pending frame callbacks for all surfaces.
    pub fn flush_all_frame_callbacks(&mut self) {
        let timestamp = Self::get_timestamp_ms();
        let mut total = 0;
        
        for (_surface_id, callbacks) in self.frame_callbacks.drain() {
            total += callbacks.len();
            for callback in callbacks {
                callback.done(timestamp);
            }
        }
        
        if total > 0 {
            tracing::trace!("Flushed {} total frame callbacks", total);
        }
    }
    
    /// Check if there are pending frame callbacks
    pub fn has_pending_frame_callbacks(&self) -> bool {
        self.frame_callbacks.values().any(|v| !v.is_empty())
    }

    // =========================================================================
    // Output Management (core)
    // =========================================================================
    
    /// Get primary output
    pub fn primary_output(&self) -> &OutputState {
        &self.outputs[self.primary_output]
    }

    /// Update primary output configuration
    pub fn update_primary_output(&mut self, width: u32, height: u32, scale: f32) {
        let index = self.primary_output;
        if let Some(output) = self.outputs.get_mut(index) {
            output.update(width, height, scale);
            crate::wlog!(crate::util::logging::STATE, "Updated primary output: {}x{} @ {}x", width, height, scale);
        }
    }
    
    /// Get primary output mutably
    pub fn primary_output_mut(&mut self) -> &mut OutputState {
        &mut self.outputs[self.primary_output]
    }
    
    /// Set output size
    pub fn set_output_size(&mut self, width: u32, height: u32, scale: f32) {
        let safe_scale = if scale < 1.0 { 1.0 } else { scale };
        let safe_width = if width == 0 { 1920 } else { width };
        let safe_height = if height == 0 { 1080 } else { height };

        let idx = self.primary_output;
        let (output_rect, usable_rect, phys_w, phys_h) = if let Some(output) = self.outputs.get_mut(idx) {
            output.width = safe_width;
            output.height = safe_height;
            output.scale = safe_scale;
            output.physical_width = ((safe_width as f32 / safe_scale) / 96.0 * 25.4) as u32;
            output.physical_height = ((safe_height as f32 / safe_scale) / 96.0 * 25.4) as u32;
            (
                (output.x, output.y, output.width as i32, output.height as i32),
                (
                    output.usable_area.x,
                    output.usable_area.y,
                    output.usable_area.width as i32,
                    output.usable_area.height as i32,
                ),
                output.physical_width,
                output.physical_height,
            )
        } else {
            (
                (0, 0, safe_width as i32, safe_height as i32),
                (0, 0, safe_width as i32, safe_height as i32),
                ((safe_width as f32 / safe_scale) / 96.0 * 25.4) as u32,
                ((safe_height as f32 / safe_scale) / 96.0 * 25.4) as u32,
            )
        };

        // Keep fullscreen / maximized windows aligned with the new output geometry
        // (e.g. device rotation). Without this, scene nodes can keep stale
        // pre-rotation dimensions until the next client-driven commit.
        let fullscreen_shell_wid = self.ext.fullscreen_shell.presented_window_id;
        let force_android_output_resize = cfg!(target_os = "android");
        let mut resized_window_sizes: std::collections::HashMap<u32, (u32, u32)> =
            std::collections::HashMap::new();
        for (&wid, window_ref) in &self.windows {
            if let Ok(mut window) = window_ref.write() {
                let old_w = window.width;
                let old_h = window.height;
                let old_x = window.x;
                let old_y = window.y;

                if force_android_output_resize
                    || fullscreen_shell_wid == Some(wid)
                    || window.fullscreen
                {
                    window.x = output_rect.0;
                    window.y = output_rect.1;
                    window.width = output_rect.2;
                    window.height = output_rect.3;
                } else if window.maximized {
                    window.x = usable_rect.0;
                    window.y = usable_rect.1;
                    window.width = usable_rect.2.max(0);
                    window.height = usable_rect.3.max(0);
                } else {
                    continue;
                }

                if window.width != old_w
                    || window.height != old_h
                    || window.x != old_x
                    || window.y != old_y
                {
                    resized_window_sizes.insert(
                        wid,
                        (window.width.max(0) as u32, window.height.max(0) as u32),
                    );
                }
            }
        }

        if !resized_window_sizes.is_empty() {
            let mut pending_configures = Vec::new();
            for ((client_id, toplevel_id), data) in &self.xdg.toplevels {
                if let Some(&(w, h)) = resized_window_sizes.get(&data.window_id) {
                    pending_configures.push((client_id.clone(), *toplevel_id, w, h, data.window_id));
                }
            }
            for (client_id, toplevel_id, w, h, window_id) in pending_configures {
                let _ = self.send_toplevel_configure(client_id, toplevel_id, w, h);
                self.pending_compositor_events.push(crate::core::compositor::CompositorEvent::WindowSizeChanged {
                    window_id,
                    width: w,
                    height: h,
                });
            }
        }
        
        tracing::info!("Output size set to {}x{} @ {}x (phys: {}x{}mm)", 
            safe_width, safe_height, safe_scale, phys_w, phys_h);
    }
    
    /// Set platform safe area insets on the primary output.
    pub fn set_safe_area_insets(&mut self, top: i32, right: i32, bottom: i32, left: i32) {
        let idx = self.primary_output;
        if let Some(output) = self.outputs.get_mut(idx) {
            output.safe_area_insets = (top, right, bottom, left);
            tracing::info!(
                "Safe area insets set: top={} right={} bottom={} left={}",
                top, right, bottom, left
            );
        }
        self.reposition_layer_surfaces();
    }
    
    // =========================================================================
    // Utilities
    // =========================================================================
    
    /// Get current timestamp in milliseconds.
    pub fn get_timestamp_ms() -> u32 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u32
    }
    
    /// Get decoration mode for new windows
    pub fn decoration_mode_for_new_window(&self) -> DecorationMode {
        match self.decoration_policy {
            DecorationPolicy::PreferClient => DecorationMode::ClientSide,
            DecorationPolicy::PreferServer => DecorationMode::ServerSide,
            DecorationPolicy::ForceServer => DecorationMode::ServerSide,
        }
    }
    
}

#[cfg(test)]
mod tests;

impl Default for CompositorState {
    fn default() -> Self {
        Self::new(None)
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_compositor_state_new() {
        let state = CompositorState::new(None);
        assert!(state.surfaces.is_empty());
        assert!(state.windows.is_empty());
        assert_eq!(state.focus.keyboard_focus, None);
    }
    
    #[test]
    fn test_surface_ids() {
        let mut state = CompositorState::new(None);
        assert_eq!(state.next_surface_id(), 1);
        assert_eq!(state.next_surface_id(), 2);
        assert_eq!(state.next_surface_id(), 3);
    }
    
    #[test]
    fn test_window_ids() {
        let mut state = CompositorState::new(None);
        assert_eq!(state.next_window_id(), 1);
        assert_eq!(state.next_window_id(), 2);
        assert_eq!(state.next_window_id(), 3);
    }
    
    #[test]
    fn test_focus_history() {
        let mut focus = crate::core::window::focus::FocusManager::new();

        focus.set_keyboard_focus(Some(1));
        assert_eq!(focus.keyboard_focus, Some(1));

        focus.set_keyboard_focus(Some(2));
        assert_eq!(focus.keyboard_focus, Some(2));
        assert_eq!(focus.focus_history, vec![1]);

        focus.set_keyboard_focus(Some(3));
        assert_eq!(focus.keyboard_focus, Some(3));
        assert_eq!(focus.focus_history, vec![2, 1]);
    }

    #[test]
    fn test_decoration_mode_for_new_window() {
        use crate::core::window::DecorationMode;

        // Force SSD -> ServerSide
        let config = crate::core::compositor::CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        assert_eq!(
            state.decoration_mode_for_new_window(),
            DecorationMode::ServerSide
        );

        // PreferClient (default when force_ssd=false)
        let config = crate::core::compositor::CompositorConfig {
            force_ssd: false,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        assert_eq!(
            state.decoration_mode_for_new_window(),
            DecorationMode::ClientSide
        );

        // PreferServer
        let mut state = CompositorState::new(None);
        state.decoration_policy = DecorationPolicy::PreferServer;
        assert_eq!(
            state.decoration_mode_for_new_window(),
            DecorationMode::ServerSide
        );
    }

    #[test]
    fn test_xdg_surface_data_tracks_ack_serial_defaults() {
        let data = XdgSurfaceData::new(123);
        assert_eq!(data.pending_serial, 0);
        assert_eq!(data.last_acked_serial, 0);
        assert!(!data.configured);
    }
}

impl CompositorState {
    /// Fire presentation feedback for committed surfaces.
    /// Uses the same delivery path as `report_presentation_feedback`.
    pub fn fire_presentation_feedback(&mut self) {
        let timestamp_ns = crate::core::Compositor::timestamp_ms() as u64 * 1_000_000;
        let refresh_ns = 16_666_666; // 60 Hz default
        let seq = self.next_presentation_seq();
        self.ext.presentation.send_presented_events(timestamp_ns, refresh_ns, seq);
    }

    /// Remove state owned by a disconnected client.
    ///
    /// Nested compositors can be killed abruptly from the host UI. This keeps
    /// the compositor's internal maps coherent even when teardown is abrupt.
    pub fn cleanup_disconnected_client(&mut self, client: ClientId) {
        self.protocol_to_internal_surface
            .retain(|(cid, _), _| *cid != client);

        let owned_surfaces: Vec<u32> = self
            .surfaces
            .iter()
            .filter_map(|(sid, surf)| {
                surf.read()
                    .ok()
                    .and_then(|s| (s.client_id == Some(client.clone())).then_some(*sid))
            })
            .collect();

        let mut owned_windows: Vec<u32> = owned_surfaces
            .iter()
            .filter_map(|sid| self.surface_to_window.get(sid).copied())
            .collect();
        owned_windows.sort_unstable();
        owned_windows.dedup();
        for wid in owned_windows {
            self.destroy_window(wid);
        }

        for sid in owned_surfaces {
            self.subsurfaces.remove(&sid);
            self.subsurface_children.remove(&sid);
            for children in self.subsurface_children.values_mut() {
                children.retain(|child| *child != sid);
            }
            self.remove_surface(sid);
        }

        self.buffers.retain(|(cid, _), _| *cid != client);
        self.pending_buffer_releases
            .retain(|(cid, _)| *cid != client);
        self.shm_pools.retain(|(cid, _), _| *cid != client);
        self.regions.retain(|(cid, _), _| *cid != client);
        self.clients.remove(&client);

        self.wlr.layer_surfaces.retain(|(cid, _), _| *cid != client);
        self.wlr.surface_to_layer.retain(|(cid, _), _| *cid != client);
        self.wlr.virtual_pointers.retain(|(cid, _), _| *cid != client);
        self.wlr.virtual_keyboards.retain(|(cid, _), _| *cid != client);

        self.xdg.surfaces.retain(|(cid, _), _| *cid != client);
        self.xdg.toplevels.retain(|(cid, _), _| *cid != client);
        self.xdg.popups.retain(|(cid, _), _| *cid != client);
        self.xdg.positioners.retain(|(cid, _), _| *cid != client);
        self.xdg.pending_pings.retain(|_, (cid, _, _)| *cid != client);
    }
}

// ============================================================================
// Protocol State Trait Implementation
// ============================================================================

impl ProtocolState for ExtProtocolState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        use wayland_server::Resource;
        // Clean up idle notify subscriptions owned by this client
        self.idle_notify.notifications.retain(|n| {
            n.resource.client().map_or(true, |c| c.id() != client)
        });
        // Clean up input timestamp subscriptions
        self.input_timestamps.resources.retain(|(r, _kind)| {
            r.client().map_or(true, |c| c.id() != client)
        });
    }
}

impl ProtocolState for WlrState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        let to_restore: Vec<u32> = self
            .gamma_control
            .active_controls
            .iter()
            .filter(|(_, (_, c))| *c == client)
            .map(|(oid, _)| *oid)
            .collect();
        self.data_control.client_disconnected(client);
        for oid in &to_restore {
            self.gamma_control.active_controls.remove(oid);
            self.gamma_control.pending_restore = Some(*oid);
        }
    }
}

impl ProtocolState for XdgState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        use wayland_server::Resource;
        // Clean up shell resources owned by this client
        self.shell_resources.retain(|_id, res| {
            res.client().map_or(true, |c| c.id() != client)
        });
    }
}

impl ProtocolState for DataDeviceState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        use wayland_server::Resource;
        // Clean up data devices owned by this client
        self.devices.retain(|_id, device_data| {
            device_data.resource.client().map_or(true, |c| c.id() != client)
        });
        // Clear drag if it belongs to disconnecting client
        if self.drag.is_some() {
            self.drag = None;
        }
    }
}

impl ProtocolState for SeatState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        use wayland_server::Resource;
        // Cleanup pointers
        self.pointer.resources.retain(|p| {
            if let Some(c) = p.client() {
                c.id() != client
            } else {
                true
            }
        });

        // Cleanup keyboards
        self.keyboard.resources.retain(|k| {
            if let Some(c) = k.client() {
                c.id() != client
            } else {
                true
            }
        });

        // Cleanup touches
        self.touch.resources.retain(|t| {
            if let Some(c) = t.client() {
                c.id() != client
            } else {
                true
            }
        });

        // Focus surface cleanup is handled at the CompositorState level
        // in client_disconnected(), which has access to the surface map
        // to resolve surface ownership.
    }
}

impl ProtocolState for CompositorState {
    fn client_disconnected(&mut self, client: wayland_server::backend::ClientId) {
        self.ext.client_disconnected(client.clone());
        self.wlr.client_disconnected(client.clone());
        self.xdg.client_disconnected(client.clone());
        self.data.client_disconnected(client.clone());
        self.seat.client_disconnected(client.clone());
        self.cleanup_disconnected_client(client);
    }
}


