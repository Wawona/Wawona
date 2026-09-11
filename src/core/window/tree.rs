//! Window tree management.

/// Manages the hierarchy and stacking order of windows.
#[derive(Debug, Default)]
pub struct WindowTree {
    /// List of windows in stacking order (back to front).
    /// The last element is the topmost window.
    pub stacking_order: Vec<u32>,
}

impl WindowTree {
    pub fn new() -> Self {
        Self {
            stacking_order: Vec::new(),
        }
    }

    /// Insert a new window at the top of the stack.
    pub fn insert(&mut self, window_id: u32) {
        if !self.stacking_order.contains(&window_id) {
            self.stacking_order.push(window_id);
        }
    }

    /// Remove a window from the stack.
    pub fn remove(&mut self, window_id: u32) {
        if let Some(pos) = self.stacking_order.iter().position(|&id| id == window_id) {
            self.stacking_order.remove(pos);
        }
    }

    /// Move a window to the top (front) of the stack.
    pub fn bring_to_front(&mut self, window_id: u32) {
        if let Some(pos) = self.stacking_order.iter().position(|&id| id == window_id) {
            let id = self.stacking_order.remove(pos);
            self.stacking_order.push(id);
        }
    }

    /// Get the topmost window ID.
    pub fn topmost(&self) -> Option<u32> {
        self.stacking_order.last().copied()
    }

    /// Find the top-most window under the given point
    pub fn window_under(
        &self,
        x: f64,
        y: f64,
        windows: &std::collections::HashMap<
            u32,
            std::sync::Arc<std::sync::RwLock<crate::core::window::Window>>,
        >,
    ) -> Option<u32> {
        // Iterate in reverse stacking order (top to bottom)
        for &window_id in self.stacking_order.iter().rev() {
            if let Some(window) = windows.get(&window_id) {
                let window = window.read().unwrap();
                if window.geometry().contains_point(x as i32, y as i32) {
                    return Some(window_id);
                }
            }
        }
        None
    }
}
