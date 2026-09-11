//! Host keymap bridge. Wawona does not own layouts.
//!
//! `generate_from_host()` prefers a live dump (macOS `UCKeyTranslate`,
//! Android `KeyCharacterMap`). iOS family has no public TIS dump, so the
//! seat stays on [`MINIMAL_KEYMAP`]. Soft printable text is still TI v3.

use std::collections::HashMap;
use std::sync::Mutex;

use super::xkb::MINIMAL_KEYMAP;

/// Host-native key identity before the evdev scancode map.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostKeyCode {
    /// Already a Linux evdev scancode (adapters that mapped position).
    Evdev(u32),
    /// macOS `NSEvent.keyCode` (kVK).
    MacVk(u16),
    /// HID usage (iPad / external keyboard).
    HidUsage(u32),
    /// Android `AKEYCODE_*`.
    AndroidKeycode(i32),
}

/// Unicode from the host IME. Soft keys and composition use TI v3, not this
/// enum, on the FFI path (`WWNCoreTextInputCommit`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TextEvent {
    Preedit { text: String, begin: i32, end: i32 },
    Commit(String),
}

/// `WWNApplyHostKeyLevels` kind: macOS `NSEvent.keyCode`.
pub const HOST_KEY_KIND_MAC_VK: i32 = 1;
/// `WWNApplyHostKeyLevels` kind: Android `AKEYCODE_*`.
pub const HOST_KEY_KIND_ANDROID: i32 = 2;

/// Bridge from the host keyboard into Wayland.
///
/// Implementations must generate or fall back. Do not seal the seat to a
/// `MINIMAL_KEYMAP` constant as the only API.
pub trait HostKeymapBridge: Send + Sync {
    fn keymap_xkb_v1(&self) -> String;
    fn physical_key(&self, host: HostKeyCode) -> Option<u32>;
}

/// One printable key we can fill from the host. Position maps only.
#[derive(Debug, Clone, Copy)]
struct HostKeySpec {
    xkb_name: &'static str,
    evdev: u32,
    kvk: u16,
    akeycode: i32,
}

