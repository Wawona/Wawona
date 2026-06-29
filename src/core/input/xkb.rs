use std::os::unix::io::{AsRawFd, RawFd};
use std::sync::Arc;
use xkbcommon::xkb;

/// Wrapper around xkb_context to ensure it's shared properly
pub struct XkbContext {
    pub context: xkb::Context,
}

unsafe impl Send for XkbContext {}
unsafe impl Sync for XkbContext {}

impl std::fmt::Debug for XkbContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("XkbContext").finish()
    }
}

impl Default for XkbContext {
    fn default() -> Self {
        Self::new()
    }
}

impl XkbContext {
    pub fn new() -> Self {
        // On iOS the Nix-compiled default include path (/nix/store/.../share/X11/xkb)
        // does not exist inside the app sandbox.  xkb_context_new() returns NULL when
        // it cannot add the default include path, which causes a crash later.
        // Use NO_DEFAULT_INCLUDES so the context is always valid; keymap loading from
        // names will fail gracefully and we fall back to MINIMAL_KEYMAP.
        #[cfg(any(
            target_os = "ios",
            target_os = "tvos",
            target_os = "visionos",
            target_os = "watchos",
            target_os = "android"
        ))]
        let flags = xkb::CONTEXT_NO_DEFAULT_INCLUDES;
        #[cfg(not(any(
            target_os = "ios",
            target_os = "tvos",
            target_os = "visionos",
            target_os = "watchos",
            target_os = "android"
        )))]
        let flags = xkb::CONTEXT_NO_FLAGS;

        Self {
            context: xkb::Context::new(flags),
        }
    }
}

/// Result of processing a key event through XKB
#[derive(Debug, Clone)]
pub struct KeyResult {
    /// Whether modifier state changed
    pub modifiers_changed: bool,
    /// The keysym produced by this key event
    pub keysym: xkb::Keysym,
    /// UTF-8 string produced by this key (empty for non-printable keys)
    pub utf8: String,
}

/// Holds the XKB state and keymap for a seat
pub struct XkbState {
    pub context: Arc<XkbContext>,
    pub keymap: xkb::Keymap,
    pub state: xkb::State,
    pub keymap_string: String,
    keymap_file: std::fs::File,
    pub keymap_size: u32,
}

unsafe impl Send for XkbState {}

impl std::fmt::Debug for XkbState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("XkbState")
            .field("keymap_size", &self.keymap_size)
            .finish()
    }
}

impl XkbState {
    pub fn new(context: Arc<XkbContext>) -> Result<Self, ()> {
        Self::new_from_names(context, "evdev", "", "us", "", None)
    }

    /// Create XKB state from specific keymap parameters.
    /// Allows runtime keymap switching by constructing a new XkbState.
    pub fn new_from_names(
        context: Arc<XkbContext>,
        rules: &str,
        model: &str,
        layout: &str,
        variant: &str,
        options: Option<String>,
    ) -> Result<Self, ()> {
        let keymap = xkb::Keymap::new_from_names(
            &context.context,
            rules,
            model,
            layout,
            variant,
            options,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        ).ok_or(())?;

        let state = xkb::State::new(&keymap);
        let keymap_string = keymap.get_as_string(xkb::KEYMAP_FORMAT_TEXT_V1);

        let keymap_file = create_keymap_file(&keymap_string)?;
        let keymap_size = keymap_string.len() as u32;

        Ok(Self {
            context,
            keymap,
            state,
            keymap_string,
            keymap_file,
            keymap_size,
        })
    }

    /// Create XKB state from a keymap string (e.g. the MINIMAL_KEYMAP fallback).
    pub fn new_from_string(context: Arc<XkbContext>, keymap_str: &str) -> Result<Self, ()> {
        let keymap = xkb::Keymap::new_from_string(
            &context.context,
            keymap_str.to_string(),
            xkb::KEYMAP_FORMAT_TEXT_V1,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        ).ok_or(())?;

        let state = xkb::State::new(&keymap);
        let keymap_string = keymap.get_as_string(xkb::KEYMAP_FORMAT_TEXT_V1);
        let keymap_file = create_keymap_file(&keymap_string)?;
        let keymap_size = keymap_string.len() as u32;

        Ok(Self {
            context,
            keymap,
            state,
            keymap_string,
            keymap_file,
            keymap_size,
        })
    }

    pub fn keymap_file(&self) -> &std::fs::File {
        &self.keymap_file
    }

    pub fn keymap_fd(&self) -> RawFd {
        self.keymap_file.as_raw_fd()
    }

    /// Get the keymap as a string for sending to clients
    pub fn serialize_keymap(&self) -> &str {
        &self.keymap_string
    }

