//! `xdg_popup.grab`: keyboard focus and dismissal.
//!
//! A grabbing popup takes keyboard focus while its toplevel stays
//! activated. The grab ends innermost popup first when the user clicks a
//! surface of another client or keyboard focus moves to another window, and
//! focus returns to the next grabbing popup or the toplevel when a grabbing
//! popup goes away.

use wayland_server::backend::ClientId;
use wayland_server::Resource;

use super::CompositorState;

/// `(client, xdg_popup protocol id)`, the key of `xdg.popups`.
pub type PopupKey = (ClientId, u32);

/// Bound on parent walks: a malformed popup chain must not hang input.
const MAX_POPUP_DEPTH: usize = 64;

impl CompositorState {
    /// Toplevel window a popup window (or a toplevel itself) hangs from.
    pub(crate) fn popup_root_window(&self, mut window_id: u32) -> Option<u32> {
        for _ in 0..MAX_POPUP_DEPTH {
            if self.windows.contains_key(&window_id) {
                return Some(window_id);
            }
            window_id = self
                .xdg
                .popups
                .values()
                .find(|popup| popup.window_id == window_id)?
                .parent_id?;
        }
        None
    }

    /// Toplevel surface whose `activated` state follows keyboard focus on
    /// `surface_id` (the surface itself, or the toplevel of its popup chain).
    pub(crate) fn activation_surface(&self, surface_id: u32) -> Option<u32> {
        let window_id = self.root_window_of_surface(surface_id)?;
        let root = self.popup_root_window(window_id)?;
        Some(self.windows.get(&root)?.read().ok()?.surface_id)
    }

    fn top_grab_popup_surface(&self) -> Option<u32> {
        self.seat
            .popup_grab_stack
            .iter()
            .rev()
            .find_map(|key| self.xdg.popups.get(key))
            .map(|popup| popup.surface_id)
    }

    fn grab_root_window(&self) -> Option<u32> {
        let key = self.seat.popup_grab_stack.first()?;
        let popup = self.xdg.popups.get(key)?;
        self.popup_root_window(popup.window_id)
    }

    fn grab_client(&self) -> Option<ClientId> {
        self.seat
            .popup_grab_stack
            .first()
            .map(|(client, _)| client.clone())
    }

    /// `xdg_popup.grab`: stack the popup and give it keyboard focus.
    pub(crate) fn begin_popup_grab(&mut self, key: PopupKey) {
        let Some(surface_id) = self.xdg.popups.get_mut(&key).map(|popup| {
            popup.grabbed = true;
            popup.surface_id
        }) else {
            return;
        };
        if !self.seat.popup_grab_stack.contains(&key) {
            self.seat.popup_grab_stack.push(key);
        }
        self.set_keyboard_focus_surface(Some(surface_id));
    }

    /// Drop `key` from the grab and move keyboard focus off its surface.
    pub(crate) fn end_popup_grab_for(&mut self, key: &PopupKey, surface_id: u32) {
        self.seat.popup_grab_stack.retain(|grabbed| grabbed != key);
        if self.seat.keyboard.focus == Some(surface_id) {
            self.refocus_after_popup_grab();
        }
    }

    /// Keyboard focus to the innermost remaining grabbing popup, else to the
    /// focused window.
    fn refocus_after_popup_grab(&mut self) {
        let target = self.top_grab_popup_surface().or_else(|| {
            let window = self.focus.keyboard_focus?;
            Some(self.windows.get(&window)?.read().ok()?.surface_id)
        });
        self.set_keyboard_focus_surface(target);
    }

    /// Whether moving keyboard focus to `window_id` leaves the grab.
    pub(crate) fn focus_change_ends_popup_grab(&self, window_id: Option<u32>) -> bool {
        if self.seat.popup_grab_stack.is_empty() {
            return false;
        }
        let target_root = window_id.and_then(|wid| self.popup_root_window(wid));
        target_root.is_none() || target_root != self.grab_root_window()
    }

    /// Whether a press on `surface_id` ends the grab: the spec dismisses it
    /// for surfaces that do not belong to the popup's client.
    pub(crate) fn click_ends_popup_grab(&self, surface_id: Option<u32>) -> bool {
        let Some(grab_client) = self.grab_client() else {
            return false;
        };
        let clicked_client = surface_id
            .and_then(|sid| self.surface_resource(sid))
            .and_then(|surface| surface.client())
            .map(|client| client.id());
        clicked_client.as_ref() != Some(&grab_client)
    }

    /// Send `popup_done` innermost first and end the grab. Keyboard focus is
    /// left to the caller, which is about to move it.
    pub(crate) fn dismiss_popup_grab_without_refocus(&mut self) {
        while let Some(key) = self.seat.popup_grab_stack.pop() {
            if let Some(popup) = self.xdg.popups.get_mut(&key) {
                popup.grabbed = false;
                if let Some(resource) = popup.resource.as_ref() {
                    tracing::debug!("Dismissing popup {} for client {:?}", key.1, key.0);
                    resource.popup_done();
                }
            }
        }
    }

    /// Dismiss the active popup grab and all its child popups
    pub fn dismiss_popup_grab(&mut self) {
        let focused_popup = self
            .seat
            .keyboard
            .focus
            .is_some_and(|sid| self.xdg.popups.values().any(|p| p.surface_id == sid));
        self.dismiss_popup_grab_without_refocus();
        if focused_popup {
            self.refocus_after_popup_grab();
        }
    }
}
