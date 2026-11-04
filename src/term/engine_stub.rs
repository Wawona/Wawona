//! Temporary VT stub when `libghostty-term` is off (mobile crate2nix).
//! Not a second product parser. Replace by enabling `nix-ghostty-vt` once
//! Ghostty VT cross archives exist for the target.

use super::cell::{ATTR_CURSOR, WwnTermCell, pack_rgb};
use std::sync::{Arc, Mutex};

const DEFAULT_SCROLLBACK: usize = 10_000;
const FG: u32 = 0x00E8E8E8;
const BG: u32 = 0x00000000;

#[derive(Clone, Debug, Default)]
pub struct StyledSpan {
    pub text: String,
    pub fg: u32,
    pub bg: u32,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub blink: bool,
    pub strike: bool,
}

#[derive(Clone, Debug, Default)]
pub struct StyledLine {
    pub spans: Vec<StyledSpan>,
}

#[derive(Clone, Debug, Default)]
pub struct PlacedImage {
    pub id: u32,
    pub col: i32,
    pub row: i32,
    pub x_px: i32,
    pub y_px: i32,
    pub px_w: u32,
    pub px_h: u32,
    pub cols: u32,
    pub rows: u32,
    pub z: i32,
    pub rgba: Vec<u8>,
}

struct Inner {
    cols: u32,
    rows: u32,
    scroll_cap: usize,
    cell_w: u32,
    cell_h: u32,
    title: String,
    reply: Vec<u8>,
    /// Scrollback + viewport as plain lines (no CSI).
    lines: Vec<String>,
    cursor_col: u32,
    cursor_row: u32,
}

pub struct VtEngine {
    inner: Arc<Mutex<Inner>>,
}

impl VtEngine {
    pub fn new(cols: u32, rows: u32) -> Self {
        let cols = cols.clamp(1, 512);
        let rows = rows.clamp(1, 256);
        let mut lines = Vec::with_capacity(rows as usize);
        for _ in 0..rows {
            lines.push(String::new());
        }
        Self {
            inner: Arc::new(Mutex::new(Inner {
                cols,
                rows,
                scroll_cap: DEFAULT_SCROLLBACK,
                cell_w: 8,
                cell_h: 16,
                title: String::new(),
                reply: Vec::new(),
                lines,
                cursor_col: 0,
                cursor_row: 0,
            })),
        }
    }

    pub fn feed(&self, bytes: &[u8]) {
        let Ok(mut g) = self.inner.lock() else {
            return;
        };
        let text = String::from_utf8_lossy(bytes);
        for ch in text.chars() {
            match ch {
                '\n' => {
                    g.cursor_row = g.cursor_row.saturating_add(1);
                    g.cursor_col = 0;
                    while g.lines.len() as u32 <= g.cursor_row {
                        g.lines.push(String::new());
                    }
                    let max = g.scroll_cap.saturating_add(g.rows as usize);
                    if g.lines.len() > max {
                        let drop_n = g.lines.len() - max;
                        g.lines.drain(0..drop_n);
                        g.cursor_row = g.cursor_row.saturating_sub(drop_n as u32);
                    }
                }
                '\r' => g.cursor_col = 0,
                '\u{08}' => {
                    g.cursor_col = g.cursor_col.saturating_sub(1);
                }
                c if !c.is_control() => {
                    let row = g.cursor_row as usize;
                    while g.lines.len() <= row {
                        g.lines.push(String::new());
                    }
                    let line = &mut g.lines[row];
                    let col = g.cursor_col as usize;
                    let mut chars: Vec<char> = line.chars().collect();
                    while chars.len() < col {
                        chars.push(' ');
                    }
                    if col < chars.len() {
                        chars[col] = c;
                    } else {
                        chars.push(c);
                    }
                    *line = chars.into_iter().collect();
                    g.cursor_col = g.cursor_col.saturating_add(1);
                    if g.cursor_col >= g.cols {
                        g.cursor_col = 0;
                        g.cursor_row = g.cursor_row.saturating_add(1);
                    }
                }
                _ => {}
            }
        }
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        let Ok(mut g) = self.inner.lock() else {
            return;
        };
        g.cols = cols.clamp(1, 512);
        g.rows = rows.clamp(1, 256);
        while g.lines.len() < g.rows as usize {
            g.lines.push(String::new());
        }
    }

    pub fn set_cell_px(&self, width: u32, height: u32) {
        if let Ok(mut g) = self.inner.lock() {
            g.cell_w = width.max(1);
            g.cell_h = height.max(1);
        }
    }

