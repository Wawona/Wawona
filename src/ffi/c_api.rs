// C FFI Exports (Plain C, no mangling)
// These are callable directly from Objective-C without Swift
use std::os::raw::c_char;
use std::ffi::{CStr, CString};
use std::sync::Arc;
use super::api::WawonaCore as WWNCore;
use super::types::{WindowId, PointerButton, PointerAxis, AxisSource, ButtonState, KeyState, KeyboardModifiers};


/// Create a new WWNCore instance
#[no_mangle]
pub extern "C" fn WWNCoreNew() -> *mut WWNCore {
    let core = WWNCore::new();
    Arc::into_raw(core) as *mut WWNCore
}

/// Start the compositor
#[no_mangle]
pub extern "C" fn WWNCoreStart(
    core: *mut WWNCore,
    socket_name: *const c_char
) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    let socket = if socket_name.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(socket_name) }
            .to_str()
            .ok()
            .map(|s| s.to_string())
    };
    
    match core.start(socket) {
        Ok(()) => {
            crate::wlog!(crate::util::logging::C_API, "Compositor started successfully");
            true
        }
        Err(e) => {
            crate::wlog!(crate::util::logging::C_API, "Compositor start failed: {:?}", e);
            false
        }
    }
}

/// Stop the compositor
#[no_mangle]
pub extern "C" fn WWNCoreStop(core: *mut WWNCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    core.stop().is_ok()
}

/// Check if compositor is running
#[no_mangle]
pub extern "C" fn WWNCoreIsRunning(core: *const WWNCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    core.is_running()
}

/// Get socket path (returns malloc'd string, caller must free)
#[no_mangle]
pub extern "C" fn WWNCoreGetSocketPath(core: *const WWNCore) -> *mut c_char {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    let path = core.get_socket_path();
    
    CString::new(path).ok()
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Get socket name (returns malloc'd string, caller must free)
#[no_mangle]
pub extern "C" fn WWNCoreGetSocketName(core: *const WWNCore) -> *mut c_char {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    let name = core.get_socket_name();
    
    CString::new(name).ok()
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Free a string returned by this API
#[no_mangle]
pub extern "C" fn WWNStringFree(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}

/// Process events
#[no_mangle]
pub extern "C" fn WWNCoreProcessEvents(core: *mut WWNCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| core.process_events())) {
        Ok(ok) => ok,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCoreProcessEvents panicked; keeping process alive and skipping this tick"
            );
            false
        }
    }
}

/// Set output size
#[no_mangle]
pub extern "C" fn WWNCoreSetOutputSize(
    core: *mut WWNCore,
    width: u32,
    height: u32,
    scale: f32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        
        let core = unsafe { &*core };
        core.set_output_size(width, height, scale);
    }));
}

/// Set platform safe area insets (iOS notch, home indicator, etc.)
/// These are applied as implicit exclusive zones for layer-shell positioning.
#[no_mangle]
pub extern "C" fn WWNCoreSetSafeAreaInsets(
    core: *mut WWNCore,
    top: i32,
    right: i32,
    bottom: i32,
    left: i32,
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        
        let core = unsafe { &*core };
        core.set_safe_area_insets(top, right, bottom, left);
    }));
}

/// Set force SSD policy
#[no_mangle]
pub extern "C" fn WWNCoreSetForceSSD(
    core: *mut WWNCore,
    enabled: bool
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        
        let core = unsafe { &*core };
        core.set_force_ssd(enabled);
    }));
}

/// Inject window resize
#[no_mangle]
pub extern "C" fn WWNCoreInjectWindowResize(
    core: *mut WWNCore,
    window_id: u64,
    width: u32,
    height: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.resize_window(WindowId { id: window_id }, width, height);
    }));
}

/// Set window activation state (focus) and send a configure event.
#[no_mangle]
pub extern "C" fn WWNCoreSetWindowActivated(
    core: *mut WWNCore,
    window_id: u64,
    active: bool
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.set_window_activated(WindowId { id: window_id }, active, true);
    }));
}

/// Set window activation state without emitting a configure.
/// The caller must trigger a configure separately (e.g. via resize).
#[no_mangle]
pub extern "C" fn WWNCoreSetWindowActivatedSilent(
    core: *mut WWNCore,
    window_id: u64,
    active: bool
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.set_window_activated(WindowId { id: window_id }, active, false);
    }));
}

/// Flush all pending Wayland events to connected clients immediately.
/// Call after generating events outside of the normal compositor tick
/// to avoid them sitting in the buffer until the next tick fires.
#[no_mangle]
pub extern "C" fn WWNCoreFlushClients(core: *mut WWNCore) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        core.flush_clients();
    }));
}

/// Free WWNCore instance
#[no_mangle]
pub extern "C" fn WWNCoreFree(core: *mut WWNCore) {
    if !core.is_null() {
        unsafe {
            drop(Arc::from_raw(core));
        }
    }
}

