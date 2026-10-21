//! Toplevel window-management state shared by `xdg_toplevel` requests and
//! `zwlr_foreign_toplevel_handle_v1` requests.
//!
//! Maximized and fullscreen are independent: fullscreen does not clear
//! maximized, and leaving fullscreen returns to the maximized size when the
//! toplevel is still maximized. Maximize, fullscreen and activate restore a
//! minimized window. Every change is published to foreign-toplevel handles.

use smithay::reexports::wayland_server::protocol::wl_output::WlOutput;
use smithay::reexports::wayland_server::{backend::ClientId, Resource};

use crate::core::compositor::CompositorEvent;
use crate::core::state::CompositorState;
use crate::core::window::Window;

/// Key of `CompositorState::xdg.toplevels`.
pub type ToplevelKey = (ClientId, u32);

impl CompositorState {
    pub(crate) fn toplevel_key_for_window(&self, window_id: u32) -> Option<ToplevelKey> {
        self.xdg
            .toplevels
            .iter()
            .find(|(_, tl)| tl.window_id == window_id)
            .map(|(key, _)| key.clone())
    }

    pub(crate) fn toplevel_window_id(&self, key: &ToplevelKey) -> Option<u32> {
        self.xdg.toplevels.get(key).map(|tl| tl.window_id)
    }

    pub(crate) fn read_window<T>(&self, window_id: u32, f: impl FnOnce(&Window) -> T) -> Option<T> {
        let window = self.get_window(window_id)?;
        let window = window.read().ok()?;
        Some(f(&window))
    }

    pub(crate) fn update_window(&self, window_id: u32, f: impl FnOnce(&mut Window)) {
        if let Some(window) = self.get_window(window_id) {
            if let Ok(mut window) = window.write() {
                f(&mut window);
            }
        }
    }

    /// Mapped and not minimized.
    pub(crate) fn is_window_shown(&self, window_id: u32) -> bool {
        self.read_window(window_id, |w| !w.minimized)
            .unwrap_or(false)
    }

    pub(crate) fn window_output_id(&self, window_id: u32) -> u32 {
        self.read_window(window_id, |w| w.outputs.first().copied())
            .flatten()
            .or_else(|| self.outputs.get(self.primary_output).map(|o| o.id))
            .unwrap_or(0)
    }

    pub(crate) fn maximized_size(&self, key: &ToplevelKey, window_id: u32) -> (u32, u32) {
        let (w, h) = self
            .get_usable_region(self.window_output_id(window_id))
            .map(|(_, _, w, h)| (w, h))
            .unwrap_or((0, 0));
        self.xdg
            .toplevels
            .get(key)
            .map(|tl| tl.clamp_size(w, h))
            .unwrap_or((w, h))
    }

    pub(crate) fn fullscreen_size(&self, output_id: u32) -> (u32, u32) {
        self.get_output_geometry(output_id)
            .map(|(_, _, w, h)| (w, h))
            .unwrap_or((0, 0))
    }

    /// Remember the floating geometry before the first maximize/fullscreen.
    pub(crate) fn save_floating_geometry(&mut self, key: &ToplevelKey, window_id: u32) {
        let geometry = self.read_window(window_id, |w| {
            (w.x, w.y, w.width.max(0) as u32, w.height.max(0) as u32)
        });
        if let (Some(geometry), Some(tl)) = (geometry, self.xdg.toplevels.get_mut(key)) {
            tl.saved_geometry.get_or_insert(geometry);
        }
    }

    /// Size to configure when returning to floating. Only a size the client
    /// chose (it committed a buffer while floating) is restored; otherwise
    /// 0x0 lets the client decide. The current size is the maximized or
    /// fullscreen size and must never be echoed back.
    pub(crate) fn restore_floating_geometry(&mut self, key: &ToplevelKey, window_id: u32) -> (u32, u32) {
        let saved = self
            .xdg
            .toplevels
            .get_mut(key)
            .and_then(|tl| tl.saved_geometry.take());
        let client_chose_size = self
            .read_window(window_id, |w| w.has_committed_buffer)
            .unwrap_or(false);
        match saved {
            Some((x, y, w, h)) if client_chose_size && w > 0 && h > 0 => {
                self.update_window(window_id, |win| {
                    win.x = x;
                    win.y = y;
                });
                (w, h)
            }
            _ => (0, 0),
        }
    }

    fn configure_toplevel(&mut self, key: &ToplevelKey, (w, h): (u32, u32)) {
        let _ = self.send_toplevel_configure(key.0.clone(), key.1, w, h);
    }

    pub(crate) fn minimize_toplevel(&mut self, key: ToplevelKey) {
        let Some(window_id) = self.toplevel_window_id(&key) else {
            return;
        };
        self.update_window(window_id, |w| w.minimized = true);
        if self.headless_host {
            if self.focus.has_keyboard_focus(window_id) {
                let next = self
                    .focus
                    .focus_history
                    .iter()
                    .copied()
                    .find(|&wid| wid != window_id && self.is_window_shown(wid));
                self.set_focused_window(next);
            }
            self.repick_headless_global_pointer();
        }
        self.pending_compositor_events
            .push(CompositorEvent::WindowMinimized {
                window_id,
                minimized: true,
            });
        self.refresh_foreign_toplevel(window_id);
    }

