//! Host-locked (kiosk) window policy — weston-family clients fill the compositor
//! view edge-to-edge; Wawona is not a floating window manager for these surfaces.

use crate::core::compositor::CompositorEvent;
use crate::core::wayland::xdg::decoration::is_weston_family_app_id;

impl super::CompositorState {
    pub fn should_host_lock_app_id(app_id: &str) -> bool {
        !app_id.is_empty() && is_weston_family_app_id(app_id)
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
        } else if self.is_host_locked_window(window_id) {
            self.unlock_host_window(window_id);
        }
    }
}
