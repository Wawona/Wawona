//! FFI-safe types for cross-platform communication
//! These types are exported via UniFFI and can be used from Kotlin, Swift, Python, etc.



// Re-export for convenience
pub use crate::util::geometry::{Point as UtilPoint, Rect as UtilRect};

// ============================================================================
// Identifiers
// ============================================================================

/// Window identifier (maps to native platform window)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct WindowId {
    pub id: u64,
}

impl WindowId {
    pub fn new(id: u64) -> Self {
        Self { id }
    }
    
    pub fn null() -> Self {
        Self { id: 0 }
    }
    
    pub fn is_null(&self) -> bool {
        self.id == 0
    }
}

impl Default for WindowId {
    fn default() -> Self {
        Self::null()
    }
}

/// Surface identifier (Wayland surface)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct SurfaceId {
    pub id: u32,
}

impl SurfaceId {
    pub fn new(id: u32) -> Self {
        Self { id }
    }
    
    pub fn null() -> Self {
        Self { id: 0 }
    }
    
    pub fn is_null(&self) -> bool {
        self.id == 0
    }
}

impl Default for SurfaceId {
    fn default() -> Self {
        Self::null()
    }
}

/// Buffer identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct BufferId {
    pub id: u64,
}

impl BufferId {
    pub fn new(id: u64) -> Self {
        Self { id }
    }
    
    pub fn null() -> Self {
        Self { id: 0 }
    }
    
    pub fn is_null(&self) -> bool {
        self.id == 0
    }
}

impl Default for BufferId {
    fn default() -> Self {
        Self::null()
    }
}

/// Output identifier (display/monitor)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct OutputId {
    pub id: u32,
}

impl OutputId {
    pub fn new(id: u32) -> Self {
        Self { id }
    }
}

impl Default for OutputId {
    fn default() -> Self {
        Self { id: 0 }
    }
}

/// Client identifier (Wayland client connection)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct ClientId {
    pub id: u32,
}

impl ClientId {
    pub fn new(id: u32) -> Self {
        Self { id }
    }
}

impl Default for ClientId {
    fn default() -> Self {
        Self { id: 0 }
    }
}

/// Opaque texture handle from platform
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Record)]
pub struct TextureHandle {
    pub handle: u64,
    pub client_id: ClientId,
}

impl TextureHandle {
    pub fn new(handle: u64, client_id: ClientId) -> Self {
        Self { handle, client_id }
    }
    
    pub fn null() -> Self {
        Self { handle: 0, client_id: ClientId::default() }
    }
    
    pub fn is_null(&self) -> bool {
        self.handle == 0
    }
}

impl Default for TextureHandle {
    fn default() -> Self {
        Self::null()
    }
}

// ============================================================================
// Geometry Types
// ============================================================================

/// 2D point (FFI-safe)
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

impl Point {
    pub fn new(x: f64, y: f64) -> Self {
        Self { x, y }
    }
    
    pub fn zero() -> Self {
        Self { x: 0.0, y: 0.0 }
    }
}

impl Default for Point {
    fn default() -> Self {
        Self::zero()
    }
}

impl From<UtilPoint> for Point {
    fn from(p: UtilPoint) -> Self {
        Self { x: p.x, y: p.y }
    }
}

/// 2D size (FFI-safe)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct Size {
    pub width: u32,
    pub height: u32,
}

impl Size {
    pub fn new(width: u32, height: u32) -> Self {
        Self { width, height }
    }
    
    pub fn zero() -> Self {
        Self { width: 0, height: 0 }
    }
}

impl Default for Size {
    fn default() -> Self {
        Self::zero()
    }
}

/// 2D rectangle (FFI-safe)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

/// Normalized content rect within a buffer (0..1 range, FFI-safe).
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct ContentRect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl Default for ContentRect {
    fn default() -> Self {
        Self { x: 0.0, y: 0.0, w: 1.0, h: 1.0 }
    }
}

