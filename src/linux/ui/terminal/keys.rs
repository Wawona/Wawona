//! DEC host modes and GTK key → PTY bytes.

use gtk4 as gtk;

#[derive(Default)]
pub(super) struct HostDecModes {
    cursor_app: bool,
    keypad_app: bool,
    pending: Vec<u8>,
}

impl HostDecModes {
    pub(super) fn observe(&mut self, bytes: &[u8]) {
        self.pending.extend_from_slice(bytes);
        let mut i = 0;
        while i < self.pending.len() {
            if self.pending[i] != 0x1b {
                i += 1;
                continue;
            }
            if i + 1 >= self.pending.len() {
                break;
            }
            match self.pending[i + 1] {
                b'c' => {
                    self.cursor_app = false;
                    self.keypad_app = false;
                    i += 2;
                }
                b'=' => {
                    self.keypad_app = true;
                    i += 2;
                }
                b'>' => {
                    self.keypad_app = false;
                    i += 2;
                }
                b'[' => match self.finish_csi(i + 2) {
                    Some(next) => i = next,
                    None => break,
                },
                _ => i += 1,
            }
        }
        if i > 0 {
            self.pending.drain(..i);
        }
        if self.pending.len() > 32 {
            let drop_n = self.pending.len() - 32;
            self.pending.drain(..drop_n);
        }
    }

    fn finish_csi(&mut self, start: usize) -> Option<usize> {
        let mut j = start;
        let mut private = false;
        if j < self.pending.len() && self.pending[j] == b'?' {
            private = true;
            j += 1;
        }
        let mut params = Vec::new();
        let mut cur = 0i32;
        let mut any = false;
        loop {
            if j >= self.pending.len() {
                return None;
            }
            let c = self.pending[j];
            if c.is_ascii_digit() {
                cur = (cur * 10 + i32::from(c - b'0')).min(9999);
                any = true;
                j += 1;
                continue;
            }
            if c == b';' {
                params.push(if any { cur } else { 0 });
                cur = 0;
                any = false;
                j += 1;
                continue;
            }
            if (0x40..=0x7e).contains(&c) {
                params.push(if any { cur } else { 0 });
                if private && (c == b'h' || c == b'l') {
                    if params.contains(&1) {
                        self.cursor_app = c == b'h';
                    }
                    if params.contains(&66) {
                        self.keypad_app = c == b'l';
                    }
                }
                return Some(j + 1);
            }
            return Some(j + 1);
        }
    }

    pub(super) fn map_key(
        &self,
        key: gtk::gdk::Key,
        state: gtk::gdk::ModifierType,
        bytes: Vec<u8>,
    ) -> Vec<u8> {
        let bare = !state.contains(gtk::gdk::ModifierType::CONTROL_MASK)
            && !state.contains(gtk::gdk::ModifierType::ALT_MASK)
            && !state.contains(gtk::gdk::ModifierType::SHIFT_MASK);
        if bare && self.keypad_app {
            if let Some(letter) = keypad_ss3(key) {
                return vec![0x1b, b'O', letter];
            }
        }
        if self.cursor_app
            && bytes.len() == 3
            && bytes[0] == 0x1b
            && bytes[1] == b'['
            && (b'A'..=b'D').contains(&bytes[2])
        {
            return vec![0x1b, b'O', bytes[2]];
        }
        bytes
    }
}

fn keypad_ss3(key: gtk::gdk::Key) -> Option<u8> {
    Some(match key {
        gtk::gdk::Key::KP_0 => 0x70,
        gtk::gdk::Key::KP_1 => 0x71,
        gtk::gdk::Key::KP_2 => 0x72,
        gtk::gdk::Key::KP_3 => 0x73,
        gtk::gdk::Key::KP_4 => 0x74,
        gtk::gdk::Key::KP_5 => 0x75,
        gtk::gdk::Key::KP_6 => 0x76,
        gtk::gdk::Key::KP_7 => 0x77,
        gtk::gdk::Key::KP_8 => 0x78,
        gtk::gdk::Key::KP_9 => 0x79,
        gtk::gdk::Key::KP_Decimal => 0x6e,
        gtk::gdk::Key::KP_Subtract => 0x6d,
        gtk::gdk::Key::KP_Add => 0x6b,
        gtk::gdk::Key::KP_Multiply => 0x6a,
        gtk::gdk::Key::KP_Divide => 0x6f,
        gtk::gdk::Key::KP_Enter => 0x4d,
        gtk::gdk::Key::KP_Separator => 0x6c,
        gtk::gdk::Key::KP_Equal => 0x58,
        _ => return None,
    })
}