    /// Update modifier state directly (e.g. from platform modifier events)
    pub fn update_mask(
        &mut self,
        depressed: xkb::ModMask,
        latched: xkb::ModMask,
        locked: xkb::ModMask,
        group: xkb::LayoutIndex,
    ) {
        self.state.update_mask(depressed, latched, locked, 0, 0, group);
    }

    /// Process a key event through XKB. Returns keysym, UTF-8 text, and
    /// whether modifiers changed. The keycode should be the Linux evdev
    /// scancode (without the +8 offset — we apply it here).
    pub fn process_key(&mut self, keycode: u32, direction: xkb::KeyDirection) -> KeyResult {
        let xkb_keycode = xkb::Keycode::from(keycode + 8);

        let keysym = self.state.key_get_one_sym(xkb_keycode);
        let utf8 = match direction {
            xkb::KeyDirection::Down => self.state.key_get_utf8(xkb_keycode),
            _ => String::new(),
        };

        let modifiers_changed = self.state.update_key(xkb_keycode, direction) != 0;

        KeyResult {
            modifiers_changed,
            keysym,
            utf8,
        }
    }

    /// Update state from a key event (returns true if modifiers changed).
    /// Legacy method — prefer `process_key()` for full keysym+UTF-8 support.
    pub fn update_key(&mut self, keycode: u32, direction: xkb::KeyDirection) -> bool {
        self.state.update_key((keycode + 8).into(), direction) != 0
    }

    /// Serialize modifiers for Wayland protocol (depressed, latched, locked, group)
    pub fn serialize_modifiers(&self) -> (u32, u32, u32, u32) {
        let depressed = self.state.serialize_mods(xkb::STATE_MODS_DEPRESSED);
        let latched = self.state.serialize_mods(xkb::STATE_MODS_LATCHED);
        let locked = self.state.serialize_mods(xkb::STATE_MODS_LOCKED);
        let group = self.state.serialize_layout(xkb::STATE_LAYOUT_EFFECTIVE);

        (depressed, latched, locked, group)
    }

    /// Check if a specific modifier is active
    pub fn mod_is_active(&self, name: &str) -> bool {
        // xkbcommon mod names: "Shift", "Control", "Mod1" (Alt), "Mod4" (Super)
        self.state.mod_name_is_active(name, xkb::STATE_MODS_EFFECTIVE)
    }
}

/// Ensure xkbcommon can locate keymap data (rules/symbols/keycodes/types) on
/// every platform. On desktop Linux and the Nix-built macOS app the default
/// xkb include path resolves; on the sandboxed Apple/Android app it does not,
/// so we point xkbcommon at the bundled `xkeyboard-config` via `XKB_CONFIG_ROOT`.
///
/// Idempotent and side-effect-light: respects an already-set `XKB_CONFIG_ROOT`,
/// honors an explicit `WAWONA_XKB_CONFIG_ROOT` override, then probes bundled
/// locations (including `WAWONA_SHARE_ROOT` from Apple bundle setup).
pub fn ensure_xkb_data_root() {
    use std::path::PathBuf;
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        if std::env::var_os("XKB_CONFIG_ROOT").is_some() {
            return;
        }
        if let Some(root) = std::env::var_os("WAWONA_XKB_CONFIG_ROOT") {
            std::env::set_var("XKB_CONFIG_ROOT", root);
            return;
        }

        let mut candidates: Vec<PathBuf> = Vec::new();
        if let Ok(share) = std::env::var("WAWONA_SHARE_ROOT") {
            if !share.is_empty() {
                candidates.push(PathBuf::from(share).join("X11/xkb"));
            }
        }
        if let Ok(app) = std::env::var("WAWONA_APP_BUNDLE_ROOT") {
            if !app.is_empty() {
                let root = PathBuf::from(app);
                candidates.push(root.join("Contents/Resources/xkb"));
                candidates.push(root.join("xkb"));
                candidates.push(root.join("share/X11/xkb"));
            }
        }
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let exe_str = exe.to_string_lossy();
                if let Some(idx) = exe_str.find(".app/Contents/MacOS/") {
                    let app = PathBuf::from(&exe_str[..idx + 4]);
                    candidates.push(app.join("share/X11/xkb"));
                    candidates.push(app.join("Contents/Resources/xkb"));
                } else if let Some(idx) = exe_str.find(".app/") {
                    let app = PathBuf::from(&exe_str[..idx + 4]);
                    candidates.push(app.join("share/X11/xkb"));
                    candidates.push(app.join("xkb"));
                }
                candidates.push(dir.join("../Resources/xkb"));
                candidates.push(dir.join("../Resources/share/X11/xkb"));
                candidates.push(dir.join("xkb"));
                candidates.push(dir.join("share/X11/xkb"));
                if let Ok(nix_app) = dir.join("../Applications/Wawona.app").canonicalize() {
                    candidates.push(nix_app.join("share/X11/xkb"));
                }
            }
        }

        for c in candidates {
            if c.join("rules").is_dir() {
                if let Ok(canonical) = c.canonicalize() {
                    std::env::set_var("XKB_CONFIG_ROOT", &canonical);
                    tracing::info!(
                        "xkb: using bundled keymap root {}",
                        canonical.display()
                    );
                    return;
                }
            }
        }

        tracing::warn!(
            "xkb: no bundled keymap root found; xkbcommon will use its default path"
        );
    });
}