/// Letter / number / punct rows in [`MINIMAL_KEYMAP`]. kVK from HIToolbox.
/// AKEYCODE from `android/view/KeyEvent`.
const HOST_KEYS: &[HostKeySpec] = &[
    HostKeySpec { xkb_name: "AE01", evdev: 2, kvk: 18, akeycode: 8 },
    HostKeySpec { xkb_name: "AE02", evdev: 3, kvk: 19, akeycode: 9 },
    HostKeySpec { xkb_name: "AE03", evdev: 4, kvk: 20, akeycode: 10 },
    HostKeySpec { xkb_name: "AE04", evdev: 5, kvk: 21, akeycode: 11 },
    HostKeySpec { xkb_name: "AE05", evdev: 6, kvk: 23, akeycode: 12 },
    HostKeySpec { xkb_name: "AE06", evdev: 7, kvk: 22, akeycode: 13 },
    HostKeySpec { xkb_name: "AE07", evdev: 8, kvk: 26, akeycode: 14 },
    HostKeySpec { xkb_name: "AE08", evdev: 9, kvk: 28, akeycode: 15 },
    HostKeySpec { xkb_name: "AE09", evdev: 10, kvk: 25, akeycode: 16 },
    HostKeySpec { xkb_name: "AE10", evdev: 11, kvk: 29, akeycode: 7 },
    HostKeySpec { xkb_name: "AE11", evdev: 12, kvk: 27, akeycode: 69 },
    HostKeySpec { xkb_name: "AE12", evdev: 13, kvk: 24, akeycode: 70 },
    HostKeySpec { xkb_name: "AD01", evdev: 16, kvk: 12, akeycode: 45 },
    HostKeySpec { xkb_name: "AD02", evdev: 17, kvk: 13, akeycode: 51 },
    HostKeySpec { xkb_name: "AD03", evdev: 18, kvk: 14, akeycode: 33 },
    HostKeySpec { xkb_name: "AD04", evdev: 19, kvk: 15, akeycode: 46 },
    HostKeySpec { xkb_name: "AD05", evdev: 20, kvk: 17, akeycode: 48 },
    HostKeySpec { xkb_name: "AD06", evdev: 21, kvk: 16, akeycode: 53 },
    HostKeySpec { xkb_name: "AD07", evdev: 22, kvk: 32, akeycode: 49 },
    HostKeySpec { xkb_name: "AD08", evdev: 23, kvk: 34, akeycode: 37 },
    HostKeySpec { xkb_name: "AD09", evdev: 24, kvk: 31, akeycode: 43 },
    HostKeySpec { xkb_name: "AD10", evdev: 25, kvk: 35, akeycode: 44 },
    HostKeySpec { xkb_name: "AD11", evdev: 26, kvk: 33, akeycode: 71 },
    HostKeySpec { xkb_name: "AD12", evdev: 27, kvk: 30, akeycode: 72 },
    HostKeySpec { xkb_name: "AC01", evdev: 30, kvk: 0, akeycode: 29 },
    HostKeySpec { xkb_name: "AC02", evdev: 31, kvk: 1, akeycode: 47 },
    HostKeySpec { xkb_name: "AC03", evdev: 32, kvk: 2, akeycode: 32 },
    HostKeySpec { xkb_name: "AC04", evdev: 33, kvk: 3, akeycode: 34 },
    HostKeySpec { xkb_name: "AC05", evdev: 34, kvk: 5, akeycode: 35 },
    HostKeySpec { xkb_name: "AC06", evdev: 35, kvk: 4, akeycode: 36 },
    HostKeySpec { xkb_name: "AC07", evdev: 36, kvk: 38, akeycode: 38 },
    HostKeySpec { xkb_name: "AC08", evdev: 37, kvk: 40, akeycode: 39 },
    HostKeySpec { xkb_name: "AC09", evdev: 38, kvk: 37, akeycode: 40 },
    HostKeySpec { xkb_name: "AC10", evdev: 39, kvk: 41, akeycode: 74 },
    HostKeySpec { xkb_name: "AC11", evdev: 40, kvk: 39, akeycode: 75 },
    HostKeySpec { xkb_name: "TLDE", evdev: 41, kvk: 50, akeycode: 68 },
    HostKeySpec { xkb_name: "BKSL", evdev: 43, kvk: 42, akeycode: 73 },
    HostKeySpec { xkb_name: "AB01", evdev: 44, kvk: 6, akeycode: 54 },
    HostKeySpec { xkb_name: "AB02", evdev: 45, kvk: 7, akeycode: 52 },
    HostKeySpec { xkb_name: "AB03", evdev: 46, kvk: 8, akeycode: 31 },
    HostKeySpec { xkb_name: "AB04", evdev: 47, kvk: 9, akeycode: 50 },
    HostKeySpec { xkb_name: "AB05", evdev: 48, kvk: 11, akeycode: 30 },
    HostKeySpec { xkb_name: "AB06", evdev: 49, kvk: 45, akeycode: 42 },
    HostKeySpec { xkb_name: "AB07", evdev: 50, kvk: 46, akeycode: 41 },
    HostKeySpec { xkb_name: "AB08", evdev: 51, kvk: 43, akeycode: 55 },
    HostKeySpec { xkb_name: "AB09", evdev: 52, kvk: 47, akeycode: 56 },
    HostKeySpec { xkb_name: "AB10", evdev: 53, kvk: 44, akeycode: 76 },
];

