use std::sync::Arc;
use std::time::Instant;
use wayland_server::Resource;
use wayland_server::protocol::wl_keyboard::{self, WlKeyboard};
use wayland_server::protocol::wl_surface::WlSurface;

use super::xkb::{XkbContext, XkbState, KeyResult, create_keymap_file, MINIMAL_KEYMAP};

/// Keyboard state for a seat, managing focus, pressed keys, XKB, and key repeat.
#[derive(Debug)]
pub struct KeyboardState {
    /// Currently focused surface (internal compositor surface ID)
    pub focus: Option<u32>,
    /// Set of currently pressed scancodes
    pub pressed_keys: Vec<u32>,
    /// Modifier state (cached from XKB)
    pub mods_depressed: u32,
    pub mods_latched: u32,
    pub mods_locked: u32,
    pub mods_group: u32,
    /// Bound keyboard resources from clients
    pub resources: Vec<WlKeyboard>,
    /// XKB context (shared with other seats)
    pub xkb_context: Arc<XkbContext>,
    /// XKB state machine (None if keymap compilation failed)
    pub xkb_state: Option<Arc<std::sync::Mutex<XkbState>>>,
    /// Key repeat configuration
    pub repeat_rate: i32,
    pub repeat_delay: i32,
    /// Key repeat tracking
    repeat_key: Option<u32>,
    repeat_started_at: Option<Instant>,
    last_repeat_at: Option<Instant>,
}

impl Default for KeyboardState {
    fn default() -> Self {
        let xkb_context = Arc::new(XkbContext::new());
        let xkb_state = create_initial_xkb_state(xkb_context.clone());

        Self {
            focus: None,
            pressed_keys: Vec::new(),
            mods_depressed: 0,
            mods_latched: 0,
            mods_locked: 0,
            mods_group: 0,
            resources: Vec::new(),
            xkb_context,
            xkb_state,
            repeat_rate: 33,
            repeat_delay: 500,
            repeat_key: None,
            repeat_started_at: None,
            last_repeat_at: None,
        }
    }
}

impl KeyboardState {
    pub fn new(xkb_context: Arc<XkbContext>) -> Self {
        let xkb_state = create_initial_xkb_state(xkb_context.clone());

        Self {
            xkb_context,
            xkb_state,
            ..Default::default()
        }
    }

    /// Add a keyboard resource and send the current keymap to it.
    pub fn add_resource(&mut self, keyboard: WlKeyboard, serial: u32) {
        use std::os::unix::io::AsFd;
        let mut keymap_done = false;

        if let Some(state) = &self.xkb_state {
            if let Ok(state) = state.lock() {
                let file = state.keymap_file();
                let size = state.keymap_size;
                keyboard.keymap(
                    wl_keyboard::KeymapFormat::XkbV1,
                    file.as_fd(),
                    size,
                );
                keymap_done = true;
            }
        }

        if !keymap_done {
            if let Ok(file) = create_keymap_file(MINIMAL_KEYMAP) {
                keyboard.keymap(
                    wl_keyboard::KeymapFormat::XkbV1,
                    file.as_fd(),
                    MINIMAL_KEYMAP.len() as u32,
                );
            }
        }

        keyboard.modifiers(
            serial,
            self.mods_depressed,
            self.mods_latched,
            self.mods_locked,
            self.mods_group,
        );

        self.resources.push(keyboard);
    }

    /// Remove a keyboard resource
    pub fn remove_resource(&mut self, resource: &WlKeyboard) {
        self.resources.retain(|k| k.id() != resource.id());
    }

    /// Process a key event through XKB and update internal state.
    /// Returns the KeyResult with keysym and UTF-8 for compositor-side processing.
    pub fn process_key(&mut self, keycode: u32, pressed: bool) -> Option<KeyResult> {
        let direction = if pressed {
            xkbcommon::xkb::KeyDirection::Down
        } else {
            xkbcommon::xkb::KeyDirection::Up
        };

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

        if let Some(xkb) = &self.xkb_state {
            if let Ok(mut state) = xkb.lock() {
                let result = state.process_key(keycode, direction);
                if result.modifiers_changed {
                    let (d, la, lo, g) = state.serialize_modifiers();
                    self.mods_depressed = d;
                    self.mods_latched = la;
                    self.mods_locked = lo;
                    self.mods_group = g;
                }
                return Some(result);
            }
        }
        None
    }

    /// Check if a key repeat event should fire. Returns the keycode to repeat, if any.
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

    /// Send enter event to all keyboard resources matching the surface's client.
    pub fn broadcast_enter(
        &mut self,
        serial: u32,
        surface: &WlSurface,
        keys: &[u32],
    ) {
        let client = surface.client();
        let keys_bytes: Vec<u8> = keys
            .iter()
            .flat_map(|k| k.to_ne_bytes().to_vec())
            .collect();

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

    /// Send leave event to all keyboard resources matching the surface's client.
    pub fn broadcast_leave(&self, serial: u32, surface: &WlSurface) {
        let client = surface.client();
        for kbd in &self.resources {
            if kbd.client() == client {
                kbd.leave(serial, surface);
            }
        }
    }

    /// Send key event to focused client's keyboard resources.
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

    /// Send modifiers event to focused client's keyboard resources.
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

    /// Switch to a new keymap at runtime. All connected keyboards receive the new keymap.
    pub fn switch_keymap(
        &mut self,
        rules: &str,
        model: &str,
        layout: &str,
        variant: &str,
        options: Option<String>,
    ) -> Result<(), ()> {
        use std::os::unix::io::AsFd;

        let new_state = XkbState::new_from_names(
            self.xkb_context.clone(),
            rules,
            model,
            layout,
            variant,
            options,
        )?;

        let file = new_state.keymap_file();
        let size = new_state.keymap_size;

        for kbd in &self.resources {
            kbd.keymap(
                wl_keyboard::KeymapFormat::XkbV1,
                file.as_fd(),
                size,
            );
        }

        self.xkb_state = Some(Arc::new(std::sync::Mutex::new(new_state)));
        self.mods_depressed = 0;
        self.mods_latched = 0;
        self.mods_locked = 0;
        self.mods_group = 0;

        Ok(())
    }

    /// Clean up dead resources
    pub fn cleanup_resources(&mut self) {
        // Note: keyboards are not aggressively cleaned — they are removed
        // when clients explicitly release them or disconnect.
    }
}

fn create_initial_xkb_state(xkb_context: Arc<XkbContext>) -> Option<Arc<std::sync::Mutex<XkbState>>> {
    #[cfg(any(target_os = "ios", target_os = "visionos", target_os = "watchos", target_os = "android"))]
    let state = XkbState::new_from_string(xkb_context.clone(), MINIMAL_KEYMAP);

    #[cfg(not(any(target_os = "ios", target_os = "visionos", target_os = "watchos", target_os = "android")))]
    let state = XkbState::new(xkb_context.clone()).or_else(|_| {
        tracing::warn!("xkb_keymap_new_from_names failed; using built-in minimal keymap");
        XkbState::new_from_string(xkb_context.clone(), MINIMAL_KEYMAP)
    });

    state.ok().map(|s| Arc::new(std::sync::Mutex::new(s)))
}
