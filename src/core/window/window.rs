

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecorationMode {
    ClientSide,
    ServerSide,
}

/// Represents a top-level window (XDG Toplevel).
///
/// Corresponds to `WawonaWindowContainer`.
pub struct Window {
    pub id: u32,
    pub title: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub decoration_mode: DecorationMode,
    pub surface_id: u32,
    pub app_id: String,
    
    // Window state
    pub maximized: bool,
    pub minimized: bool,
    pub fullscreen: bool,
    pub activated: bool,
    pub resizing: bool,
    /// Whether this window is a modal dialog
    pub modal: bool,
    /// When true the host OS view owns placement/size (kiosk / embedded-app).
    pub host_locked: bool,

    /// CSD geometry offset: the (x, y) origin of the content area within the
    /// surface buffer.  When the window is cropped to exclude the CSD shadow,
    /// pointer coordinates from the platform must be shifted by this offset to
    /// produce correct surface-local coordinates.
    pub geometry_x: i32,
    pub geometry_y: i32,
    
    /// IDs of outputs this window is visible on
    pub outputs: Vec<u32>,
}

impl Window {
    pub fn new(id: u32, surface_id: u32) -> Self {
        Self {
            id,
            title: "Wawona Window".to_string(),
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            decoration_mode: DecorationMode::ClientSide,
            surface_id,
            app_id: "".to_string(),
            maximized: false,
            minimized: false,
            fullscreen: false,
            activated: false,
            resizing: false,
            modal: false,
            host_locked: false,
            geometry_x: 0,
            geometry_y: 0,
            outputs: Vec::new(),
        }
    }

    pub fn geometry(&self) -> crate::util::geometry::Rect {
        crate::util::geometry::Rect {
            x: self.x,
            y: self.y,
            width: self.width as u32,
            height: self.height as u32,
        }
    }
}