/// C-compatible window event type
#[repr(u32)]
#[derive(Debug, Copy, Clone)]
pub enum CWindowEventType {
    Created = 0,
    Destroyed = 1,
    TitleChanged = 2,
    SizeChanged = 3,
    PopupCreated = 4,
    PopupRepositioned = 5,
    MoveRequested = 6,
    ResizeRequested = 7,
    DecorationModeChanged = 8,
    MinimizeRequested = 9,
    MaximizeRequested = 10,
    UnmaximizeRequested = 11,
    CursorShapeChanged = 12,
}

/// C-compatible window event structure
#[repr(C)]
pub struct CWindowEvent {
    pub event_type: u64, // Use u64 for alignment stability
    pub window_id: u64,
    pub surface_id: u32,
    pub title: *mut c_char,
    pub width: u32,
    pub height: u32,
    pub parent_id: u64,
    pub x: i32,
    pub y: i32,
    /// 0 = ClientSide, 1 = ServerSide
    pub decoration_mode: u8,
    /// 0 = false, 1 = true (fullscreen shell / kiosk - no host chrome)
    pub fullscreen_shell: u8,
    /// Resize edge (xdg_toplevel resize_edge values)
    pub edges: u8,
    pub padding: u8,
}

/// Pop the next pending window event
#[no_mangle]
pub extern "C" fn WWNCorePopWindowEvent(core: *mut WWNCore) -> *mut CWindowEvent {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return std::ptr::null_mut();
        }
        
        let core = unsafe { &*core };
        
        if let Some(event) = core.pop_window_event() {
            let mut c_event = Box::new(CWindowEvent {
                event_type: CWindowEventType::Created as u64,
                window_id: 0,
                surface_id: 0,
                title: std::ptr::null_mut(),
                width: 0,
                height: 0,
                parent_id: 0,
                x: 0,
                y: 0,
                decoration_mode: 0,
                fullscreen_shell: 0,
                edges: 0,
                padding: 0,
            });

            let should_return = match event {
                super::types::WindowEvent::Created { window_id, config } => {
                    c_event.event_type = CWindowEventType::Created as u64;
                    c_event.window_id = window_id.id;
                    c_event.width = config.width;
                    c_event.height = config.height;
                    c_event.decoration_mode = match config.decoration_mode {
                        super::types::DecorationMode::ClientSide => 0,
                        super::types::DecorationMode::ServerSide => 1,
                    };
                    c_event.fullscreen_shell = if config.fullscreen_shell { 1 } else { 0 };
                    c_event.title = CString::new(config.title).ok()
                        .map(|s| s.into_raw())
                        .unwrap_or(std::ptr::null_mut());
                    true
                },
                super::types::WindowEvent::Destroyed { window_id } => {
                    c_event.event_type = CWindowEventType::Destroyed as u64;
                    c_event.window_id = window_id.id;
                    true
                },
                super::types::WindowEvent::TitleChanged { window_id, title } => {
                    c_event.event_type = CWindowEventType::TitleChanged as u64;
                    c_event.window_id = window_id.id;
                    c_event.title = CString::new(title).ok()
                        .map(|s| s.into_raw())
                        .unwrap_or(std::ptr::null_mut());
                    true
                },
                super::types::WindowEvent::SizeChanged { window_id, width, height } => {
                    c_event.event_type = CWindowEventType::SizeChanged as u64;
                    c_event.window_id = window_id.id;
                    c_event.width = width;
                    c_event.height = height;
                    true
                },
                super::types::WindowEvent::PopupCreated { window_id, parent_id, x, y, width, height } => {
                    c_event.event_type = CWindowEventType::PopupCreated as u64;
                    c_event.window_id = window_id.id;
                    c_event.parent_id = parent_id.id;
                    c_event.x = x;
                    c_event.y = y;
                    c_event.width = width;
                    c_event.height = height;
                    c_event.surface_id = window_id.id as u32;

                    tracing::info!("FFI: PopupCreated {} parent={} at {},{}", window_id.id, parent_id.id, x, y);
                    true
                },
                super::types::WindowEvent::PopupRepositioned { window_id, x, y, width, height } => {
                    c_event.event_type = CWindowEventType::PopupRepositioned as u64;
                    c_event.window_id = window_id.id;
                    c_event.x = x;
                    c_event.y = y;
                    c_event.width = width;
                    c_event.height = height;
                    tracing::info!("FFI: PopupRepositioned {} at {},{} {}x{}", window_id.id, x, y, width, height);
                    true
                },
                super::types::WindowEvent::MoveRequested { window_id, serial: _ } => {
                    c_event.event_type = CWindowEventType::MoveRequested as u64;
                    c_event.window_id = window_id.id;
                    true
                },
                super::types::WindowEvent::ResizeRequested { window_id, serial: _, edge } => {
                    c_event.event_type = CWindowEventType::ResizeRequested as u64;
                    c_event.window_id = window_id.id;
                    c_event.edges = edge.to_u32() as u8;
                    true
                },
                super::types::WindowEvent::MinimizeRequested { window_id } => {
                    c_event.event_type = CWindowEventType::MinimizeRequested as u64;
                    c_event.window_id = window_id.id;
                    true
                },
                super::types::WindowEvent::MaximizeRequested { window_id } => {
                    c_event.event_type = CWindowEventType::MaximizeRequested as u64;
                    c_event.window_id = window_id.id;
                    true
                },
                super::types::WindowEvent::UnmaximizeRequested { window_id } => {
                    c_event.event_type = CWindowEventType::UnmaximizeRequested as u64;
                    c_event.window_id = window_id.id;
                    true
                },
                super::types::WindowEvent::DecorationModeChanged { window_id, mode } => {
                    c_event.event_type = CWindowEventType::DecorationModeChanged as u64;
                    c_event.window_id = window_id.id;
                    c_event.decoration_mode = match mode {
                        super::types::DecorationMode::ClientSide => 0,
                        super::types::DecorationMode::ServerSide => 1,
                    };
                    true
                },
                super::types::WindowEvent::CursorShapeChanged { shape } => {
                    c_event.event_type = CWindowEventType::CursorShapeChanged as u64;
                    c_event.surface_id = shape;
                    true
                },
                _ => false
            };
            
            if should_return {
                return Box::into_raw(c_event);
            }
        }
        
        std::ptr::null_mut()
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCorePopWindowEvent panicked; returning NULL"
            );
            std::ptr::null_mut()
        }
    }
}