impl Rect {
    pub fn new(x: i32, y: i32, width: u32, height: u32) -> Self {
        Self { x, y, width, height }
    }
    
    pub fn zero() -> Self {
        Self { x: 0, y: 0, width: 0, height: 0 }
    }
    
    pub fn contains_point(&self, px: i32, py: i32) -> bool {
        px >= self.x 
            && px < self.x + self.width as i32
            && py >= self.y
            && py < self.y + self.height as i32
    }
}

impl Default for Rect {
    fn default() -> Self {
        Self::zero()
    }
}

impl From<UtilRect> for Rect {
    fn from(r: UtilRect) -> Self {
        Self {
            x: r.x,
            y: r.y,
            width: r.width,
            height: r.height,
        }
    }
}

/// 4x4 transformation matrix (column-major)
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct Mat4 {
    pub data: Vec<f32>, // 16 elements
}

impl Mat4 {
    pub fn identity() -> Self {
        Self {
            data: vec![
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            ],
        }
    }
    
    pub fn translation(x: f32, y: f32, z: f32) -> Self {
        Self {
            data: vec![
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                x,   y,   z,   1.0,
            ],
        }
    }
    
    pub fn scale(x: f32, y: f32, z: f32) -> Self {
        Self {
            data: vec![
                x,   0.0, 0.0, 0.0,
                0.0, y,   0.0, 0.0,
                0.0, 0.0, z,   0.0,
                0.0, 0.0, 0.0, 1.0,
            ],
        }
    }
}

impl Default for Mat4 {
    fn default() -> Self {
        Self::identity()
    }
}

// ============================================================================
// Output/Display Types
// ============================================================================

/// Output transform (rotation/reflection)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum OutputTransform {
    Normal,
    Rotate90,
    Rotate180,
    Rotate270,
    Flipped,
    FlippedRotate90,
    FlippedRotate180,
    FlippedRotate270,
}

impl Default for OutputTransform {
    fn default() -> Self {
        Self::Normal
    }
}

/// Output subpixel layout
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum OutputSubpixel {
    Unknown,
    None,
    HorizontalRgb,
    HorizontalBgr,
    VerticalRgb,
    VerticalBgr,
}

impl Default for OutputSubpixel {
    fn default() -> Self {
        Self::Unknown
    }
}

/// Output mode (resolution/refresh rate)
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct OutputMode {
    pub width: u32,
    pub height: u32,
    pub refresh_mhz: u32,  // Refresh rate in millihertz
    pub preferred: bool,
    pub current: bool,
}

impl OutputMode {
    pub fn new(width: u32, height: u32, refresh_mhz: u32) -> Self {
        Self {
            width,
            height,
            refresh_mhz,
            preferred: false,
            current: false,
        }
    }
}

/// Complete output information
#[derive(Debug, Clone, uniffi::Record)]
pub struct OutputInfo {
    pub id: OutputId,
    pub name: String,
    pub make: String,
    pub model: String,
    pub x: i32,
    pub y: i32,
    pub physical_width_mm: u32,
    pub physical_height_mm: u32,
    pub subpixel: OutputSubpixel,
    pub transform: OutputTransform,
    pub scale: f32,
    pub modes: Vec<OutputMode>,
}

impl OutputInfo {
    pub fn new(id: OutputId, name: String) -> Self {
        Self {
            id,
            name,
            make: String::new(),
            model: String::new(),
            x: 0,
            y: 0,
            physical_width_mm: 0,
            physical_height_mm: 0,
            subpixel: OutputSubpixel::Unknown,
            transform: OutputTransform::Normal,
            scale: 1.0,
            modes: vec![],
        }
    }
}

// ============================================================================
// Window Types
// ============================================================================

/// Window decoration mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum DecorationMode {
    ClientSide,  // CSD - client draws decorations
    ServerSide,  // SSD - compositor draws decorations
}

impl Default for DecorationMode {
    fn default() -> Self {
        Self::ServerSide
    }
}

/// Window state
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum WindowState {
    Normal,
    Maximized,
    Fullscreen,
    Minimized,
    Tiled,
}