    /// Restore a minimized window. No-op when it is not minimized.
    pub(crate) fn unminimize_window(&mut self, window_id: u32) {
        let minimized = self
            .read_window(window_id, |w| w.minimized)
            .unwrap_or(false);
        if !minimized {
            return;
        }
        self.update_window(window_id, |w| w.minimized = false);
        if self.headless_host {
            self.window_tree.bring_to_front(window_id);
            self.repick_headless_global_pointer();
        }
        self.pending_compositor_events
            .push(CompositorEvent::WindowMinimized {
                window_id,
                minimized: false,
            });
        self.refresh_foreign_toplevel(window_id);
    }

    /// Headless window-manager activation: restore, raise and focus.
    pub(crate) fn activate_window(&mut self, window_id: u32) {
        self.unminimize_window(window_id);
        self.window_tree.bring_to_front(window_id);
        self.set_focused_window(Some(window_id));
        if self.headless_host {
            self.repick_headless_global_pointer();
        }
    }

    /// Ask the client to close the toplevel (`xdg_toplevel.close`).
    pub(crate) fn close_window(&mut self, window_id: u32) {
        let surface = self
            .toplevel_key_for_window(window_id)
            .and_then(|key| self.xdg.toplevels.get(&key))
            .and_then(|tl| tl.toplevel_surface.clone());
        if let Some(surface) = surface {
            surface.send_close();
        }
    }

    pub(crate) fn maximize_toplevel(&mut self, key: ToplevelKey) {
        let Some(window_id) = self.toplevel_window_id(&key) else {
            return;
        };
        self.unminimize_window(window_id);
        self.save_floating_geometry(&key, window_id);
        self.update_window(window_id, |w| w.maximized = true);
        let fullscreen = self.xdg.toplevels.get_mut(&key).is_some_and(|tl| {
            tl.pending_maximized = true;
            tl.pending_fullscreen
        });
        let size = if fullscreen {
            self.fullscreen_size(self.window_output_id(window_id))
        } else {
            self.maximized_size(&key, window_id)
        };
        self.configure_toplevel(&key, size);
        self.pending_compositor_events
            .push(CompositorEvent::WindowMaximized {
                window_id,
                maximized: true,
            });
        self.refresh_foreign_toplevel(window_id);
    }

    pub(crate) fn unmaximize_toplevel(&mut self, key: ToplevelKey) {
        let Some(window_id) = self.toplevel_window_id(&key) else {
            return;
        };
        self.update_window(window_id, |w| w.maximized = false);
        let fullscreen = self.xdg.toplevels.get_mut(&key).is_some_and(|tl| {
            tl.pending_maximized = false;
            tl.pending_fullscreen
        });
        let size = if fullscreen {
            self.fullscreen_size(self.window_output_id(window_id))
        } else {
            self.restore_floating_geometry(&key, window_id)
        };
        self.configure_toplevel(&key, size);
        self.pending_compositor_events
            .push(CompositorEvent::WindowMaximized {
                window_id,
                maximized: false,
            });
        self.refresh_foreign_toplevel(window_id);
    }

    pub(crate) fn fullscreen_toplevel(&mut self, key: ToplevelKey, output: Option<WlOutput>) {
        let Some(window_id) = self.toplevel_window_id(&key) else {
            return;
        };
        let output_id = match output {
            Some(output) => self
                .output_id_by_resource
                .get(&output.id())
                .copied()
                .unwrap_or_else(|| output.id().protocol_id()),
            None => self.window_output_id(window_id),
        };
        self.unminimize_window(window_id);
        self.save_floating_geometry(&key, window_id);
        self.update_window(window_id, |w| w.fullscreen = true);
        if let Some(tl) = self.xdg.toplevels.get_mut(&key) {
            tl.pending_fullscreen = true;
        }
        let size = self.fullscreen_size(output_id);
        self.configure_toplevel(&key, size);
        self.pending_compositor_events
            .push(CompositorEvent::WindowFullscreen {
                window_id,
                fullscreen: true,
            });
        self.refresh_foreign_toplevel(window_id);
    }

    pub(crate) fn unfullscreen_toplevel(&mut self, key: ToplevelKey) {
        let Some(window_id) = self.toplevel_window_id(&key) else {
            return;
        };
        self.update_window(window_id, |w| w.fullscreen = false);
        let maximized = self.xdg.toplevels.get_mut(&key).is_some_and(|tl| {
            tl.pending_fullscreen = false;
            tl.pending_maximized
        });
        let size = if maximized {
            self.maximized_size(&key, window_id)
        } else {
            self.restore_floating_geometry(&key, window_id)
        };
        self.configure_toplevel(&key, size);
        self.pending_compositor_events
            .push(CompositorEvent::WindowFullscreen {
                window_id,
                fullscreen: false,
            });
        self.refresh_foreign_toplevel(window_id);
    }
}