/// The `XkbConfig` used for the seat keyboard on EVERY platform: a full
/// `evdev/us` keymap (NOT the `MINIMAL_KEYMAP`). [`ensure_xkb_data_root`] is
/// invoked first so xkbcommon can find the keymap data. If data is genuinely
/// unavailable the Smithay `add_keyboard` call returns `Err`, and the caller
/// falls back to `MINIMAL_KEYMAP` via `KeyboardHandle::set_keymap_from_string`.
pub fn wawona_xkb_config() -> xkb_config_reexport::XkbConfig<'static> {
    ensure_xkb_data_root();
    xkb_config_reexport::XkbConfig {
        rules: "evdev",
        model: "pc105",
        layout: "us",
        variant: "",
        options: None,
    }
}

/// Re-export so callers don't need to depend on the smithay path directly.
pub mod xkb_config_reexport {
    pub use smithay::input::keyboard::XkbConfig;
}

/// Create a temporary file containing the keymap string
pub fn create_keymap_file(content: &str) -> Result<std::fs::File, ()> {
    use std::io::Write;

    let mut file = tempfile::tempfile().map_err(|_| ())?;
    file.write_all(content.as_bytes()).map_err(|_| ())?;
    file.flush().map_err(|_| ())?;

    Ok(file)
}