impl Default for WindowState {
    fn default() -> Self {
        Self::Normal
    }
}

/// Window resize edge
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ResizeEdge {
    None,
    Top,
    Bottom,
    Left,
    Right,
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

impl ResizeEdge {
    pub fn from_u32(val: u32) -> Self {
        match val {
            1 => ResizeEdge::Top,
            2 => ResizeEdge::Bottom,
            4 => ResizeEdge::Left,
            5 => ResizeEdge::TopLeft,
            6 => ResizeEdge::BottomLeft,
            8 => ResizeEdge::Right,
            9 => ResizeEdge::TopRight,
            10 => ResizeEdge::BottomRight,
            _ => ResizeEdge::None,
        }
    }

    pub fn to_u32(self) -> u32 {
        match self {
            ResizeEdge::None => 0,
            ResizeEdge::Top => 1,
            ResizeEdge::Bottom => 2,
            ResizeEdge::Left => 4,
            ResizeEdge::TopLeft => 5,
            ResizeEdge::BottomLeft => 6,
            ResizeEdge::Right => 8,
            ResizeEdge::TopRight => 9,
            ResizeEdge::BottomRight => 10,
        }
    }
}

impl Default for ResizeEdge {
    fn default() -> Self {
        Self::None
    }
}

/// What kind of size payload an event carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GeometrySizeKind {
    /// Host window frame (including native chrome).
    Frame,
    /// Drawable content area (excluding host chrome).
    Content,
    /// Client-submitted buffer dimensions.
    Buffer,
}

impl Default for GeometrySizeKind {
    fn default() -> Self {
        Self::Content
    }
}

/// Why a size/configure transition occurred.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum WindowSizeCause {
    Unknown,
    /// Host requested resize and compositor emitted configure.
    HostConfigure,
    /// Client committed a new surface size.
    ClientCommit,
    /// Output mode/scale update triggered relayout.
    OutputModeChange,
}

impl Default for WindowSizeCause {
    fn default() -> Self {
        Self::Unknown
    }
}

/// Correlates host resize requests to configure/ack/commit lifecycle.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ResizeTransaction {
    pub id: u64,
    pub window_id: WindowId,
    pub configure_serial: u32,
    pub cause: WindowSizeCause,
    pub requested_size: Size,
    pub size_kind: GeometrySizeKind,
}

/// Window configuration for creation
#[derive(Debug, Clone, uniffi::Record)]
pub struct WindowConfig {
    pub title: String,
    pub app_id: String,
    pub width: u32,
    pub height: u32,
    pub min_width: Option<u32>,
    pub min_height: Option<u32>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub decoration_mode: DecorationMode,
    /// True when this window is from fullscreen shell (kiosk); host must not draw window chrome
    pub fullscreen_shell: bool,
    /// Stable per-connection id (maps nested kiosk + xdg to one host window on Linux/GTK).
    pub owner_client_internal_id: u64,
    pub state: WindowState,
    pub parent: Option<WindowId>,
}

impl WindowConfig {
    pub fn new(title: String, width: u32, height: u32) -> Self {
        Self {
            title,
            app_id: String::new(),
            width,
            height,
            min_width: None,
            min_height: None,
            max_width: None,
            max_height: None,
            decoration_mode: DecorationMode::ServerSide,
            fullscreen_shell: false,
            owner_client_internal_id: 0,
            state: WindowState::Normal,
            parent: None,
        }
    }
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self::new("Untitled".to_string(), 800, 600)
    }
}

/// Window information (read-only snapshot)
#[derive(Debug, Clone, uniffi::Record)]
pub struct WindowInfo {
    pub id: WindowId,
    pub surface_id: SurfaceId,
    pub title: String,
    pub app_id: String,
    pub width: u32,
    pub height: u32,
    pub decoration_mode: DecorationMode,
    pub state: WindowState,
    pub activated: bool,
    pub resizing: bool,
}

