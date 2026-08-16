

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
    /// Per-client (per-machine) decoration policy override captured when this
    /// window's client connected. `None` means "follow the global default"
    /// (`CompositorState::decoration_policy`); `Some` pins the policy so a
    /// concurrent machine toggling Force SSD cannot restyle this window. See
    /// Force SSD per-machine (#120).
    pub decoration_policy: Option<crate::core::state::DecorationPolicy>,
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

    /// When true, this window is hosted in its own independent OS
    /// window/scene (macOS NSWindow-per-toplevel, or iPadOS/visionOS
    /// `UIWindowScene`-per-client. See `ipad-scene-parity` /
    /// `vision-shell-parity`, #120). Its size is driven exclusively by that
    /// dedicated host geometry via `resize_window`/`injectWindowResize`.
    /// `CompositorState::set_output_size` MUST skip these windows in its
    /// maximized/fullscreen resize sweep: that sweep snaps windows to the
    /// *shared* primary-output rect, which is the wrong rect for a window
    /// that lives in its own separately-sized scene (resizing the primary
    /// Machines window must never resize an unrelated client window).
    pub host_scene_independent: bool,

    /// Whether the client has committed at least one buffer for this toplevel.
    ///
    /// The compositor always defers the initial `xdg_toplevel` configure to
    /// size (0, 0). Per the xdg-shell spec this tells the client "pick your
    /// own size." The client's *first* commit is therefore always its true
    /// preferred size and must be trusted unconditionally, regardless of
    /// what output/window size hint the host used before that commit
    /// arrived. Without this, host chrome (an AppKit `NSWindow`, for
    /// example) can end up a different size than the buffer it displays,
    /// leaving the content mis-aligned/cropped inside the window. This
    /// applies to every Wayland client, not just known demo apps.
    pub has_committed_buffer: bool,

    /// Size-authority state machine (host ↔ client). See
    /// [`crate::core::window::size_authority`] and
    /// `.cursor/rules/wawona-host-client-size-sync.mdc`.
    pub size_authority: crate::core::window::SizeAuthority,

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
            decoration_policy: None,
            surface_id,
            app_id: "".to_string(),
            maximized: false,
            minimized: false,
            fullscreen: false,
            activated: false,
            resizing: false,
            modal: false,
            host_locked: false,
            host_scene_independent: false,
            has_committed_buffer: false,
            size_authority: crate::core::window::SizeAuthority::AwaitingFirstCommit,
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
