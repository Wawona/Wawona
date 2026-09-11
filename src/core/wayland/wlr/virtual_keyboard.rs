//! `zwp_virtual_keyboard_manager_v1` is owned by Smithay
//! (`delegate_virtual_keyboard_manager!`) with a trusted-client filter.
//! Do not `create_global` that interface here.

/// Leftover bookkeeping type. Smithay owns the protocol now.
#[derive(Debug, Clone)]
pub struct VirtualKeyboardState {
    pub seat_name: Option<String>,
}

impl VirtualKeyboardState {
    pub fn new(seat_name: Option<String>) -> Self {
        Self { seat_name }
    }
}