impl WindowInfo {
    pub fn new(id: WindowId, surface_id: SurfaceId) -> Self {
        Self {
            id,
            surface_id,
            title: String::new(),
            app_id: String::new(),
            width: 0,
            height: 0,
            decoration_mode: DecorationMode::ServerSide,
            state: WindowState::Normal,
            activated: false,
            resizing: false,
        }
    }
}

/// Window event (notification from core to platform)
#[derive(Debug, Clone, uniffi::Enum)]
pub enum WindowEvent {
    // Window lifecycle
    Created { window_id: WindowId, config: WindowConfig },
    Destroyed { window_id: WindowId },
    
    // Window state changes
    TitleChanged { window_id: WindowId, title: String },
    AppIdChanged { window_id: WindowId, app_id: String },
    StateChanged { window_id: WindowId, state: WindowState },
    DecorationModeChanged { window_id: WindowId, mode: DecorationMode },
    SizeChanged {
        window_id: WindowId,
        width: u32,
        height: u32,
        cause: WindowSizeCause,
        size_kind: GeometrySizeKind,
        configure_serial: u32,
        transaction_id: u64,
    },
    
    // Focus changes
    Activated { window_id: WindowId },
    Deactivated { window_id: WindowId },
    
    // Interactive operations
    MoveRequested { window_id: WindowId, serial: u32 },
    ResizeRequested { window_id: WindowId, serial: u32, edge: ResizeEdge },
    
    // Customize popup
    PopupCreated { 
        window_id: WindowId, 
        parent_id: WindowId,
        x: i32,
        y: i32,
        width: u32,
        height: u32
    },
    PopupRepositioned {
        window_id: WindowId,
        x: i32,
        y: i32,
        width: u32,
        height: u32,
    },

    // Minimize/close requests
    MinimizeRequested { window_id: WindowId },
    MaximizeRequested { window_id: WindowId },
    UnmaximizeRequested { window_id: WindowId },
    CloseRequested { window_id: WindowId },

    // Cursor shape change (from wp_cursor_shape protocol)
    CursorShapeChanged { shape: u32 },

    // System bell / notification
    SystemBell { surface_id: u32 },
}

// ============================================================================
// Surface Types
// ============================================================================

/// Surface role
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum SurfaceRole {
    None,
    Toplevel,
    Popup,
    Subsurface,
    Cursor,
    DragIcon,
}

impl Default for SurfaceRole {
    fn default() -> Self {
        Self::None
    }
}

/// Surface state (committed state snapshot)
#[derive(Debug, Clone, uniffi::Record)]
pub struct SurfaceState {
    pub id: SurfaceId,
    pub buffer_id: Option<BufferId>,
    pub buffer_x: i32,
    pub buffer_y: i32,
    pub buffer_width: u32,
    pub buffer_height: u32,
    pub buffer_scale: f32,
    pub buffer_transform: OutputTransform,
    pub damage: Vec<Rect>,
    pub opaque_region: Vec<Rect>,
    pub input_region: Vec<Rect>,
    pub role: SurfaceRole,
}

impl SurfaceState {
    pub fn new(id: SurfaceId) -> Self {
        Self {
            id,
            buffer_id: None,
            buffer_x: 0,
            buffer_y: 0,
            buffer_width: 0,
            buffer_height: 0,
            buffer_scale: 1.0,
            buffer_transform: OutputTransform::Normal,
            damage: vec![],
            opaque_region: vec![],
            input_region: vec![],
            role: SurfaceRole::None,
        }
    }
}

// ============================================================================
// Buffer Types
// ============================================================================

/// Wayland buffer format
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BufferFormat {
    Argb8888,
    Xrgb8888,
    Rgba8888,
    Rgbx8888,
    Abgr8888,
    Xbgr8888,
    Bgra8888,
    Bgrx8888,
}

impl BufferFormat {
    /// Get bytes per pixel for this format
    pub fn bytes_per_pixel(&self) -> u32 {
        4 // All supported formats are 4 bytes per pixel
    }
    