    pub fn set_scroll_cap(&self, rows: usize) {
        if let Ok(mut g) = self.inner.lock() {
            g.scroll_cap = rows.max(1);
        }
    }

    pub fn scroll_cap(&self) -> usize {
        self.inner
            .lock()
            .map(|g| g.scroll_cap)
            .unwrap_or(DEFAULT_SCROLLBACK)
    }

    pub fn scroll_to_origin(&self, _origin: u32) {}

    pub fn pointer(&self, _button: u8, _col: u32, _row: u32, _pressed: bool, _motion: bool) {}

    pub fn take_reply(&self) -> Vec<u8> {
        self.inner
            .lock()
            .map(|mut g| std::mem::take(&mut g.reply))
            .unwrap_or_default()
    }

    pub fn title(&self) -> String {
        self.inner
            .lock()
            .map(|g| g.title.clone())
            .unwrap_or_default()
    }

    pub fn cols(&self) -> u32 {
        self.inner.lock().map(|g| g.cols).unwrap_or(80)
    }

    pub fn rows(&self) -> u32 {
        self.inner.lock().map(|g| g.rows).unwrap_or(24)
    }

    pub fn styled_lines(&self) -> Vec<StyledLine> {
        let Ok(g) = self.inner.lock() else {
            return Vec::new();
        };
        let start = g.lines.len().saturating_sub(g.rows as usize);
        g.lines[start..]
            .iter()
            .map(|text| StyledLine {
                spans: vec![StyledSpan {
                    text: text.clone(),
                    fg: FG,
                    bg: BG,
                    ..StyledSpan::default()
                }],
            })
            .collect()
    }

    pub fn lines_json(&self) -> String {
        let lines = self.styled_lines();
        let mut out = String::from("[");
        for (li, line) in lines.iter().enumerate() {
            if li > 0 {
                out.push(',');
            }
            out.push('[');
            for (si, span) in line.spans.iter().enumerate() {
                if si > 0 {
                    out.push(',');
                }
                out.push_str(&format!(
                    "{{\"text\":{},\"fg\":{},\"bg\":{},\"bold\":{},\"italic\":{},\"underline\":{},\"blink\":{},\"strike\":{}}}",
                    json_str(&span.text),
                    span.fg,
                    span.bg,
                    span.bold,
                    span.italic,
                    span.underline,
                    span.blink,
                    span.strike
                ));
            }
            out.push(']');
        }
        out.push(']');
        out
    }

    pub fn write_viewport(&self, _origin: u32, out: &mut [WwnTermCell]) -> (u32, u32, u32) {
        let Ok(g) = self.inner.lock() else {
            return (0, 0, 0);
        };
        let cols = g.cols;
        let rows = g.rows;
        let need = (cols as usize).saturating_mul(rows as usize);
        let n = need.min(out.len());
        for cell in out.iter_mut().take(n) {
            *cell = WwnTermCell {
                cp: 32,
                fg: FG,
                bg: BG,
                attrs: 0,
            };
        }
        let start = g.lines.len().saturating_sub(rows as usize);
        for row in 0..rows as usize {
            let line = g.lines.get(start + row).map(|s| s.as_str()).unwrap_or("");
            for (col, ch) in line.chars().take(cols as usize).enumerate() {
                let idx = row * cols as usize + col;
                if idx >= n {
                    break;
                }
                out[idx].cp = ch as u32;
            }
        }
        let ccol = g.cursor_col.min(cols.saturating_sub(1)) as usize;
        let crow = g
            .cursor_row
            .saturating_sub(start as u32)
            .min(rows.saturating_sub(1)) as usize;
        let cidx = crow * cols as usize + ccol;
        if cidx < n {
            out[cidx].attrs |= ATTR_CURSOR;
            let fg = out[cidx].fg;
            out[cidx].fg = out[cidx].bg;
            out[cidx].bg = if fg == 0 { pack_rgb(0xe8, 0xe8, 0xe8) } else { fg };
        }
        (n as u32, cols, rows)
    }

    pub fn encode_paste(&self, text: &str) -> Vec<u8> {
        text.as_bytes().to_vec()
    }

    pub fn placed_images(&self) -> Vec<PlacedImage> {
        Vec::new()
    }

    pub fn origin(&self) -> u32 {
        0
    }
}

pub fn recommended_scroll_cap(cols: u32) -> usize {
    let cols = cols.max(1) as usize;
    let bytes_per_row = cols.saturating_mul(16).max(1);
    let budget = 8 * 1024 * 1024;
    (budget / bytes_per_row).clamp(1_000, 100_000)
}

fn json_str(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