/// Free a CWindowEvent structure
#[no_mangle]
pub extern "C" fn WWNWindowEventFree(event: *mut CWindowEvent) {
    if !event.is_null() {
        unsafe {
            let event = Box::from_raw(event);
            if !event.title.is_null() {
                drop(CString::from_raw(event.title));
            }
        }
    }
}

/// C-compatible window info structure
#[repr(C)]
pub struct CWindowInfo {
    pub window_id: u64,
    pub width: u32,
    pub height: u32,
    pub title: *mut c_char,  // Caller must free with WWNStringFree
}

/// Get count of pending window created events
#[no_mangle]
pub extern "C" fn WWNCorePendingWindowCount(core: *const WWNCore) -> u32 {
    if core.is_null() {
        return 0;
    }
    0
}

/// Pop and return the next pending window creation info
/// Returns NULL if no pending windows
/// Caller must free title with WWNStringFree
#[no_mangle]
pub extern "C" fn WWNCorePopPendingWindow(_core: *mut WWNCore) -> *mut CWindowInfo {
    // DEPRECATED: Use WWNCorePop_window_event instead
    std::ptr::null_mut()
}

/// Free a CWindowInfo structure
#[no_mangle]
pub extern "C" fn WWNWindowInfoFree(info: *mut CWindowInfo) {
    if !info.is_null() {
        unsafe {
            let info = Box::from_raw(info);
            if !info.title.is_null() {
                drop(CString::from_raw(info.title));
            }
        }
    }
}

/// C-compatible buffer data structure
#[repr(C)]
pub struct CBufferData {
    pub window_id: u64,
    pub surface_id: u32,
    pub buffer_id: u64,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
    pub pixels: *mut u8,       // Pointer to pixel data (leaked Vec)
    pub size: usize,           // Size of pixel data
    pub capacity: usize,       // Capacity of pixel data (for freeing)
    pub iosurface_id: u32,
}