    /// Check if format has alpha channel
    pub fn has_alpha(&self) -> bool {
        matches!(self, 
            BufferFormat::Argb8888 | 
            BufferFormat::Rgba8888 |
            BufferFormat::Abgr8888 |
            BufferFormat::Bgra8888
        )
    }
}

impl Default for BufferFormat {
    fn default() -> Self {
        Self::Argb8888
    }
}

/// Buffer data (either SHM or DMA-BUF)
#[derive(Debug, Clone, uniffi::Enum)]
pub enum BufferData {
    Shm {
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        format: BufferFormat,
        stride: u32,
    },
    DmaBuf {
        fd: i32,
        width: u32,
        height: u32,
        format: u32,
        modifier: u64,
    },
    Iosurface {
        id: u32,
        width: u32,
        height: u32,
        format: u32,
    },
}

impl BufferData {
    pub fn width(&self) -> u32 {
        match self {
            BufferData::Shm { width, .. } => *width,
            BufferData::DmaBuf { width, .. } => *width,
            BufferData::Iosurface { width, .. } => *width,
        }
    }
    
    pub fn height(&self) -> u32 {
        match self {
            BufferData::Shm { height, .. } => *height,
            BufferData::DmaBuf { height, .. } => *height,
            BufferData::Iosurface { height, .. } => *height,
        }
    }
}

/// Buffer with data
#[derive(Debug, Clone, uniffi::Record)]
pub struct Buffer {
    pub id: BufferId,
    pub data: BufferData,
}

impl Buffer {
    pub fn new_shm(
        id: BufferId,
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        format: BufferFormat,
        stride: u32,
    ) -> Self {
        Self {
            id,
            data: BufferData::Shm {
                pixels,
                width,
                height,
                format,
                stride,
            },
        }
    }
}

/// Buffer update for a specific window
#[derive(Debug, Clone, uniffi::Record)]
pub struct WindowBuffer {
    pub window_id: WindowId,
    pub surface_id: SurfaceId,
    pub buffer: Buffer,
}

/// Helper struct for buffer rendering info
#[derive(Debug, Clone, uniffi::Record)]
pub struct BufferRenderInfo {
    pub stride: u32,
    pub format: u32,
    pub iosurface_id: u32,
    pub width: u32,
    pub height: u32,
}

/// Cursor rendering info for the C API — position, hotspot, and buffer metadata.
#[derive(Debug, Clone, Default)]
pub struct CursorRenderInfo {
    pub has_cursor: bool,
    pub x: f32,
    pub y: f32,
    pub hotspot_x: f32,
    pub hotspot_y: f32,
    pub surface_id: u32,
    pub buffer_id: u64,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
    pub iosurface_id: u32,
}

/// Pending screencopy — platform writes ARGB8888 pixels to ptr, then calls screencopy_done
#[derive(Debug, Clone, uniffi::Record)]
pub struct ScreencopyRequest {
    pub capture_id: u64,
    /// Pointer to writable buffer (as u64 for FFI; cast to void* on C side)
    pub ptr: u64,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub size: u64,
}

// ============================================================================
// Input Types
// ============================================================================

/// Input event types used for injection from FFI
#[derive(Debug, Clone, uniffi::Enum)]
pub enum InputEvent {
    /// Pointer motion (absolute or relative)
    PointerMotion {
        x: f64, 
        y: f64, 
        time_ms: u32
    },
    /// Pointer button press/release
    PointerButton {
        button: u32, 
        state: ButtonState, 
        time_ms: u32
    },
    /// Pointer axis (scroll)
    PointerAxis {
        horizontal: f64,
        vertical: f64,
        time_ms: u32
    },
    /// Keyboard key press/release
    KeyboardKey {
        keycode: u32,
        state: KeyState,
        time_ms: u32
    },
    /// Keyboard modifiers update
    KeyboardModifiers {
        depressed: u32,
        latched: u32,
        locked: u32,
        group: u32
    },
    /// Touch down
    TouchDown {
        id: i32,
        x: f64,
        y: f64,
        time_ms: u32
    },
    /// Touch up
    TouchUp {
        id: i32,
        time_ms: u32
    },
    /// Touch motion
    TouchMotion {
        id: i32,
        x: f64,
        y: f64,
        time_ms: u32
    },
    /// Touch cancel
    TouchCancel,
    /// Touch frame
    TouchFrame,
}