pub const MINIMAL_KEYMAP: &str = concat!(
    "xkb_keymap {\n",
    "  xkb_keycodes \"minimal\" {\n",
    "    minimum = 8;\n",
    "    maximum = 255;\n",
    "    <ESC>  = 9;\n",
    "    <AE01> = 10;\n",
    "    <AE02> = 11;\n",
    "    <AE03> = 12;\n",
    "    <AE04> = 13;\n",
    "    <AE05> = 14;\n",
    "    <AE06> = 15;\n",
    "    <AE07> = 16;\n",
    "    <AE08> = 17;\n",
    "    <AE09> = 18;\n",
    "    <AE10> = 19;\n",
    "    <AE11> = 20;\n",
    "    <AE12> = 21;\n",
    "    <BKSP> = 22;\n",
    "    <TAB>  = 23;\n",
    "    <AD01> = 24;\n",
    "    <AD02> = 25;\n",
    "    <AD03> = 26;\n",
    "    <AD04> = 27;\n",
    "    <AD05> = 28;\n",
    "    <AD06> = 29;\n",
    "    <AD07> = 30;\n",
    "    <AD08> = 31;\n",
    "    <AD09> = 32;\n",
    "    <AD10> = 33;\n",
    "    <AD11> = 34;\n",
    "    <AD12> = 35;\n",
    "    <RTRN> = 36;\n",
    "    <LCTL> = 37;\n",
    "    <AC01> = 38;\n",
    "    <AC02> = 39;\n",
    "    <AC03> = 40;\n",
    "    <AC04> = 41;\n",
    "    <AC05> = 42;\n",
    "    <AC06> = 43;\n",
    "    <AC07> = 44;\n",
    "    <AC08> = 45;\n",
    "    <AC09> = 46;\n",
    "    <AC10> = 47;\n",
    "    <AC11> = 48;\n",
    "    <TLDE> = 49;\n",
    "    <LFSH> = 50;\n",
    "    <BKSL> = 51;\n",
    "    <AB01> = 52;\n",
    "    <AB02> = 53;\n",
    "    <AB03> = 54;\n",
    "    <AB04> = 55;\n",
    "    <AB05> = 56;\n",
    "    <AB06> = 57;\n",
    "    <AB07> = 58;\n",
    "    <AB08> = 59;\n",
    "    <AB09> = 60;\n",
    "    <AB10> = 61;\n",
    "    <RTSH> = 62;\n",
    "    <LALT> = 64;\n",
    "    <SPCE> = 65;\n",
    "    <HOME> = 110;\n",
    "    <UP>   = 111;\n",
    "    <PGUP> = 112;\n",
    "    <LEFT> = 113;\n",
    "    <RGHT> = 114;\n",
    "    <END>  = 115;\n",
    "    <DOWN> = 116;\n",
    "    <PGDN> = 117;\n",
    "    <LWIN> = 133;\n",
    "  };\n",
    "  xkb_types \"minimal\" {\n",
    "    type \"ONE_LEVEL\" {\n",
    "      modifiers = none;\n",
    "      map[none] = Level1;\n",
    "      level_name[Level1] = \"Any\";\n",
    "    };\n",
    "    type \"TWO_LEVEL\" {\n",
    "      modifiers = Shift;\n",
    "      map[Shift] = Level2;\n",
    "      level_name[Level1] = \"Base\";\n",
    "      level_name[Level2] = \"Shift\";\n",
    "    };\n",
    "  };\n",
    "  xkb_compatibility \"minimal\" {\n",
    "    interpret Any + AnyOf(all) { action = SetMods(modifiers=modMapMods,clearLocks); };\n",
    "  };\n",
    "  xkb_symbols \"minimal\" {\n",
    "    key <ESC>  { [ Escape ] };\n",
    "    key <AE01> { [ 1, exclam ] };\n",
    "    key <AE02> { [ 2, at ] };\n",
    "    key <AE03> { [ 3, numbersign ] };\n",
    "    key <AE04> { [ 4, dollar ] };\n",
    "    key <AE05> { [ 5, percent ] };\n",
    "    key <AE06> { [ 6, asciicircum ] };\n",
    "    key <AE07> { [ 7, ampersand ] };\n",
    "    key <AE08> { [ 8, asterisk ] };\n",
    "    key <AE09> { [ 9, parenleft ] };\n",
    "    key <AE10> { [ 0, parenright ] };\n",
    "    key <AE11> { [ minus, underscore ] };\n",
    "    key <AE12> { [ equal, plus ] };\n",
    "    key <BKSP> { [ BackSpace ] };\n",
    "    key <TAB>  { [ Tab, ISO_Left_Tab ] };\n",
    "    key <AD01> { [ q, Q ] };\n",
    "    key <AD02> { [ w, W ] };\n",
    "    key <AD03> { [ e, E ] };\n",
    "    key <AD04> { [ r, R ] };\n",
    "    key <AD05> { [ t, T ] };\n",
    "    key <AD06> { [ y, Y ] };\n",
    "    key <AD07> { [ u, U ] };\n",
    "    key <AD08> { [ i, I ] };\n",
    "    key <AD09> { [ o, O ] };\n",
    "    key <AD10> { [ p, P ] };\n",
    "    key <AD11> { [ bracketleft, braceleft ] };\n",
    "    key <AD12> { [ bracketright, braceright ] };\n",
    "    key <RTRN> { [ Return ] };\n",
    "    key <LCTL> { [ Control_L ] };\n",
    "    key <AC01> { [ a, A ] };\n",
    "    key <AC02> { [ s, S ] };\n",
    "    key <AC03> { [ d, D ] };\n",
    "    key <AC04> { [ f, F ] };\n",
    "    key <AC05> { [ g, G ] };\n",
    "    key <AC06> { [ h, H ] };\n",
    "    key <AC07> { [ j, J ] };\n",
    "    key <AC08> { [ k, K ] };\n",
    "    key <AC09> { [ l, L ] };\n",
    "    key <AC10> { [ semicolon, colon ] };\n",
    "    key <AC11> { [ apostrophe, quotedbl ] };\n",
    "    key <TLDE> { [ grave, asciitilde ] };\n",
    "    key <LFSH> { [ Shift_L ] };\n",
    "    key <BKSL> { [ backslash, bar ] };\n",
    "    key <AB01> { [ z, Z ] };\n",
    "    key <AB02> { [ x, X ] };\n",
    "    key <AB03> { [ c, C ] };\n",
    "    key <AB04> { [ v, V ] };\n",
    "    key <AB05> { [ b, B ] };\n",
    "    key <AB06> { [ n, N ] };\n",
    "    key <AB07> { [ m, M ] };\n",
    "    key <AB08> { [ comma, less ] };\n",
    "    key <AB09> { [ period, greater ] };\n",
    "    key <AB10> { [ slash, question ] };\n",
    "    key <RTSH> { [ Shift_R ] };\n",
    "    key <LALT> { [ Alt_L, Meta_L ] };\n",
    "    key <SPCE> { [ space ] };\n",
    "    key <HOME> { [ Home ] };\n",
    "    key <UP>   { [ Up ] };\n",
    "    key <PGUP> { [ Prior ] };\n",
    "    key <LEFT> { [ Left ] };\n",
    "    key <RGHT> { [ Right ] };\n",
    "    key <END>  { [ End ] };\n",
    "    key <DOWN> { [ Down ] };\n",
    "    key <PGDN> { [ Next ] };\n",
    "    key <LWIN> { [ Super_L ] };\n",
    "    modifier_map Shift { <LFSH>, <RTSH> };\n",
    "    modifier_map Control { <LCTL> };\n",
    "    modifier_map Mod1 { <LALT> };\n",
    "    modifier_map Mod4 { <LWIN> };\n",
    "  };\n",
    "};\n"
);