/// Pop the next pending buffer update
/// Returns NULL if no updates
/// Caller must free with WWNBufferDataFree
#[no_mangle]
pub extern "C" fn WWNCorePopPendingBuffer(core: *mut WWNCore) -> *mut CBufferData {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    
    if let Some(event) = core.pop_pending_buffer() {
        // Extract data based on buffer type
        match event.buffer.data {
            super::types::BufferData::Shm { pixels, width, height, stride, format: _ } => {
                // Convert Vec<u8> to raw pointer by leaking it
                // We must reconstruct and drop this Vec later in free()
                let mut pixels = pixels;
                let size = pixels.len();
                let capacity = pixels.capacity();
                let ptr = pixels.as_mut_ptr();
                std::mem::forget(pixels);
                
                let data = Box::new(CBufferData {
                    window_id: event.window_id.id,
                    surface_id: event.surface_id.id,
                    buffer_id: event.buffer.id.id,
                    width,
                    height,
                    stride,
                    format: 0, // 0 for ARGB8888 for now (BufferFormat is enum)
                    pixels: ptr,
                    size,
                    capacity,
                    iosurface_id: 0,
                });
                
                return Box::into_raw(data);
            },
            super::types::BufferData::Iosurface { id, width, height, format } => {
                let data = Box::new(CBufferData {
                    window_id: event.window_id.id,
                    surface_id: event.surface_id.id,
                    buffer_id: event.buffer.id.id,
                    width,
                    height,
                    stride: 0, 
                    format,
                    pixels: std::ptr::null_mut(),
                    size: 0,
                    capacity: 0,
                    iosurface_id: id,
                });
                return Box::into_raw(data);
            },
            super::types::BufferData::DmaBuf { fd: _, width, height, format, modifier: _ } => {
                crate::wlog!(crate::util::logging::FFI,
                    "DMA-BUF buffer popped (buf={} surf={} win={} {}x{} fmt={}): \
                     rendering unsupported, passing metadata so frame_done/release still fire",
                    event.buffer.id.id, event.surface_id.id, event.window_id.id,
                    width, height, format);

                let data = Box::new(CBufferData {
                    window_id: event.window_id.id,
                    surface_id: event.surface_id.id,
                    buffer_id: event.buffer.id.id,
                    width,
                    height,
                    stride: 0,
                    format,
                    pixels: std::ptr::null_mut(),
                    size: 0,
                    capacity: 0,
                    iosurface_id: 0,
                });
                return Box::into_raw(data);
            }
            _ => {
                crate::wlog!(crate::util::logging::FFI,
                    "Unknown buffer type popped (buf={} surf={} win={}): skipping",
                    event.buffer.id.id, event.surface_id.id, event.window_id.id);
                return std::ptr::null_mut();
            }
        }
    }
    
    std::ptr::null_mut()
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCorePopPendingBuffer panicked; returning NULL"
            );
            std::ptr::null_mut()
        }
    }
}

/// Free a CBufferData structure and its pixel data
#[no_mangle]
pub extern "C" fn WWNBufferDataFree(data: *mut CBufferData) {
    if !data.is_null() {
        unsafe {
            let data = Box::from_raw(data);
            if !data.pixels.is_null() && data.capacity > 0 {
                // Reconstruct Vec to drop it and free memory
                let _ = Vec::from_raw_parts(data.pixels, data.size, data.capacity);
            }
        }
    }
}

/// Notify that a frame has been presented
#[no_mangle]
pub extern "C" fn WWNCoreNotifyFramePresented(
    core: *mut WWNCore,
    surface_id: u32,
    buffer_id: u64,
    timestamp: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let sid = super::types::SurfaceId { id: surface_id };
        let bid = if buffer_id != 0 {
            Some(super::types::BufferId { id: buffer_id })
        } else {
            None
        };
        
        core.notify_frame_presented(sid, bid, timestamp);
    }));
}

// ----------------------------------------------------------------------------
// Input Injection API
// ----------------------------------------------------------------------------

/// Inject pointer motion event
#[no_mangle]
pub extern "C" fn WWNCoreInjectPointerMotion(
    core: *mut WWNCore,
    window_id: u64,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.inject_pointer_motion(WindowId { id: window_id }, x, y, timestamp_ms);
    }));
}

/// Inject pointer button event
/// request_code: Linux input event code (0x110=BTN_LEFT, etc)
/// state: 0 = Released, 1 = Pressed
#[no_mangle]
pub extern "C" fn WWNCoreInjectPointerButton(
    core: *mut WWNCore,
    window_id: u64,
    button_code: u32,
    state: u32,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let button = PointerButton::from_button_code(button_code);
        let button_state = if state == 1 { ButtonState::Pressed } else { ButtonState::Released };
        
        core.inject_pointer_button(WindowId { id: window_id }, button, button_state, timestamp_ms);
    }));
}

/// Inject pointer enter event
#[no_mangle]
pub extern "C" fn WWNCoreInjectPointerEnter(
    core: *mut WWNCore,
    window_id: u64,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.inject_pointer_enter(WindowId { id: window_id }, x, y, timestamp_ms);
    }));
}

/// Inject pointer leave event
#[no_mangle]
pub extern "C" fn WWNCoreInjectPointerLeave(
    core: *mut WWNCore,
    window_id: u64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.inject_pointer_leave(WindowId { id: window_id }, timestamp_ms);
    }));
}

/// Inject pointer axis (scroll) event
/// axis: 0 = vertical, 1 = horizontal
#[no_mangle]
pub extern "C" fn WWNCoreInjectPointerAxis(
    core: *mut WWNCore,
    window_id: u64,
    axis: u32,
    value: f64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        let pa = if axis == 1 { PointerAxis::Horizontal } else { PointerAxis::Vertical };
        core.inject_pointer_axis(
            WindowId { id: window_id },
            pa,
            value,
            0,
            AxisSource::Finger,
            timestamp_ms,
        );
    }));
}