/// Pointer button
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PointerButton {
    Left,
    Right,
    Middle,
    Back,
    Forward,
    Other(u32),
}

impl PointerButton {
    pub fn to_button_code(&self) -> u32 {
        match self {
            PointerButton::Left => 0x110,
            PointerButton::Right => 0x111,
            PointerButton::Middle => 0x112,
            PointerButton::Back => 0x116,
            PointerButton::Forward => 0x115,
            PointerButton::Other(_) => 0x113,
        }
    }
    
    pub fn from_button_code(code: u32) -> Self {
        match code {
            0x110 => PointerButton::Left,
            0x111 => PointerButton::Right,
            0x112 => PointerButton::Middle,
            0x116 => PointerButton::Back,
            0x115 => PointerButton::Forward,
            _ => PointerButton::Other(code),
        }
    }
}

impl Default for PointerButton {
    fn default() -> Self {
        Self::Left
    }
}

/// Axis source
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AxisSource {
    Wheel,
    Finger,
    Continuous,
    WheelTilt,
}

impl Default for AxisSource {
    fn default() -> Self {
        Self::Wheel
    }
}

// Re-using KeyState for ButtonState logic to align with InputEvent
pub type ButtonState = KeyState;



/// Pointer axis (scroll direction)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PointerAxis {
    Vertical,
    Horizontal,
}

impl Default for PointerAxis {
    fn default() -> Self {
        Self::Vertical
    }
}

/// Key state
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum KeyState {
    Released,
    Pressed,
}

impl KeyState {
    pub fn is_pressed(&self) -> bool {
        matches!(self, KeyState::Pressed)
    }
    
    pub fn is_released(&self) -> bool {
        matches!(self, KeyState::Released)
    }
}

impl Default for KeyState {
    fn default() -> Self {
        Self::Released
    }
}

/// Keyboard modifier flags
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct KeyboardModifiers {
    pub mods_depressed: u32,
    pub mods_latched: u32,
    pub mods_locked: u32,
    pub group: u32,
}

impl KeyboardModifiers {
    pub fn new() -> Self {
        Self {
            mods_depressed: 0,
            mods_latched: 0,
            mods_locked: 0,
            group: 0,
        }
    }
}

impl Default for KeyboardModifiers {
    fn default() -> Self {
        Self::new()
    }
}

/// Cursor shape (wp_cursor_shape protocol)
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum CursorShape {
    Default,
    ContextMenu,
    Help,
    Pointer,
    Progress,
    Wait,
    Cell,
    Crosshair,
    Text,
    VerticalText,
    Alias,
    Copy,
    Move,
    NoDrop,
    NotAllowed,
    Grab,
    Grabbing,
    EResize,
    NResize,
    NeResize,
    NwResize,
    SResize,
    SeResize,
    SwResize,
    WResize,
    EwResize,
    NsResize,
    NeswResize,
    NwseResize,
    ColResize,
    RowResize,
    AllScroll,
    ZoomIn,
    ZoomOut,
}

impl Default for CursorShape {
    fn default() -> Self {
        Self::Default
    }
}

/// Touch point information
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct TouchPoint {
    pub id: i32,
    pub x: f64,
    pub y: f64,
}

impl TouchPoint {
    pub fn new(id: i32, x: f64, y: f64) -> Self {
        Self { id, x, y }
    }
}

/// Gesture types
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GestureType {
    Pinch,
    Swipe,
    Hold,
}

impl Default for GestureType {
    fn default() -> Self {
        Self::Swipe
    }
}

/// Gesture state
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GestureState {
    Begin,
    Update,
    End,
    Cancel,
}

