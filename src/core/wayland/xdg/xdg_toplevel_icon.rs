//! XDG Toplevel Icon — dispatch owned by Smithay `delegate_xdg_toplevel_icon!`.
//!
//! Legacy icon buffer tracking for window metadata (optional).

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct IconBuffer {
    pub buffer_id: u32,
    pub scale: i32,
}

#[derive(Debug, Clone, Default)]
pub struct IconData {
    pub buffers: Vec<IconBuffer>,
}

#[derive(Debug, Default)]
pub struct ToplevelIconState {
    pub pending_icons: HashMap<u32, IconData>,
    pub toplevel_icons: HashMap<u32, Vec<IconBuffer>>,
}