/// Inject keyboard key event
/// keycode: Linux key code
/// state: 0 = Released, 1 = Pressed
#[no_mangle]
pub extern "C" fn WWNCoreInjectKey(
    core: *mut WWNCore,
    keycode: u32,
    state: u32,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let key_state = if state == 1 { KeyState::Pressed } else { KeyState::Released };
        
        core.inject_key(keycode, key_state, timestamp_ms);
    }));
}

/// Inject keyboard modifiers
#[no_mangle]
pub extern "C" fn WWNCoreInjectModifiers(
    core: *mut WWNCore,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let modifiers = KeyboardModifiers {
            mods_depressed,
            mods_latched,
            mods_locked,
            group,
        };
        
        core.inject_modifiers(modifiers);
    }));
}

/// Inject keyboard enter event
#[no_mangle]
pub extern "C" fn WWNCoreInjectKeyboardEnter(
    core: *mut WWNCore,
    window_id: u64,
    keys: *const u32,
    count: usize,
    _timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let key_slice = if keys.is_null() || count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(keys, count) }
        };
        
        // Convert slice to Vec for API compliance
        let keys_vec = key_slice.to_vec();
        core.inject_keyboard_enter(WindowId { id: window_id }, keys_vec);
    }));
}

/// Inject keyboard leave event
#[no_mangle]
pub extern "C" fn WWNCoreInjectKeyboardLeave(
    core: *mut WWNCore,
    window_id: u64
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.inject_keyboard_leave(WindowId { id: window_id });
    }));
}

// ============================================================================
// Text Input (IME / Emoji)
// ============================================================================

/// Commit a UTF-8 string to the focused Wayland client via text-input-v3.
///
/// This is how platform IME, emoji pickers, and composed text reach the
/// client.  `text` must be a valid NUL-terminated C string.
#[no_mangle]
pub extern "C" fn WWNCoreTextInputCommit(
    core: *mut WWNCore,
    text: *const c_char
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() || text.is_null() { return; }
        let core = unsafe { &*core };
        let s = unsafe { CStr::from_ptr(text) };
        if let Ok(text_str) = s.to_str() {
            core.text_input_commit_string(text_str);
        }
    }));
}

/// Send a preedit (composition preview) string via text-input-v3.
///
/// `cursor_begin` and `cursor_end` are byte offsets into `text`.
/// Pass (0, 0) when not applicable.
#[no_mangle]
pub extern "C" fn WWNCoreTextInputPreedit(
    core: *mut WWNCore,
    text: *const c_char,
    cursor_begin: i32,
    cursor_end: i32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() || text.is_null() { return; }
        let core = unsafe { &*core };
        let s = unsafe { CStr::from_ptr(text) };
        if let Ok(text_str) = s.to_str() {
            core.text_input_preedit_string(text_str, cursor_begin, cursor_end);
        }
    }));
}

/// Delete surrounding text relative to the cursor via text-input-v3.
#[no_mangle]
pub extern "C" fn WWNCoreTextInputDeleteSurrounding(
    core: *mut WWNCore,
    before_length: u32,
    after_length: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        core.text_input_delete_surrounding(before_length, after_length);
    }));
}

/// Get surrounding text reported by the Wayland client.
/// Writes the text (as a UTF-8 C string) into `out_buf` (up to `buf_len` bytes),
/// and writes cursor/anchor byte offsets to `out_cursor`/`out_anchor`.
/// Returns the number of bytes written (excluding NUL terminator).
#[no_mangle]
pub extern "C" fn WWNCoreTextInputGetSurrounding(
    core: *mut WWNCore,
    out_buf: *mut u8,
    buf_len: u32,
    out_cursor: *mut i32,
    out_anchor: *mut i32,
) -> u32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() || out_buf.is_null() { return 0; }
        let core = unsafe { &*core };
        let (text, cursor, anchor) = core.text_input_get_surrounding();
        if !out_cursor.is_null() { unsafe { *out_cursor = cursor; } }
        if !out_anchor.is_null() { unsafe { *out_anchor = anchor; } }
        let bytes = text.as_bytes();
        let copy_len = std::cmp::min(bytes.len(), (buf_len as usize).saturating_sub(1));
        if copy_len > 0 {
            unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, copy_len); }
        }
        unsafe { *out_buf.add(copy_len) = 0; } // NUL terminate
        copy_len as u32
    })) {
        Ok(n) => n,
        Err(_) => 0,
    }
}

/// Get content type (hint, purpose) reported by the Wayland client.
#[no_mangle]
pub extern "C" fn WWNCoreTextInputGetContentType(
    core: *mut WWNCore,
    out_hint: *mut u32,
    out_purpose: *mut u32,
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        let (hint, purpose) = core.text_input_get_content_type();
        if !out_hint.is_null() { unsafe { *out_hint = hint; } }
        if !out_purpose.is_null() { unsafe { *out_purpose = purpose; } }
    }));
}