impl Default for GestureState {
    fn default() -> Self {
        Self::Begin
    }
}

/// Gesture event data
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct GestureEvent {
    pub gesture_type: GestureType,
    pub state: GestureState,
    pub timestamp_ms: u32,
    pub finger_count: u32,
    pub x: f64,
    pub y: f64,
    pub dx: f64,
    pub dy: f64,
    pub scale: f64,
    pub rotation: f64,
}

impl GestureEvent {
    pub fn new(gesture_type: GestureType, state: GestureState, timestamp_ms: u32) -> Self {
        Self {
            gesture_type,
            state,
            timestamp_ms,
            finger_count: 2,
            x: 0.0,
            y: 0.0,
            dx: 0.0,
            dy: 0.0,
            scale: 1.0,
            rotation: 0.0,
        }
    }
}

// ============================================================================
// Rendering Types
// ============================================================================

/// Render node in scene graph
#[derive(Debug, Clone, uniffi::Record)]
pub struct RenderNode {
    pub window_id: WindowId,
    pub surface_id: SurfaceId,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub scale: f32,
    pub opacity: f32,
    pub visible: bool,
    pub transform: Mat4,
    pub texture: TextureHandle,
    pub damage: Vec<Rect>,
    /// Anchor position in output space for subsurfaces (parent window/popup origin).
    /// Used to compute window-local coordinates: (x - anchor_output_x, y - anchor_output_y).
    /// For toplevels/popups this equals (x, y) since they are their own anchor.
    pub anchor_output_x: i32,
    pub anchor_output_y: i32,
    /// Normalized content rect within the buffer (0..1 range).
    /// Default [0,0,1,1] = full buffer. Non-default when CSD geometry crops content.
    pub content_rect: ContentRect,
}

impl RenderNode {
    pub fn new(
        window_id: WindowId,
        surface_id: SurfaceId,
        texture: TextureHandle,
    ) -> Self {
        Self {
            window_id,
            surface_id,
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            scale: 1.0,
            opacity: 1.0,
            visible: true,
            transform: Mat4::identity(),
            texture,
            damage: vec![],
            anchor_output_x: 0,
            anchor_output_y: 0,
            content_rect: ContentRect::default(),
        }
    }
}

/// Complete render scene
#[derive(Debug, Clone, uniffi::Record)]
pub struct RenderScene {
    pub nodes: Vec<RenderNode>,
    pub width: u32,
    pub height: u32,
    pub scale: f32,
    pub needs_redraw: bool,
    pub damage: Vec<Rect>,
}

impl RenderScene {
    pub fn empty() -> Self {
        Self {
            nodes: vec![],
            width: 0,
            height: 0,
            scale: 1.0,
            needs_redraw: false,
            damage: vec![],
        }
    }
    
    pub fn new(width: u32, height: u32, scale: f32) -> Self {
        Self {
            nodes: vec![],
            width,
            height,
            scale,
            needs_redraw: false,
            damage: vec![],
        }
    }
}

// ============================================================================
// Client Types
// ============================================================================

/// Client information
#[derive(Debug, Clone, uniffi::Record)]
pub struct ClientInfo {
    pub id: ClientId,
    pub pid: u32,
    pub name: Option<String>,
    pub surface_count: u32,
    pub window_count: u32,
}

impl ClientInfo {
    pub fn new(id: ClientId, pid: u32) -> Self {
        Self {
            id,
            pid,
            name: None,
            surface_count: 0,
            window_count: 0,
        }
    }
}

/// Client event
#[derive(Debug, Clone, uniffi::Enum)]
pub enum ClientEvent {
    Connected { client_id: ClientId, pid: u32 },
    Disconnected { client_id: ClientId },
}

// ============================================================================
// IPC/Debug Types
// ============================================================================

/// Debug command
#[derive(Debug, Clone, uniffi::Enum)]
pub enum DebugCommand {
    DumpState,
    DumpSurfaces,
    DumpWindows,
    DumpClients,
    SetLogLevel { level: String },
    ForceRedraw,
}
