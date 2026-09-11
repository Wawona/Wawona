//! Platform callbacks trait
//!
//! Platforms (macOS, iOS, Android) must implement this trait to receive
//! callbacks from the Rust core compositor.
//!
//! The compositor calls these methods to request platform-specific actions
//! such as creating windows, uploading textures, and setting cursor shapes.
//!
//! NOTE: These traits are for internal Rust use. For FFI, we use a polling
//! model instead of callbacks (see api.rs poll_* methods).

use crate::ffi::types::*;
use std::sync::Arc;

// ============================================================================
// Platform Callbacks (Rust → Platform, internal use)
// ============================================================================

/// Platform callbacks interface (for internal Rust platform adapters)
///
/// This trait is implemented by Rust platform adapters (macOS, iOS, Android)
/// to handle compositor events. It is NOT exposed via UniFFI.
///
/// For FFI-based platforms, use the polling API instead:
/// - poll_window_events()
/// - poll_client_events()
/// - poll_pending_buffers()
/// - poll_redraw_requests()
pub trait PlatformCallbacks: Send + Sync {
    // ===== Window Lifecycle =====

    /// Create a native window with the given configuration
    fn create_window(&self, config: WindowConfig) -> WindowId;

    /// Destroy a native window
    fn destroy_window(&self, window_id: WindowId);

    /// Set the window title
    fn set_window_title(&self, window_id: WindowId, title: String);

    /// Set the window state
    fn set_window_state(&self, window_id: WindowId, state: WindowState);

    /// Set the decoration mode
    fn set_decoration_mode(&self, window_id: WindowId, mode: DecorationMode);

    /// Resize the window
    fn resize_window(&self, window_id: WindowId, width: u32, height: u32);

    // ===== Rendering =====

    /// Upload a buffer to GPU and return texture handle
    fn upload_buffer(&self, buffer: Buffer) -> TextureHandle;

    /// Release a texture
    fn release_texture(&self, texture: TextureHandle);

    /// Request a redraw
    fn request_redraw(&self, window_id: WindowId);

    // ===== Cursor =====

    /// Set cursor shape
    fn set_cursor_shape(&self, shape: CursorShape);

    /// Set custom cursor image
    fn set_cursor_image(&self, texture: TextureHandle, hotspot_x: i32, hotspot_y: i32);

    /// Hide cursor
    fn hide_cursor(&self);

    // ===== Platform Info =====

    /// Get vsync interval in nanoseconds
    fn get_vsync_interval_ns(&self) -> u64;

    /// Get available outputs
    fn get_outputs(&self) -> Vec<OutputInfo>;

    // ===== Logging =====

    /// Log a message
    fn log_message(&self, level: String, message: String);

    // ===== Clipboard =====

    /// Set clipboard text
    fn set_clipboard_text(&self, text: String);

    /// Get clipboard text
    fn get_clipboard_text(&self) -> Option<String>;
}

/// Type alias for callback handle
pub type PlatformCallbacksHandle = Arc<dyn PlatformCallbacks>;

// ============================================================================
// Event Listener (for internal Rust use)
// ============================================================================

/// Event listener for async compositor events (internal Rust use)
pub trait CompositorEventListener: Send + Sync {
    fn on_window_event(&self, event: WindowEvent);
    fn on_client_event(&self, event: ClientEvent);
    fn on_frame(&self, timestamp_ns: u64);
}

/// Type alias for event listener handle
pub type CompositorEventListenerHandle = Arc<dyn CompositorEventListener>;

// ============================================================================
// Stub Implementations (for testing)
// ============================================================================

/// Stub platform callbacks for testing
#[derive(Debug)]
pub struct StubPlatformCallbacks {
    next_window_id: std::sync::atomic::AtomicU64,
    next_texture_handle: std::sync::atomic::AtomicU64,
}

impl StubPlatformCallbacks {
    pub fn new() -> Self {
        Self {
            next_window_id: std::sync::atomic::AtomicU64::new(1),
            next_texture_handle: std::sync::atomic::AtomicU64::new(1),
        }
    }
}

impl Default for StubPlatformCallbacks {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformCallbacks for StubPlatformCallbacks {
    fn create_window(&self, _config: WindowConfig) -> WindowId {
        let id = self
            .next_window_id
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        WindowId::new(id)
    }

    fn destroy_window(&self, _window_id: WindowId) {}
    fn set_window_title(&self, _window_id: WindowId, _title: String) {}
    fn set_window_state(&self, _window_id: WindowId, _state: WindowState) {}
    fn set_decoration_mode(&self, _window_id: WindowId, _mode: DecorationMode) {}
    fn resize_window(&self, _window_id: WindowId, _width: u32, _height: u32) {}

    fn upload_buffer(&self, _buffer: Buffer) -> TextureHandle {
        let handle = self
            .next_texture_handle
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        TextureHandle::new(handle, crate::ffi::types::ClientId::default())
    }

    fn release_texture(&self, _texture: TextureHandle) {}
    fn request_redraw(&self, _window_id: WindowId) {}
    fn set_cursor_shape(&self, _shape: CursorShape) {}
    fn set_cursor_image(&self, _texture: TextureHandle, _hotspot_x: i32, _hotspot_y: i32) {}
    fn hide_cursor(&self) {}

    fn get_vsync_interval_ns(&self) -> u64 {
        16_666_666 // ~60Hz
    }

    fn get_outputs(&self) -> Vec<OutputInfo> {
        vec![OutputInfo::new(OutputId::new(1), "default".to_string())]
    }

    fn log_message(&self, level: String, message: String) {
        tracing::info!("[{}] {}", level, message);
    }

    fn set_clipboard_text(&self, _text: String) {}
    fn get_clipboard_text(&self) -> Option<String> {
        None
    }
}

/// Stub event listener for testing
#[derive(Debug, Default)]
pub struct StubEventListener;

impl CompositorEventListener for StubEventListener {
    fn on_window_event(&self, event: WindowEvent) {
        tracing::debug!("Window event: {:?}", event);
    }

    fn on_client_event(&self, event: ClientEvent) {
        tracing::debug!("Client event: {:?}", event);
    }

    fn on_frame(&self, timestamp_ns: u64) {
        tracing::trace!("Frame callback: {} ns", timestamp_ns);
    }
}