/// Get the cursor rectangle reported by the focused Wayland client
/// via `set_cursor_rectangle`.  The platform uses this to position
/// IME candidate windows and emoji pickers near the text cursor.
///
/// Coordinates are in surface-local pixels.
#[no_mangle]
pub extern "C" fn WWNCoreTextInputGetCursorRect(
    core: *mut WWNCore,
    out_x: *mut i32,
    out_y: *mut i32,
    out_width: *mut i32,
    out_height: *mut i32,
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        let (x, y, w, h) = core.text_input_get_cursor_rect();
        if !out_x.is_null() { unsafe { *out_x = x; } }
        if !out_y.is_null() { unsafe { *out_y = y; } }
        if !out_width.is_null() { unsafe { *out_width = w; } }
        if !out_height.is_null() { unsafe { *out_height = h; } }
    }));
}

// ============================================================================
// Touch Injection
// ============================================================================

/// Inject touch down event
#[no_mangle]
pub extern "C" fn WWNCoreInjectTouchDown(
    core: *mut WWNCore,
    id: i32,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let event = super::types::InputEvent::TouchDown {
            id,
            x,
            y,
            time_ms: timestamp_ms,
        };
        
        core.inject_input_event(event);
    }));
}

/// Inject touch up event
#[no_mangle]
pub extern "C" fn WWNCoreInjectTouchUp(
    core: *mut WWNCore,
    id: i32,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let event = super::types::InputEvent::TouchUp {
            id,
            time_ms: timestamp_ms,
        };
        
        core.inject_input_event(event);
    }));
}

/// Inject touch motion event
#[no_mangle]
pub extern "C" fn WWNCoreInjectTouchMotion(
    core: *mut WWNCore,
    id: i32,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let event = super::types::InputEvent::TouchMotion {
            id,
            x,
            y,
            time_ms: timestamp_ms,
        };
        
        core.inject_input_event(event);
    }));
}

/// Inject touch cancel event
#[no_mangle]
pub extern "C" fn WWNCoreInjectTouchCancel(
    core: *mut WWNCore
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let event = super::types::InputEvent::TouchCancel;
        core.inject_input_event(event);
    }));
}

/// Inject touch frame event
#[no_mangle]
pub extern "C" fn WWNCoreInject_touch_frame(
    core: *mut WWNCore
) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return; }
        let core = unsafe { &*core };
        
        let event = super::types::InputEvent::TouchFrame;
        core.inject_input_event(event);
    }));
}

// ----------------------------------------------------------------------------
// Scene Graph API
// ----------------------------------------------------------------------------

/// C-compatible RenderNode structure
#[repr(C)]
pub struct CRenderNode {
    pub node_id: u64,
    pub window_id: u64,
    pub surface_id: u32,
    pub buffer_id: u64,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub scale: f32,
    pub opacity: f32,
    pub corner_radius: f32,
    pub is_opaque: bool,
    pub buffer_width: u32,
    pub buffer_height: u32,
    pub buffer_stride: u32,
    pub buffer_format: u32,
    pub iosurface_id: u32,
    /// Anchor position in output space for subsurface positioning
    pub anchor_output_x: f32,
    pub anchor_output_y: f32,
    /// Normalized content rect within buffer (0..1). Default: (0,0,1,1).
    pub content_rect_x: f32,
    pub content_rect_y: f32,
    pub content_rect_w: f32,
    pub content_rect_h: f32,
}

/// C-compatible RenderScene structure
#[repr(C)]
pub struct CRenderScene {
    pub nodes: *mut CRenderNode,
    pub count: usize,
    pub capacity: usize,
    // Cursor state — populated when a Wayland client has set a cursor surface
    pub has_cursor: bool,
    pub cursor_x: f32,
    pub cursor_y: f32,
    pub cursor_hotspot_x: f32,
    pub cursor_hotspot_y: f32,
    pub cursor_buffer_id: u64,
    pub cursor_width: u32,
    pub cursor_height: u32,
    pub cursor_stride: u32,
    pub cursor_format: u32,
    pub cursor_iosurface_id: u32,
}

