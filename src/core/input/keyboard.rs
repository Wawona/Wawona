use std::time::Instant;
use wayland_server::protocol::wl_keyboard::{self, WlKeyboard};
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::Resource;

/// Focus / pressed-key cache for a seat. Smithay `KeyboardHandle` owns the
/// live keymap and `wl_keyboard` protocol. Do not compile a second XKB state
/// here (`wawona-host-keymap-bridge`).
#[derive(Debug)]
pub struct KeyboardState {
    /// Currently focused surface (internal compositor surface ID)
    pub focus: Option<u32>,
    /// Set of currently pressed scancodes (evdev)
    pub pressed_keys: Vec<u32>,
    /// Modifier cache mirrored from Smithay / host inject
    pub mods_depressed: u32,
    pub mods_latched: u32,
    pub mods_locked: u32,
    pub mods_group: u32,
    /// Leftover custom-path resources. Smithay seat clients do not use these.
    pub resources: Vec<WlKeyboard>,
    pub repeat_rate: i32,
    pub repeat_delay: i32,
    repeat_key: Option<u32>,
    repeat_started_at: Option<Instant>,
    last_repeat_at: Option<Instant>,
}

impl Default for KeyboardState {
    fn default() -> Self {
        Self {
            focus: None,
            pressed_keys: Vec::new(),
            mods_depressed: 0,
            mods_latched: 0,
            mods_locked: 0,
            mods_group: 0,
            resources: Vec::new(),
            repeat_rate: 33,
            repeat_delay: 500,
            repeat_key: None,
            repeat_started_at: None,
            last_repeat_at: None,
        }
    }
}

impl KeyboardState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Track a leftover custom keyboard resource. Do not send a keymap fd.
    /// Smithay already advertised XKB v1 from `HostKeymapBridge`.
    pub fn add_resource(&mut self, keyboard: WlKeyboard, serial: u32) {
        keyboard.modifiers(
            serial,
            self.mods_depressed,
            self.mods_latched,
            self.mods_locked,
            self.mods_group,
        );
        self.resources.push(keyboard);
    }

    pub fn remove_resource(&mut self, resource: &WlKeyboard) {
        self.resources.retain(|k| k.id() != resource.id());
    }

    /// Track press/release for enter key lists and repeat. No XKB compile.
    pub fn process_key(&mut self, keycode: u32, pressed: bool) {
        if pressed {
            if !self.pressed_keys.contains(&keycode) {
                self.pressed_keys.push(keycode);
            }
            self.repeat_key = Some(keycode);
            self.repeat_started_at = Some(Instant::now());
            self.last_repeat_at = None;
        } else {
            self.pressed_keys.retain(|&k| k != keycode);
            if self.repeat_key == Some(keycode) {
                self.repeat_key = None;
                self.repeat_started_at = None;
                self.last_repeat_at = None;
            }
        }
    }

    pub fn check_repeat(&mut self) -> Option<u32> {
        if self.repeat_rate == 0 {
            return None;
        }

        let key = self.repeat_key?;
        let started = self.repeat_started_at?;
        let now = Instant::now();
        let elapsed = now.duration_since(started);
        let delay = std::time::Duration::from_millis(self.repeat_delay as u64);

        if elapsed < delay {
            return None;
        }

        let interval = std::time::Duration::from_millis(1000 / self.repeat_rate as u64);
        if let Some(last) = self.last_repeat_at {
            if now.duration_since(last) >= interval {
                self.last_repeat_at = Some(now);
                return Some(key);
            }
        } else {
            self.last_repeat_at = Some(now);
            return Some(key);
        }

        None
    }

    pub fn broadcast_enter(&mut self, serial: u32, surface: &WlSurface, keys: &[u32]) {
        let client = surface.client();
        let keys_bytes: Vec<u8> = keys.iter().flat_map(|k| k.to_ne_bytes().to_vec()).collect();

        for kbd in &self.resources {
            if kbd.client() == client {
                kbd.enter(serial, surface, keys_bytes.clone());
                kbd.modifiers(
                    serial,
                    self.mods_depressed,
                    self.mods_latched,
                    self.mods_locked,
                    self.mods_group,
                );
                if kbd.version() >= 4 {
                    kbd.repeat_info(self.repeat_rate, self.repeat_delay);
                }
            }
        }
    }

    pub fn broadcast_leave(&self, serial: u32, surface: &WlSurface) {
        let client = surface.client();
        for kbd in &self.resources {
            if kbd.client() == client {
                kbd.leave(serial, surface);
            }
        }
    }

    pub fn broadcast_key(
        &self,
        serial: u32,
        time: u32,
        key: u32,
        state: wl_keyboard::KeyState,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for kbd in &self.resources {
                if kbd.client().as_ref() == Some(focused) {
                    kbd.key(serial, time, key, state);
                }
            }
        }
    }

    pub fn broadcast_modifiers(
        &self,
        serial: u32,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for kbd in &self.resources {
                if kbd.client().as_ref() == Some(focused) {
                    kbd.modifiers(
                        serial,
                        self.mods_depressed,
                        self.mods_latched,
                        self.mods_locked,
                        self.mods_group,
                    );
                }
            }
        }
    }

    pub fn cleanup_resources(&mut self) {}
}
