use std::collections::HashMap;

/// A single active touch point (compositor bookkeeping, not the protocol owner).
#[derive(Debug, Clone)]
pub struct TouchPoint {
    pub id: i32,
    pub surface_id: u32,
    pub x: f64,
    pub y: f64,
}

/// Contact-id tracker. Smithay `TouchHandle` owns `wl_touch` events.
#[derive(Debug, Clone)]
pub struct TouchState {
    pub active_points: HashMap<i32, TouchPoint>,
    /// Host-side concurrent-contact cap. Watch and other single-touch hosts use 1.
    pub max_concurrent: usize,
    /// Primary contact used for nested-compositor pointer chrome (or emulation).
    pub pointer_mirror_id: Option<i32>,
    /// True while a mirrored `BTN_LEFT` is held.
    pub pointer_button_held: bool,
}

impl Default for TouchState {
    fn default() -> Self {
        Self {
            active_points: HashMap::new(),
            max_concurrent: default_touch_max_concurrent(),
            pointer_mirror_id: None,
            pointer_button_held: false,
        }
    }
}

/// Single-touch hosts keep one live id. Others allow a small multitouch set.
pub fn default_touch_max_concurrent() -> usize {
    if cfg!(target_os = "watchos") {
        1
    } else {
        16
    }
}

/// How the host screen feeds `wl_touch` and `wl_pointer`.
///
/// CarPlay and Android Auto are one-contact screens: `wl_touch` keeps a
/// single slot, and that contact is also `wl_pointer` so clients that never
/// bind touch still receive a point. A TV with no touch (AirPlay, wired,
/// DeX-style) is a touchpad: the phone sends `wl_pointer` and
/// `zwp_relative_pointer_v1`, and `wl_touch` accepts no contacts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum HostSeatMode {
    MultiTouch = 0,
    SingleTouch = 1,
    Touchpad = 2,
}

impl HostSeatMode {
    pub fn from_u32(raw: u32) -> Self {
        match raw {
            1 => Self::SingleTouch,
            2 => Self::Touchpad,
            _ => Self::MultiTouch,
        }
    }

    /// Concurrent `wl_touch` downs. Zero means the seat does not accept touch.
    pub fn max_concurrent(self) -> usize {
        match self {
            Self::MultiTouch => default_touch_max_concurrent(),
            Self::SingleTouch => 1,
            Self::Touchpad => 0,
        }
    }

    /// One-contact screens also drive `wl_pointer` for clients without touch.
    pub fn force_pointer_emulation(self) -> bool {
        matches!(self, Self::SingleTouch)
    }
}

impl TouchState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn can_accept_down(&self, id: i32) -> bool {
        if self.active_points.contains_key(&id) {
            return true;
        }
        if self.max_concurrent == 0 {
            return false;
        }
        self.active_points.len() < self.max_concurrent
    }

    pub fn touch_down(&mut self, id: i32, surface_id: u32, x: f64, y: f64) {
        self.active_points.insert(
            id,
            TouchPoint {
                id,
                surface_id,
                x,
                y,
            },
        );
        if self.pointer_mirror_id.is_none() {
            self.pointer_mirror_id = Some(id);
        }
    }

    pub fn touch_motion(&mut self, id: i32, x: f64, y: f64) {
        if let Some(point) = self.active_points.get_mut(&id) {
            point.x = x;
            point.y = y;
        }
    }

    pub fn touch_up(&mut self, id: i32) {
        self.active_points.remove(&id);
        if self.pointer_mirror_id == Some(id) {
            self.pointer_mirror_id = self.active_points.keys().next().copied();
            self.pointer_button_held = false;
        }
    }

    pub fn touch_cancel(&mut self) {
        self.active_points.clear();
        self.pointer_mirror_id = None;
        self.pointer_button_held = false;
    }

    pub fn get_touch_surface(&self, id: i32) -> Option<u32> {
        self.active_points.get(&id).map(|p| p.surface_id)
    }

    pub fn has_active_touches(&self) -> bool {
        !self.active_points.is_empty()
    }

    /// Custom `wl_touch` resources are no longer bound here. Smithay owns them.
    pub fn add_resource(&mut self, _touch: wayland_server::protocol::wl_touch::WlTouch) {}

    pub fn remove_resource(&mut self, _resource: &wayland_server::protocol::wl_touch::WlTouch) {}

    pub fn cleanup_resources(&mut self) {}
}

/// Whether Multi-Touch should also hold `wl_pointer` + BTN_LEFT.
/// Nested compositor chrome needs a button serial. Terminal selection is a
/// separate narrow compatibility path in `CompositorState`; apps do not get it.
pub fn should_mirror_pointer_for_chrome(nested_compositor: bool) -> bool {
    nested_compositor
}

/// Pref-gated pointer stream for clients that never bind `wl_touch`.
pub fn should_emulate_pointer(pref_enabled: bool, nested_compositor: bool) -> bool {
    pref_enabled && !nested_compositor
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_touch_cap_rejects_second_id() {
        let mut t = TouchState::new();
        t.max_concurrent = HostSeatMode::SingleTouch.max_concurrent();
        assert!(t.can_accept_down(1));
        t.touch_down(1, 10, 0.0, 0.0);
        assert!(!t.can_accept_down(2));
        assert!(t.can_accept_down(1));
    }

    #[test]
    fn touchpad_seat_accepts_no_contacts() {
        let mut t = TouchState::new();
        t.max_concurrent = HostSeatMode::Touchpad.max_concurrent();
        assert!(!t.can_accept_down(1));
        assert!(HostSeatMode::SingleTouch.force_pointer_emulation());
        assert!(!HostSeatMode::Touchpad.force_pointer_emulation());
        assert!(!HostSeatMode::MultiTouch.force_pointer_emulation());
    }

    #[test]
    fn cancel_clears_ids() {
        let mut t = TouchState::new();
        t.touch_down(3, 1, 1.0, 2.0);
        t.touch_cancel();
        assert!(!t.has_active_touches());
        assert!(t.pointer_mirror_id.is_none());
    }

    #[test]
    fn chrome_mirror_only_when_nested() {
        assert!(should_mirror_pointer_for_chrome(true));
        assert!(!should_mirror_pointer_for_chrome(false));
        assert!(should_emulate_pointer(true, false));
        assert!(!should_emulate_pointer(true, true));
        assert!(!should_emulate_pointer(false, false));
    }
}