/// Modifier / nav keys. Position only (not dumped as letters).
const PHYSICAL_ONLY: &[(HostKeyCode, u32)] = &[
    (HostKeyCode::MacVk(36), 28),  // Return
    (HostKeyCode::MacVk(48), 15),  // Tab
    (HostKeyCode::MacVk(49), 57),  // Space
    (HostKeyCode::MacVk(51), 14),  // Backspace
    (HostKeyCode::MacVk(53), 1),   // Esc
    (HostKeyCode::MacVk(55), 125), // Command
    (HostKeyCode::MacVk(54), 126), // Right Command
    (HostKeyCode::MacVk(56), 42),  // Shift L
    (HostKeyCode::MacVk(60), 54),  // Shift R
    (HostKeyCode::MacVk(58), 56),  // Option L
    (HostKeyCode::MacVk(61), 100), // Option R
    (HostKeyCode::MacVk(59), 29),  // Control L
    (HostKeyCode::MacVk(62), 97),  // Control R
    (HostKeyCode::MacVk(123), 105),
    (HostKeyCode::MacVk(124), 106),
    (HostKeyCode::MacVk(125), 108),
    (HostKeyCode::MacVk(126), 103),
    (HostKeyCode::AndroidKeycode(66), 28), // ENTER
    (HostKeyCode::AndroidKeycode(61), 15), // TAB
    (HostKeyCode::AndroidKeycode(62), 57), // SPACE
    (HostKeyCode::AndroidKeycode(67), 14), // DEL
    (HostKeyCode::AndroidKeycode(111), 1), // ESCAPE
];

static HOST_LEVELS: Mutex<Option<HashMap<&'static str, [u32; 4]>>> = Mutex::new(None);

/// Seat keymap. Live dump when the host has pushed levels; else US fallback.
pub fn generate_from_host() -> String {
    if let Some(dumped) = dump_host_layout_xkb_v1() {
        return dumped;
    }
    MINIMAL_KEYMAP.to_string()
}

fn dump_host_layout_xkb_v1() -> Option<String> {
    let guard = HOST_LEVELS.lock().ok()?;
    let levels = guard.as_ref()?;
    if levels.is_empty() {
        return None;
    }
    Some(emit_xkb_from_host_levels(levels))
}

/// Host glue (macOS TIS / Android KCM) pushes UTF-32 levels for known keys.
/// `kind` is [`HOST_KEY_KIND_MAC_VK`] or [`HOST_KEY_KIND_ANDROID`].
/// `ids[i]` pairs with `levels[i*4 .. i*4+4]` (none, Shift, Option, Shift+Option).
pub fn apply_host_key_levels(kind: i32, ids: &[i32], levels: &[u32]) {
    if ids.is_empty() || levels.len() < ids.len().saturating_mul(4) {
        return;
    }
    let mut map: HashMap<&'static str, [u32; 4]> = HashMap::new();
    for (i, id) in ids.iter().copied().enumerate() {
        let spec = HOST_KEYS.iter().find(|s| match kind {
            HOST_KEY_KIND_MAC_VK => s.kvk as i32 == id,
            HOST_KEY_KIND_ANDROID => s.akeycode == id,
            _ => false,
        });
        let Some(spec) = spec else {
            continue;
        };
        let base = i * 4;
        let lv = [
            levels[base],
            levels[base + 1],
            levels[base + 2],
            levels[base + 3],
        ];
        if lv[0] == 0 && lv[1] == 0 {
            continue;
        }
        map.insert(spec.xkb_name, lv);
    }
    if let Ok(mut guard) = HOST_LEVELS.lock() {
        *guard = if map.is_empty() { None } else { Some(map) };
    }
}

/// Test / host-layout-change helper. Clears the live dump (US fallback).
pub fn clear_host_key_levels() {
    if let Ok(mut guard) = HOST_LEVELS.lock() {
        *guard = None;
    }
}

/// Fill [`MINIMAL_KEYMAP`] letter rows from host Unicode. Unknown keys stay US.
pub fn emit_xkb_from_host_levels(levels: &HashMap<&'static str, [u32; 4]>) -> String {
    let mut out = MINIMAL_KEYMAP.to_string();
    let mut need_four = false;
    for spec in HOST_KEYS {
        let Some(lv) = levels.get(spec.xkb_name) else {
            continue;
        };
        if lv[2] != 0 || lv[3] != 0 {
            need_four = true;
        }
        let line = format_key_line(spec.xkb_name, lv);
        out = replace_key_line(&out, spec.xkb_name, &line);
    }
    if need_four {
        out = inject_four_level_type(&out);
    }
    out
}

