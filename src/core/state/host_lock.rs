//! Host-locked (kiosk) window policy.
//!
//! A host-locked surface fills the primary output and ignores client-preferred
//! floating sizes. That is appropriate for `fullscreen_shell` / explicit
//! embedded kiosk hosts. **not** for ordinary xdg_toplevel clients.
//!
//! ## Wayland rule
//!
//! Sizing is negotiated via `xdg_toplevel.configure` (0×0 = client decides).
//! Do **not** host-lock by `app_id` for weston-family demos
//! (`weston-flower`, `weston-smoke`, …): that forced `configure(output)` and
//! stretched a fixed 200×200 buffer into a giant host window, which violates
//! xdg-shell and OWL (host frame == committed buffer).

use crate::core::compositor::CompositorEvent;

impl super::CompositorState {
    /// Auto host-lock from app_id is disabled.
    ///
    /// Historical code locked every `*weston*` app_id to the output. That
    /// broke fixed-size clients (flower/smoke) by stretching their buffers.
    /// Keep host-lock for `fullscreen_shell` and explicit
    /// [`Self::lock_window_to_primary_output`] callers only.
    pub fn should_host_lock_app_id(_app_id: &str) -> bool {
        false
    }

    /// Host-lock check from already-known window fields (safe while holding `window.write()`).
    pub fn is_host_locked_window_flags(
        window_id: u32,
        host_locked: bool,
        fullscreen_shell_presented: Option<u32>,
    ) -> bool {
        fullscreen_shell_presented == Some(window_id) || host_locked
    }

    pub fn is_host_locked_window(&self, window_id: u32) -> bool {
        if self.ext.fullscreen_shell.presented_window_id == Some(window_id) {
            return true;
        }
        if let Some(window) = self.get_window(window_id) {
            if let Ok(w) = window.read() {
                return w.host_locked;
            }
        }
        false
    }

    /// Pin a toplevel to the primary output and tell the client the drawable size.
    pub fn lock_window_to_primary_output(&mut self, window_id: u32) -> Option<(u32, u32)> {
        let output = self.primary_output();
        let x = output.x;
        let y = output.y;
        let w = output.width as i32;
        let h = output.height as i32;
        if w <= 0 || h <= 0 {
            return None;
        }

        if let Some(window) = self.get_window(window_id) {
            let mut window = window.write().unwrap();
            window.host_locked = true;
            window.x = x;
            window.y = y;
            window.width = w;
            window.height = h;
            window.geometry_x = 0;
            window.geometry_y = 0;
            window.maximized = false;
        }

        let mut configure = None;
        for ((client_id, toplevel_id), tl) in &self.xdg.toplevels {
            if tl.window_id == window_id {
                configure = Some((client_id.clone(), *toplevel_id, w as u32, h as u32));
                break;
            }
        }
        if let Some((client_id, toplevel_id, cw, ch)) = configure {
            if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                tl.width = cw;
                tl.height = ch;
            }
            self.send_toplevel_configure(client_id, toplevel_id, cw, ch);
        }

        Some((w as u32, h as u32))
    }

    pub fn unlock_host_window(&mut self, window_id: u32) {
        if let Some(window) = self.get_window(window_id) {
            window.write().unwrap().host_locked = false;
        }
    }

    pub fn apply_host_lock_for_app_id(&mut self, window_id: u32, app_id: &str) {
        if Self::should_host_lock_app_id(app_id) {
            if let Some((width, height)) = self.lock_window_to_primary_output(window_id) {
                self.pending_compositor_events
                    .push(CompositorEvent::WindowHostLocked {
                        window_id,
                        width,
                        height,
                    });
            }
        } else if self.is_host_locked_window(window_id)
            && self.ext.fullscreen_shell.presented_window_id != Some(window_id)
        {
            // Clear stale app_id-based locks (e.g. after policy change / rematch).
            self.unlock_host_window(window_id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::CompositorState;

    #[test]
    fn weston_flower_is_not_auto_host_locked() {
        assert!(!CompositorState::should_host_lock_app_id(
            "org.freedesktop.weston.wayland-flower"
        ));
        assert!(!CompositorState::should_host_lock_app_id("weston-flower"));
        assert!(!CompositorState::should_host_lock_app_id("weston-smoke"));
        assert!(!CompositorState::should_host_lock_app_id("weston"));
    }
}