/// Get the current render scene
/// Caller must free the returned pointer with WWNRenderSceneFree
#[no_mangle]
pub extern "C" fn WWNCoreGetRenderScene(core: *mut WWNCore) -> *mut CRenderScene {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() { return std::ptr::null_mut(); }
        let core = unsafe { &*core };
        
        let scene = core.get_render_scene();
        let mut c_nodes = Vec::with_capacity(scene.nodes.len());
        
        for node in scene.nodes {
            let buffer_id = node.texture.handle;
            let info = core.get_buffer_render_info(node.texture);
            let (stride, format, iosurface_id, width, height) = (info.stride, info.format, info.iosurface_id, info.width, info.height);
            
            c_nodes.push(CRenderNode {
                node_id: 0, 
                window_id: node.window_id.id,
                surface_id: node.surface_id.id,
                buffer_id,
                x: node.x as f32,
                y: node.y as f32,
                width: node.width as f32,
                height: node.height as f32,
                scale: node.scale,
                opacity: node.opacity,
                corner_radius: 0.0,
                is_opaque: false, 
                buffer_width: width,
                buffer_height: height,
                buffer_stride: stride,
                buffer_format: format,
                iosurface_id,
                anchor_output_x: node.anchor_output_x as f32,
                anchor_output_y: node.anchor_output_y as f32,
                content_rect_x: node.content_rect.x,
                content_rect_y: node.content_rect.y,
                content_rect_w: node.content_rect.w,
                content_rect_h: node.content_rect.h,
            });
        }
        
        let cursor_info = core.get_cursor_render_info();

        let c_scene = Box::new(CRenderScene {
            nodes: c_nodes.as_mut_ptr(),
            count: c_nodes.len(),
            capacity: c_nodes.capacity(),
            has_cursor: cursor_info.has_cursor,
            cursor_x: cursor_info.x,
            cursor_y: cursor_info.y,
            cursor_hotspot_x: cursor_info.hotspot_x,
            cursor_hotspot_y: cursor_info.hotspot_y,
            cursor_buffer_id: cursor_info.buffer_id,
            cursor_width: cursor_info.width,
            cursor_height: cursor_info.height,
            cursor_stride: cursor_info.stride,
            cursor_format: cursor_info.format,
            cursor_iosurface_id: cursor_info.iosurface_id,
        });
        std::mem::forget(c_nodes);
        
        Box::into_raw(c_scene)
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCoreGetRenderScene panicked; returning NULL scene"
            );
            std::ptr::null_mut()
        }
    }
}

/// Free a RenderScene
#[no_mangle]
pub extern "C" fn WWNRenderSceneFree(scene: *mut CRenderScene) {
    if !scene.is_null() {
        unsafe {
            let scene = Box::from_raw(scene);
            if !scene.nodes.is_null() && scene.capacity > 0 {
                let _ = Vec::from_raw_parts(scene.nodes, scene.count, scene.capacity);
            }
        }
    }
}

// ----------------------------------------------------------------------------
// Screencopy API (zwlr_screencopy_manager_v1)
// ----------------------------------------------------------------------------

/// Screencopy request — platform writes ARGB8888 pixels to ptr, then calls WWNCoreScreencopyDone
#[repr(C)]
pub struct CScreencopyRequest {
    pub capture_id: u64,
    pub ptr: *mut std::ffi::c_void,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub size: usize,
}

/// Get the first pending screencopy. Returns capture_id=0 if none.
/// Platform must memcpy ARGB8888 pixels to ptr, then call WWNCoreScreencopyDone(capture_id).
#[no_mangle]
pub extern "C" fn WWNCoreGetPendingScreencopy(core: *mut WWNCore) -> CScreencopyRequest {
    let empty = || CScreencopyRequest {
        capture_id: 0,
        ptr: std::ptr::null_mut(),
        width: 0,
        height: 0,
        stride: 0,
        size: 0,
    };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return empty();
        }
        let core = unsafe { &*core };
        core.get_pending_screencopy()
            .map(|r| CScreencopyRequest {
                capture_id: r.capture_id,
                ptr: r.ptr as *mut std::ffi::c_void,
                width: r.width,
                height: r.height,
                stride: r.stride,
                size: r.size as usize,
            })
            .unwrap_or_else(empty)
    })) {
        Ok(req) => req,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCoreGetPendingScreencopy panicked; returning empty request"
            );
            empty()
        }
    }
}

/// Notify screencopy capture complete (platform has written pixels)
#[no_mangle]
pub extern "C" fn WWNCoreScreencopyDone(core: *mut WWNCore, capture_id: u64) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        let core = unsafe { &*core };
        core.screencopy_done(capture_id);
    }));
}

/// Notify screencopy capture failed
#[no_mangle]
pub extern "C" fn WWNCoreScreencopyFailed(core: *mut WWNCore, capture_id: u64) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        let core = unsafe { &*core };
        core.screencopy_failed(capture_id);
    }));
}

// ----------------------------------------------------------------------------
// Image Copy Capture API (ext-image-copy-capture-v1, desktop-protocols only)
// ----------------------------------------------------------------------------

/// Get the first pending image copy capture. Returns capture_id=0 if none.
/// Same structure as screencopy; platform writes ARGB8888 pixels then calls WWNCoreImageCopyCaptureDone.
#[cfg(feature = "desktop-protocols")]
#[no_mangle]
pub extern "C" fn WWNCoreGetPendingImageCopyCapture(core: *mut WWNCore) -> CScreencopyRequest {
    let empty = || CScreencopyRequest {
        capture_id: 0,
        ptr: std::ptr::null_mut(),
        width: 0,
        height: 0,
        stride: 0,
        size: 0,
    };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return empty();
        }
        let core = unsafe { &*core };
        core.get_pending_image_copy_capture()
            .map(|r| CScreencopyRequest {
                capture_id: r.capture_id,
                ptr: r.ptr as *mut std::ffi::c_void,
                width: r.width,
                height: r.height,
                stride: r.stride,
                size: r.size as usize,
            })
            .unwrap_or_else(empty)
    })) {
        Ok(req) => req,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCoreGetPendingImageCopyCapture panicked; returning empty request"
            );
            empty()
        }
    }
}

