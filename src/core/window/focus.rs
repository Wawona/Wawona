//! Focus management.

/// Manages input focus state.
#[derive(Debug, Default)]
pub struct FocusManager {
    /// The window that currently has keyboard focus.
    pub keyboard_focus: Option<u32>,
    /// The window that currently has pointer focus.
    pub pointer_focus: Option<u32>,

    /// Window focus history (for alt-tab)
    pub focus_history: Vec<u32>,
    /// Grabbed surface (for drag operations)
    pub grabbed_surface: Option<u32>,
}

impl FocusManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Set keyboard focus to a specific window.
    pub fn set_keyboard_focus(&mut self, window_id: Option<u32>) {
        // Add current focus to history before changing
        if let Some(prev) = self.keyboard_focus {
            if Some(prev) != window_id {
                self.focus_history.retain(|&id| id != prev);
                self.focus_history.insert(0, prev);
                // Keep history limited
                self.focus_history.truncate(10);
            }
        }
        self.keyboard_focus = window_id;
    }

    /// Set pointer focus to a specific window.
    pub fn set_pointer_focus(&mut self, window_id: Option<u32>) {
        self.pointer_focus = window_id;
    }

    /// Check if a window has keyboard focus.
    pub fn has_keyboard_focus(&self, window_id: u32) -> bool {
        self.keyboard_focus == Some(window_id)
    }
}