fn format_key_line(name: &str, lv: &[u32; 4]) -> String {
    let a = keysym_token(lv[0]);
    let b = keysym_token(if lv[1] != 0 { lv[1] } else { 0 });
    if lv[2] == 0 && lv[3] == 0 {
        if lv[1] == 0 {
            return format!("key <{name}> {{ [ {a} ] }};");
        }
        return format!("key <{name}> {{ [ {a}, {b} ] }};");
    }
    let c = keysym_token(lv[2]);
    let d = keysym_token(lv[3]);
    format!("key <{name}> {{ type = \"FOUR_LEVEL\", [ {a}, {b}, {c}, {d} ] }};")
}

fn replace_key_line(keymap: &str, name: &str, new_line: &str) -> String {
    let needle = format!("key <{name}>");
    let mut out = String::with_capacity(keymap.len() + 32);
    for line in keymap.lines() {
        if line.trim_start().starts_with(&needle) {
            let indent_len = line.len() - line.trim_start().len();
            out.push_str(&line[..indent_len]);
            out.push_str(new_line);
            out.push('\n');
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

fn inject_four_level_type(keymap: &str) -> String {
    if keymap.contains("type \"FOUR_LEVEL\"") {
        return keymap.to_string();
    }
    const TYPE: &str = concat!(
        "    type \"FOUR_LEVEL\" {\n",
        "      modifiers = Shift+Mod1;\n",
        "      map[Shift] = Level2;\n",
        "      map[Mod1] = Level3;\n",
        "      map[Shift+Mod1] = Level4;\n",
        "      level_name[Level1] = \"Base\";\n",
        "      level_name[Level2] = \"Shift\";\n",
        "      level_name[Level3] = \"AltGr\";\n",
        "      level_name[Level4] = \"Shift AltGr\";\n",
        "    };\n",
    );
    keymap.replacen(
        "    type \"TWO_LEVEL\" {\n",
        &format!("{TYPE}    type \"TWO_LEVEL\" {{\n"),
        1,
    )
}

fn keysym_token(ch: u32) -> String {
    if ch == 0 {
        return "NoSymbol".into();
    }
    let Some(c) = char::from_u32(ch) else {
        return format!("U{ch:04X}");
    };
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
        return c.to_string();
    }
    if c == ' ' {
        return "space".into();
    }
    match c {
        '!' => "exclam",
        '@' => "at",
        '#' => "numbersign",
        '$' => "dollar",
        '%' => "percent",
        '^' => "asciicircum",
        '&' => "ampersand",
        '*' => "asterisk",
        '(' => "parenleft",
        ')' => "parenright",
        '-' => "minus",
        '_' => "underscore",
        '=' => "equal",
        '+' => "plus",
        '[' => "bracketleft",
        ']' => "bracketright",
        '{' => "braceleft",
        '}' => "braceright",
        ';' => "semicolon",
        ':' => "colon",
        '\'' => "apostrophe",
        '"' => "quotedbl",
        '`' => "grave",
        '~' => "asciitilde",
        '\\' => "backslash",
        '|' => "bar",
        ',' => "comma",
        '<' => "less",
        '.' => "period",
        '>' => "greater",
        '/' => "slash",
        '?' => "question",
        _ => return format!("U{:04X}", ch),
    }
    .into()
}

/// Default bridge used by the Smithay seat.
#[derive(Debug, Default, Clone, Copy)]
pub struct FallbackHostKeymap;

impl HostKeymapBridge for FallbackHostKeymap {
    fn keymap_xkb_v1(&self) -> String {
        generate_from_host()
    }

    fn physical_key(&self, host: HostKeyCode) -> Option<u32> {
        match host {
            HostKeyCode::Evdev(code) => Some(code),
            HostKeyCode::MacVk(kvk) => HOST_KEYS
                .iter()
                .find(|s| s.kvk == kvk)
                .map(|s| s.evdev)
                .or_else(|| {
                    PHYSICAL_ONLY.iter().find_map(|(h, ev)| match h {
                        HostKeyCode::MacVk(k) if *k == kvk => Some(*ev),
                        _ => None,
                    })
                }),
            HostKeyCode::AndroidKeycode(code) => HOST_KEYS
                .iter()
                .find(|s| s.akeycode == code)
                .map(|s| s.evdev)
                .or_else(|| {
                    PHYSICAL_ONLY.iter().find_map(|(h, ev)| match h {
                        HostKeyCode::AndroidKeycode(k) if *k == code => Some(*ev),
                        _ => None,
                    })
                }),
            // HID usage stays in the Apple adapter until a shared table lands.
            HostKeyCode::HidUsage(_) => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn us_letter_levels() -> HashMap<&'static str, [u32; 4]> {
        let mut m = HashMap::new();
        m.insert("AC01", [u32::from(b'a'), u32::from(b'A'), 0, 0]);
        m.insert("AD01", [u32::from(b'q'), u32::from(b'Q'), 0, 0]);
        m.insert("AB01", [u32::from(b'z'), u32::from(b'Z'), 0, 0]);
        m
    }

    #[test]
    fn generate_from_host_matches_us_letter_rows() {
        clear_host_key_levels();
        let km = generate_from_host();
        assert!(
            km.contains("key <AC01> { [ a, A ] }"),
            "US home row A missing: {km}"
        );
        assert!(
            km.contains("key <AD01> { [ q, Q ] }"),
            "US Q row missing: {km}"
        );
        assert!(
            km.contains("key <AB01> { [ z, Z ] }"),
            "US Z row missing: {km}"
        );
        assert!(km.contains("xkb_keymap {"), "not XKB v1: {km}");
    }

    #[test]
    fn us_dump_matches_minimal_letter_rows() {
        let km = emit_xkb_from_host_levels(&us_letter_levels());
        assert!(km.contains("key <AC01> { [ a, A ] }"));
        assert!(km.contains("key <AD01> { [ q, Q ] }"));
        assert!(km.contains("key <AB01> { [ z, Z ] }"));
    }

    #[test]
    fn french_like_levels_emit_a_on_ad01() {
        let mut levels = us_letter_levels();
        levels.insert("AD01", [u32::from(b'a'), u32::from(b'A'), 0, 0]);
        let km = emit_xkb_from_host_levels(&levels);
        assert!(
            km.contains("key <AD01> { [ a, A ] }"),
            "AZERTY Q position must be a: {km}"
        );
        assert!(
            !km.contains("key <AD01> { [ q, Q ] }"),
            "must not keep US q on AD01: {km}"
        );
    }

    #[test]
    fn apply_mac_vk_q_as_a_then_generate() {
        clear_host_key_levels();
        // kVK 12 is Q position (AD01). Host French: a/A.
        apply_host_key_levels(
            HOST_KEY_KIND_MAC_VK,
            &[12],
            &[u32::from(b'a'), u32::from(b'A'), 0, 0],
        );
        let km = generate_from_host();
        assert!(km.contains("key <AD01> { [ a, A ] }"), "{km}");
        clear_host_key_levels();
    }

    #[test]
    fn fallback_bridge_uses_generate_from_host() {
        clear_host_key_levels();
        let bridge = FallbackHostKeymap;
        assert_eq!(bridge.keymap_xkb_v1(), generate_from_host());
        assert_eq!(bridge.physical_key(HostKeyCode::Evdev(30)), Some(30));
        assert_eq!(bridge.physical_key(HostKeyCode::MacVk(0)), Some(30)); // A
        assert_eq!(bridge.physical_key(HostKeyCode::MacVk(12)), Some(16)); // Q
        assert_eq!(
            bridge.physical_key(HostKeyCode::AndroidKeycode(29)),
            Some(30)
        );
        assert_eq!(bridge.physical_key(HostKeyCode::HidUsage(0x04)), None);
    }
}