#[cfg(not(feature = "desktop-protocols"))]
#[no_mangle]
pub extern "C" fn WWNCoreGetPendingImageCopyCapture(core: *mut WWNCore) -> CScreencopyRequest {
    let _ = core;
    CScreencopyRequest {
        capture_id: 0,
        ptr: std::ptr::null_mut(),
        width: 0,
        height: 0,
        stride: 0,
        size: 0,
    }
}

/// Notify image copy capture complete
#[cfg(feature = "desktop-protocols")]
#[no_mangle]
pub extern "C" fn WWNCoreImageCopyCaptureDone(core: *mut WWNCore, capture_id: u64) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        let core = unsafe { &*core };
        core.image_copy_capture_done(capture_id);
    }));
}

#[cfg(not(feature = "desktop-protocols"))]
#[no_mangle]
pub extern "C" fn WWNCoreImageCopyCaptureDone(_core: *mut WWNCore, _capture_id: u64) {
    // No-op when desktop-protocols disabled
}

/// Notify image copy capture failed
#[cfg(feature = "desktop-protocols")]
#[no_mangle]
pub extern "C" fn WWNCoreImageCopyCaptureFailed(core: *mut WWNCore, capture_id: u64) {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return;
        }
        let core = unsafe { &*core };
        core.image_copy_capture_failed(capture_id);
    }));
}

#[cfg(not(feature = "desktop-protocols"))]
#[no_mangle]
pub extern "C" fn WWNCoreImageCopyCaptureFailed(_core: *mut WWNCore, _capture_id: u64) {
    // No-op when desktop-protocols disabled
}

// ----------------------------------------------------------------------------
// Gamma Control API (zwlr_gamma_control_manager_v1)
// ----------------------------------------------------------------------------

/// Gamma ramp apply — platform uses CGSetDisplayTransferByTable.
/// Convert u16 (0-65535) to float (0-1) for CGGammaValue.
#[repr(C)]
pub struct CGammaApply {
    pub output_id: u32,
    pub size: u32,
    pub red: *const u16,
    pub green: *const u16,
    pub blue: *const u16,
}

/// Gamma apply with owned buffers (CGammaApply is first field, same address)
#[repr(C)]
struct GammaApplyOwned {
    c: CGammaApply,
    _red: Box<[u16]>,
    _green: Box<[u16]>,
    _blue: Box<[u16]>,
}

/// Pop pending gamma apply. Caller must free with WWNGammaApplyFree.
#[no_mangle]
pub extern "C" fn WWNCorePopPendingGammaApply(core: *mut WWNCore) -> *mut CGammaApply {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return std::ptr::null_mut();
        }
        let core = unsafe { &*core };
        if let Some(apply) = core.pop_pending_gamma_apply() {
            let red = apply.red.into_boxed_slice();
            let green = apply.green.into_boxed_slice();
            let blue = apply.blue.into_boxed_slice();
            let owned = Box::new(GammaApplyOwned {
                c: CGammaApply {
                    output_id: apply.output_id,
                    size: apply.size,
                    red: red.as_ptr(),
                    green: green.as_ptr(),
                    blue: blue.as_ptr(),
                },
                _red: red,
                _green: green,
                _blue: blue,
            });
            let ptr = Box::into_raw(owned);
            ptr as *mut CGammaApply
        } else {
            std::ptr::null_mut()
        }
    })) {
        Ok(ptr) => ptr,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCorePopPendingGammaApply panicked; returning NULL"
            );
            std::ptr::null_mut()
        }
    }
}

/// Free gamma apply (call after platform has applied)
#[no_mangle]
pub extern "C" fn WWNGammaApplyFree(apply: *mut CGammaApply) {
    if !apply.is_null() {
        let _ = unsafe { Box::from_raw(apply as *mut GammaApplyOwned) };
    }
}

/// Pop pending gamma restore (output_id to restore)
/// Returns 0 if none, or output_id to restore
#[no_mangle]
pub extern "C" fn WWNCorePopPendingGammaRestore(core: *mut WWNCore) -> u32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if core.is_null() {
            return 0;
        }
        let core = unsafe { &*core };
        core.pop_pending_gamma_restore().unwrap_or(0)
    })) {
        Ok(output_id) => output_id,
        Err(_) => {
            crate::wlog!(
                crate::util::logging::C_API,
                "WWNCorePopPendingGammaRestore panicked; returning 0"
            );
            0
        }
    }
}