pub(super) fn bytes_for_key(key: gtk::gdk::Key, state: gtk::gdk::ModifierType) -> Vec<u8> {
    let ctrl = state.contains(gtk::gdk::ModifierType::CONTROL_MASK);
    let alt = state.contains(gtk::gdk::ModifierType::ALT_MASK);
    let shift = state.contains(gtk::gdk::ModifierType::SHIFT_MASK);
    if ctrl {
        if let Some(ch) = key.to_unicode() {
            let upper = ch.to_ascii_uppercase();
            if upper.is_ascii() {
                let ascii = upper as u8;
                if (0x40..=0x5F).contains(&ascii) {
                    let byte = ascii & 0x1F;
                    return if alt { vec![0x1b, byte] } else { vec![byte] };
                }
            }
        }
        let extra = match key {
            gtk::gdk::Key::_2 | gtk::gdk::Key::KP_2 => Some(0x00),
            gtk::gdk::Key::_3 => Some(0x1b),
            gtk::gdk::Key::_4 => Some(0x1c),
            gtk::gdk::Key::_5 => Some(0x1d),
            gtk::gdk::Key::_6 | gtk::gdk::Key::KP_6 => Some(0x1e),
            gtk::gdk::Key::_7 | gtk::gdk::Key::minus | gtk::gdk::Key::KP_Subtract => Some(0x1f),
            gtk::gdk::Key::_8 => Some(0x7f),
            gtk::gdk::Key::slash => Some(if shift { 0x7f } else { 0x1f }),
            gtk::gdk::Key::bracketleft => Some(0x1b),
            gtk::gdk::Key::backslash => Some(0x1c),
            gtk::gdk::Key::bracketright => Some(0x1d),
            _ => None,
        };
        if let Some(byte) = extra {
            return if alt { vec![0x1b, byte] } else { vec![byte] };
        }
    }
    let param = 1 + i32::from(shift) + 2 * i32::from(alt) + 4 * i32::from(ctrl);
    let modified = param != 1;
    match key {
        gtk::gdk::Key::Return | gtk::gdk::Key::KP_Enter => {
            if alt {
                b"\x1b\r".to_vec()
            } else {
                b"\r".to_vec()
            }
        }
        gtk::gdk::Key::BackSpace => {
            let byte = if ctrl { 0x08 } else { 0x7f };
            if alt {
                vec![0x1b, byte]
            } else {
                vec![byte]
            }
        }
        gtk::gdk::Key::Tab => {
            if shift {
                b"\x1b[Z".to_vec()
            } else if alt {
                b"\x1b\t".to_vec()
            } else {
                b"\t".to_vec()
            }
        }
        gtk::gdk::Key::Escape => vec![0x1b],
        gtk::gdk::Key::space => {
            if ctrl {
                if alt {
                    vec![0x1b, 0x00]
                } else {
                    vec![0x00]
                }
            } else if alt {
                b"\x1b ".to_vec()
            } else {
                b" ".to_vec()
            }
        }
        gtk::gdk::Key::Up | gtk::gdk::Key::KP_Up => csi_letter(b'A', param, modified, b"\x1b[A"),
        gtk::gdk::Key::Down | gtk::gdk::Key::KP_Down => {
            csi_letter(b'B', param, modified, b"\x1b[B")
        }
        gtk::gdk::Key::Right | gtk::gdk::Key::KP_Right => {
            csi_letter(b'C', param, modified, b"\x1b[C")
        }
        gtk::gdk::Key::Left | gtk::gdk::Key::KP_Left => {
            csi_letter(b'D', param, modified, b"\x1b[D")
        }
        gtk::gdk::Key::Home | gtk::gdk::Key::KP_Home => {
            csi_letter(b'H', param, modified, b"\x1b[H")
        }
        gtk::gdk::Key::End | gtk::gdk::Key::KP_End => csi_letter(b'F', param, modified, b"\x1b[F"),
        gtk::gdk::Key::Page_Up | gtk::gdk::Key::KP_Page_Up => {
            csi_tilde(b'5', param, modified, b"\x1b[5~")
        }
        gtk::gdk::Key::Page_Down | gtk::gdk::Key::KP_Page_Down => {
            csi_tilde(b'6', param, modified, b"\x1b[6~")
        }
        gtk::gdk::Key::Delete | gtk::gdk::Key::KP_Delete => {
            csi_tilde(b'3', param, modified, b"\x1b[3~")
        }
        gtk::gdk::Key::KP_Begin => b"\x1b[E".to_vec(),
        gtk::gdk::Key::KP_Divide => kp_ascii(b'/', alt),
        gtk::gdk::Key::KP_Multiply => kp_ascii(b'*', alt),
        gtk::gdk::Key::KP_Subtract => kp_ascii(b'-', alt),
        gtk::gdk::Key::KP_Add => kp_ascii(b'+', alt),
        gtk::gdk::Key::KP_Equal => kp_ascii(b'=', alt),
        gtk::gdk::Key::KP_Separator => kp_ascii(b',', alt),
        gtk::gdk::Key::Insert | gtk::gdk::Key::KP_Insert => {
            csi_tilde(b'2', param, modified, b"\x1b[2~")
        }
        gtk::gdk::Key::Menu => csi_fn("29", param, modified, b"\x1b[29~"),
        gtk::gdk::Key::Find => csi_tilde(b'1', param, modified, b"\x1b[1~"),
        gtk::gdk::Key::Select => csi_tilde(b'4', param, modified, b"\x1b[4~"),
        gtk::gdk::Key::Help => csi_fn("28", param, modified, b"\x1b[28~"),
        gtk::gdk::Key::F1 => csi_letter(b'P', param, modified, b"\x1bOP"),
        gtk::gdk::Key::F2 => csi_letter(b'Q', param, modified, b"\x1bOQ"),
        gtk::gdk::Key::F3 => csi_letter(b'R', param, modified, b"\x1bOR"),
        gtk::gdk::Key::F4 => csi_letter(b'S', param, modified, b"\x1bOS"),
        gtk::gdk::Key::F5 => csi_fn("15", param, modified, b"\x1b[15~"),
        gtk::gdk::Key::F6 => csi_fn("17", param, modified, b"\x1b[17~"),
        gtk::gdk::Key::F7 => csi_fn("18", param, modified, b"\x1b[18~"),
        gtk::gdk::Key::F8 => csi_fn("19", param, modified, b"\x1b[19~"),
        gtk::gdk::Key::F9 => csi_fn("20", param, modified, b"\x1b[20~"),
        gtk::gdk::Key::F10 => csi_fn("21", param, modified, b"\x1b[21~"),
        gtk::gdk::Key::F11 => csi_fn("23", param, modified, b"\x1b[23~"),
        gtk::gdk::Key::F12 => csi_fn("24", param, modified, b"\x1b[24~"),
        gtk::gdk::Key::F13 => csi_fn("25", param, modified, b"\x1b[25~"),
        gtk::gdk::Key::F14 => csi_fn("26", param, modified, b"\x1b[26~"),
        gtk::gdk::Key::F15 => csi_fn("28", param, modified, b"\x1b[28~"),
        gtk::gdk::Key::F16 => csi_fn("29", param, modified, b"\x1b[29~"),
        gtk::gdk::Key::F17 => csi_fn("31", param, modified, b"\x1b[31~"),
        gtk::gdk::Key::F18 => csi_fn("32", param, modified, b"\x1b[32~"),
        gtk::gdk::Key::F19 => csi_fn("33", param, modified, b"\x1b[33~"),
        gtk::gdk::Key::F20 => csi_fn("34", param, modified, b"\x1b[34~"),
        _ => {
            let Some(ch) = key.to_unicode() else {
                return Vec::new();
            };
            let mut bytes = ch.to_string().into_bytes();
            if alt {
                bytes.insert(0, 0x1b);
            }
            bytes
        }
    }
}

fn kp_ascii(byte: u8, alt: bool) -> Vec<u8> {
    if alt {
        vec![0x1b, byte]
    } else {
        vec![byte]
    }
}

fn csi_letter(letter: u8, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[1;{param}{}", letter as char).into_bytes()
}

fn csi_fn(code: &str, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[{code};{param}~").into_bytes()
}

fn csi_tilde(code: u8, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[{};{param}~", code as char).into_bytes()
}

