//! Temporary VT stub when `libghostty-term` is off (mobile crate2nix).
//! Not a second product parser. Replace by enabling `nix-ghostty-vt` once
//! Ghostty VT cross archives exist for the target.
//!
//! Strips CSI / OSC so Metal Present does not paint raw SGR as glyphs.
//! Basic SGR colors only. Real styling stays libghostty-vt.

use super::cell::{ATTR_BOLD, ATTR_CURSOR, WwnTermCell, pack_rgb};
use std::sync::{Arc, Mutex};

const DEFAULT_SCROLLBACK: usize = 10_000;
/// An unterminated OSC longer than this is dropped instead of buffered.
const MAX_PENDING: usize = 4096;
const FG: u32 = 0x00E8E8E8;
const BG: u32 = 0x00000000;

/// Selection gesture mode (matches real `engine::SelectMode`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SelectMode {
    Cell = 0,
    Word = 1,
    Row = 2,
}

impl SelectMode {
    pub fn from_u32(v: u32) -> Self {
        match v {
            1 => Self::Word,
            2 => Self::Row,
            _ => Self::Cell,
        }
    }
}

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

#[derive(Clone, Copy, Debug)]
struct StubCell {
    ch: char,
    fg: u32,
    bg: u32,
    bold: bool,
}

impl Default for StubCell {
    fn default() -> Self {
        Self {
            ch: ' ',
            fg: FG,
            bg: BG,
            bold: false,
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct Pen {
    fg: u32,
    bg: u32,
    bold: bool,
}

impl Default for Pen {
    fn default() -> Self {
        Self {
            fg: FG,
            bg: BG,
            bold: false,
        }
    }
}

struct Inner {
    cols: u32,
    rows: u32,
    scroll_cap: usize,
    scroll_origin: u32,
    scroll_total: u32,
    cell_w: u32,
    cell_h: u32,
    title: String,
    reply: Vec<u8>,
    /// Scrollback + viewport. CSI stripped; basic SGR applied.
    lines: Vec<Vec<StubCell>>,
    cursor_col: u32,
    cursor_row: u32,
    pen: Pen,
    /// Bytes of an escape or UTF-8 sequence cut off at the end of the last
    /// feed. PTY reads split sequences anywhere.
    pending: Vec<u8>,
    /// DECSET 2004 (bracketed paste) from the shell.
    bracketed_paste: bool,
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
            lines.push(Vec::new());
        }
        Self {
            inner: Arc::new(Mutex::new(Inner {
                cols,
                rows,
                scroll_cap: DEFAULT_SCROLLBACK,
                scroll_origin: 0,
                scroll_total: rows,
                cell_w: 8,
                cell_h: 16,
                title: String::new(),
                reply: Vec::new(),
                lines,
                cursor_col: 0,
                cursor_row: 0,
                pen: Pen::default(),
                pending: Vec::new(),
                bracketed_paste: false,
            })),
        }
    }

    pub fn feed(&self, bytes: &[u8]) {
        let Ok(mut g) = self.inner.lock() else {
            return;
        };
        let mut buf = std::mem::take(&mut g.pending);
        buf.extend_from_slice(bytes);
        let cut = match std::str::from_utf8(&buf) {
            Ok(_) => buf.len(),
            Err(e) if e.error_len().is_none() => e.valid_up_to(),
            Err(_) => buf.len(),
        };
        let tail = buf.split_off(cut);
        let text = String::from_utf8_lossy(&buf);
        let chars: Vec<char> = text.chars().collect();
        let mut i = 0usize;
        while i < chars.len() {
            let ch = chars[i];
            match ch {
                '\n' => {
                    newline(&mut g);
                    i += 1;
                }
                '\r' => {
                    g.cursor_col = 0;
                    i += 1;
                }
                '\u{08}' => {
                    g.cursor_col = g.cursor_col.saturating_sub(1);
                    i += 1;
                }
                '\u{1b}' | '\u{9b}' => {
                    let next = if ch == '\u{1b}' {
                        consume_escape(&mut g, &chars, i)
                    } else {
                        // C1 CSI (8-bit): single-byte 0x9b is ESC [.
                        consume_csi_from(&mut g, &chars, i + 1)
                    };
                    match next {
                        Some(next) => i = next,
                        None => {
                            let rest: String = chars[i..].iter().collect();
                            if rest.len() <= MAX_PENDING {
                                g.pending = rest.into_bytes();
                            }
                            break;
                        }
                    }
                }
                // Orphan CSI: ESC already stripped upstream (fake PTY / filter).
                // `\[` + params + final letter. Same as ESC[ without the ESC.
                '[' if looks_like_orphan_csi(&chars, i) => {
                    i = consume_csi_from(&mut g, &chars, i + 1).unwrap_or(chars.len());
                }
                c if !c.is_control() => {
                    put_char(&mut g, c);
                    i += 1;
                }
                _ => {
                    i += 1;
                }
            }
        }
        g.pending.extend_from_slice(&tail);
        g.scroll_total = g.lines.len() as u32;
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        let Ok(mut g) = self.inner.lock() else {
            return;
        };
        g.cols = cols.clamp(1, 512);
        g.rows = rows.clamp(1, 256);
        while g.lines.len() < g.rows as usize {
            g.lines.push(Vec::new());
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

    pub fn scroll_to_origin(&self, origin: u32) {
        if let Ok(mut g) = self.inner.lock() {
            g.scroll_origin = origin;
        }
    }

    pub fn scroll_delta(&self, delta: i32) {
        if let Ok(mut g) = self.inner.lock() {
            let next = (g.scroll_origin as i64) + i64::from(delta);
            g.scroll_origin = next.clamp(0, i64::from(u32::MAX)) as u32;
        }
    }

    pub fn scroll_to_bottom(&self) {
        if let Ok(mut g) = self.inner.lock() {
            g.scroll_origin = g.scroll_total.saturating_sub(g.rows);
        }
    }

    pub fn pointer(&self, _button: u8, _col: u32, _row: u32, _pressed: bool, _motion: bool) {}

    /// Soft-key / host keypath. Stub feeds printable UTF-8 into the line buffer.
    pub fn key(&self, _keycode: u32, _mods: u32, _action: u32, text: &[u8]) {
        if !text.is_empty() {
            self.feed(text);
        }
    }

    pub fn select_begin(&self, _col: u32, _row: u32, _mode: SelectMode) {}

    pub fn select_extend(&self, _col: u32, _row: u32) {}

    pub fn select_clear(&self) {}

    pub fn select_all(&self) {}

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
            .map(|row| StyledLine {
                spans: spans_from_cells(row),
            })
            .collect()
    }

    pub fn lines_json(&self) -> String {
        // Same host ABI as real engine: [{"spans":[…]}, …]
        let lines = self.styled_lines();
        let mut out = String::from("[");
        for (li, line) in lines.iter().enumerate() {
            if li > 0 {
                out.push(',');
            }
            out.push_str("{\"spans\":[");
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
            out.push_str("]}");
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
            let line = g.lines.get(start + row).map(|s| s.as_slice()).unwrap_or(&[]);
            for (col, cell) in line.iter().take(cols as usize).enumerate() {
                let idx = row * cols as usize + col;
                if idx >= n {
                    break;
                }
                out[idx].cp = cell.ch as u32;
                out[idx].fg = cell.fg;
                out[idx].bg = cell.bg;
                if cell.bold {
                    out[idx].attrs |= ATTR_BOLD;
                }
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
        let bracketed = self.inner.lock().map(|g| g.bracketed_paste).unwrap_or(false);
        if !bracketed {
            return text.as_bytes().to_vec();
        }
        let mut out = b"\x1b[200~".to_vec();
        out.extend(text.bytes().filter(|&b| b != 0x1b));
        out.extend_from_slice(b"\x1b[201~");
        out
    }

    pub fn placed_images(&self) -> Vec<PlacedImage> {
        Vec::new()
    }

    pub fn origin(&self) -> u32 {
        self.inner
            .lock()
            .map(|g| g.scroll_origin)
            .unwrap_or(0)
    }

    pub fn scroll_total(&self) -> u32 {
        self.inner
            .lock()
            .map(|g| g.scroll_total)
            .unwrap_or(0)
    }

    /// Stub has no Ghostty selection. Always empty (do not invent text).
    pub fn selection_text(&self) -> String {
        String::new()
    }
}

pub fn recommended_scroll_cap(cols: u32) -> usize {
    let cols = cols.max(1) as usize;
    let bytes_per_row = cols.saturating_mul(16).max(1);
    let budget = 8 * 1024 * 1024;
    (budget / bytes_per_row).clamp(1_000, 100_000)
}

fn spans_from_cells(row: &[StubCell]) -> Vec<StyledSpan> {
    if row.is_empty() {
        return vec![StyledSpan {
            text: String::new(),
            fg: FG,
            bg: BG,
            ..StyledSpan::default()
        }];
    }
    let mut spans = Vec::new();
    let mut cur = StyledSpan {
        text: String::new(),
        fg: row[0].fg,
        bg: row[0].bg,
        bold: row[0].bold,
        ..StyledSpan::default()
    };
    for cell in row {
        if cell.fg != cur.fg || cell.bg != cur.bg || cell.bold != cur.bold {
            if !cur.text.is_empty() {
                spans.push(cur);
            }
            cur = StyledSpan {
                text: String::new(),
                fg: cell.fg,
                bg: cell.bg,
                bold: cell.bold,
                ..StyledSpan::default()
            };
        }
        cur.text.push(cell.ch);
    }
    if !cur.text.is_empty() {
        spans.push(cur);
    }
    spans
}

fn newline(g: &mut Inner) {
    g.cursor_row = g.cursor_row.saturating_add(1);
    g.cursor_col = 0;
    while g.lines.len() as u32 <= g.cursor_row {
        g.lines.push(Vec::new());
    }
    let max = g.scroll_cap.saturating_add(g.rows as usize);
    if g.lines.len() > max {
        let drop_n = g.lines.len() - max;
        g.lines.drain(0..drop_n);
        g.cursor_row = g.cursor_row.saturating_sub(drop_n as u32);
    }
}

fn put_char(g: &mut Inner, c: char) {
    let row = g.cursor_row as usize;
    let col = g.cursor_col as usize;
    while g.lines.len() <= row {
        g.lines.push(Vec::new());
    }
    let line = &mut g.lines[row];
    while line.len() < col {
        line.push(StubCell::default());
    }
    let cell = StubCell {
        ch: c,
        fg: g.pen.fg,
        bg: g.pen.bg,
        bold: g.pen.bold,
    };
    if col < line.len() {
        line[col] = cell;
    } else {
        line.push(cell);
    }
    g.cursor_col = g.cursor_col.saturating_add(1);
    if g.cursor_col >= g.cols {
        newline(g);
    }
}

/// True when `chars[i]` is `[` and the following bytes look like CSI params + final.
fn looks_like_orphan_csi(chars: &[char], i: usize) -> bool {
    if i >= chars.len() || chars[i] != '[' {
        return false;
    }
    let mut j = i + 1;
    while j < chars.len() {
        let c = chars[j];
        if c.is_ascii_digit() || c == ';' || c == '?' || c == '>' || c == ' ' {
            j += 1;
            continue;
        }
        // Final byte of CSI. Only treat SGR / erase / cursor as orphan (avoid
        // eating literal `[` in shell output like `[1]`).
        return matches!(c, 'm' | 'K' | 'J' | 'H' | 'f' | 'A'..='G');
    }
    false
}

/// Consume CSI params starting at `params_at` (first char after `[`). Returns
/// the index past the final byte, or `None` when the sequence is cut off.
fn consume_csi_from(g: &mut Inner, chars: &[char], params_at: usize) -> Option<usize> {
    let mut j = params_at;
    while j < chars.len() {
        let c = chars[j];
        if c.is_ascii_alphabetic() || c == '@' || c == '~' {
            let params: String = chars[params_at..j].iter().collect();
            apply_csi(g, &params, c);
            return Some(j + 1);
        }
        j += 1;
    }
    None
}

/// First numeric CSI parameter, `default` when absent or zero.
fn csi_arg(params: &str, index: usize, default: u32) -> u32 {
    params
        .trim_start_matches('?')
        .split(';')
        .nth(index)
        .and_then(|p| p.parse::<u32>().ok())
        .filter(|&n| n > 0)
        .unwrap_or(default)
}

fn current_line(g: &mut Inner) -> &mut Vec<StubCell> {
    let row = g.cursor_row as usize;
    while g.lines.len() <= row {
        g.lines.push(Vec::new());
    }
    &mut g.lines[row]
}

fn apply_csi(g: &mut Inner, params: &str, fin: char) {
    let max_col = g.cols.saturating_sub(1);
    match fin {
        'm' => apply_sgr(g, params),
        'A' => g.cursor_row = g.cursor_row.saturating_sub(csi_arg(params, 0, 1)),
        'B' => {
            g.cursor_row += csi_arg(params, 0, 1).min(g.rows);
            current_line(g);
        }
        'C' => g.cursor_col = (g.cursor_col + csi_arg(params, 0, 1)).min(max_col),
        'D' => g.cursor_col = g.cursor_col.saturating_sub(csi_arg(params, 0, 1)),
        'G' => g.cursor_col = (csi_arg(params, 0, 1) - 1).min(max_col),
        'H' | 'f' => {
            let top = g.lines.len().saturating_sub(g.rows as usize) as u32;
            g.cursor_row = top + (csi_arg(params, 0, 1) - 1).min(g.rows.saturating_sub(1));
            g.cursor_col = (csi_arg(params, 1, 1) - 1).min(max_col);
        }
        'K' => {
            let col = g.cursor_col as usize;
            let mode = params.parse::<u32>().unwrap_or(0);
            let line = current_line(g);
            match mode {
                1 => {
                    for cell in line.iter_mut().take(col + 1) {
                        *cell = StubCell::default();
                    }
                }
                2 => line.clear(),
                _ => line.truncate(col),
            }
        }
        'J' => {
            let mode = params.parse::<u32>().unwrap_or(0);
            let row = g.cursor_row as usize;
            let col = g.cursor_col as usize;
            if mode == 0 {
                if let Some(line) = g.lines.get_mut(row) {
                    line.truncate(col);
                }
                for line in g.lines.iter_mut().skip(row + 1) {
                    line.clear();
                }
            } else if mode == 2 {
                let top = g.lines.len().saturating_sub(g.rows as usize);
                for line in g.lines.iter_mut().skip(top) {
                    line.clear();
                }
            }
        }
        'P' => {
            let col = g.cursor_col as usize;
            let n = csi_arg(params, 0, 1) as usize;
            let line = current_line(g);
            if col < line.len() {
                let end = (col + n).min(line.len());
                line.drain(col..end);
            }
        }
        '@' => {
            let col = g.cursor_col as usize;
            let n = csi_arg(params, 0, 1) as usize;
            let line = current_line(g);
            if col <= line.len() {
                for _ in 0..n {
                    line.insert(col, StubCell::default());
                }
            }
        }
        'X' => {
            let col = g.cursor_col as usize;
            let n = csi_arg(params, 0, 1) as usize;
            let line = current_line(g);
            for cell in line.iter_mut().skip(col).take(n) {
                *cell = StubCell::default();
            }
        }
        'h' | 'l' if params == "?2004" => g.bracketed_paste = fin == 'h',
        _ => {}
    }
}

/// Consume ESC sequence starting at `i` (which is ESC). Returns the next
/// index, or `None` when the sequence is cut off.
fn consume_escape(g: &mut Inner, chars: &[char], i: usize) -> Option<usize> {
    if i + 1 >= chars.len() {
        return None;
    }
    match chars[i + 1] {
        '[' => consume_csi_from(g, chars, i + 2),
        ']' => {
            // OSC: ESC ] … BEL or ST (ESC \)
            let mut j = i + 2;
            while j < chars.len() {
                if chars[j] == '\u{07}' {
                    return Some(j + 1);
                }
                if chars[j] == '\u{1b}' {
                    if j + 1 >= chars.len() {
                        return None;
                    }
                    if chars[j + 1] == '\\' {
                        return Some(j + 2);
                    }
                }
                j += 1;
            }
            None
        }
        // Character set designate: ESC ( B etc. Skip one more.
        '(' | ')' | '*' | '+' => (i + 2 < chars.len()).then_some(i + 3),
        _ => Some(i + 2),
    }
}

fn apply_sgr(g: &mut Inner, params: &str) {
    if params.is_empty() {
        g.pen = Pen::default();
        return;
    }
    for part in params.split(';') {
        let code = part.parse::<u32>().unwrap_or(0);
        match code {
            0 => g.pen = Pen::default(),
            1 => g.pen.bold = true,
            22 => g.pen.bold = false,
            30..=37 => g.pen.fg = ansi_basic(code - 30, false),
            90..=97 => g.pen.fg = ansi_basic(code - 90, true),
            39 => g.pen.fg = FG,
            40..=47 => g.pen.bg = ansi_basic(code - 40, false),
            100..=107 => g.pen.bg = ansi_basic(code - 100, true),
            49 => g.pen.bg = BG,
            _ => {}
        }
    }
}

fn ansi_basic(index: u32, bright: bool) -> u32 {
    // xterm-ish 16-color map.
    let base: [(u8, u8, u8); 8] = [
        (0x00, 0x00, 0x00),
        (0xcd, 0x00, 0x00),
        (0x00, 0xcd, 0x00),
        (0xcd, 0xcd, 0x00),
        (0x00, 0x00, 0xee),
        (0xcd, 0x00, 0xcd),
        (0x00, 0xcd, 0xcd),
        (0xe5, 0xe5, 0xe5),
    ];
    let bright_map: [(u8, u8, u8); 8] = [
        (0x7f, 0x7f, 0x7f),
        (0xff, 0x00, 0x00),
        (0x00, 0xff, 0x00),
        (0xff, 0xff, 0x00),
        (0x5c, 0x5c, 0xff),
        (0xff, 0x00, 0xff),
        (0x00, 0xff, 0xff),
        (0xff, 0xff, 0xff),
    ];
    let i = (index as usize).min(7);
    let (r, g, b) = if bright { bright_map[i] } else { base[i] };
    pack_rgb(r, g, b)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn feed_strips_sgr_from_cells() {
        let eng = VtEngine::new(80, 24);
        eng.feed(b"\x1b[32mWawona\x1b[39m zsh\r\n");
        let mut cells = vec![WwnTermCell::default(); 80 * 24];
        let (n, cols, _rows) = eng.write_viewport(0, &mut cells);
        assert!(n > 0 && cols == 80);
        let text: String = cells[..80]
            .iter()
            .map(|c| char::from_u32(c.cp).unwrap_or(' '))
            .collect::<String>()
            .trim_end()
            .to_string();
        assert!(text.starts_with("Wawona zsh"), "got {text:?}");
        assert!(!text.contains("[32m") && !text.contains("[39m"));
        let json = eng.lines_json();
        assert!(json.contains("\"spans\""));
        assert!(!json.contains("[32m"));
    }

    fn row_text(eng: &VtEngine, row: usize) -> String {
        let mut cells = vec![WwnTermCell::default(); 80 * 24];
        let _ = eng.write_viewport(0, &mut cells);
        cells[row * 80..(row + 1) * 80]
            .iter()
            .map(|c| char::from_u32(c.cp).unwrap_or(' '))
            .collect::<String>()
            .trim_end()
            .to_string()
    }

    #[test]
    fn cursor_back_overwrites_zle_echo() {
        let eng = VtEngine::new(80, 24);
        eng.feed(b"~ % e\x1b[Decho hi");
        assert_eq!(row_text(&eng, 0), "~ % echo hi");
    }

    #[test]
    fn escape_split_across_feeds() {
        let eng = VtEngine::new(80, 24);
        eng.feed(b"run1\r\n\x1b[24");
        eng.feed(b"m\x1b[J~ % ");
        assert_eq!(row_text(&eng, 1), "~ %");
        eng.feed(&"\u{e9}".as_bytes()[..1]);
        eng.feed(&"\u{e9}".as_bytes()[1..]);
        assert_eq!(row_text(&eng, 1), "~ % \u{e9}");
    }

    #[test]
    fn paste_brackets_after_decset_2004() {
        let eng = VtEngine::new(80, 24);
        assert_eq!(eng.encode_paste("ls"), b"ls");
        eng.feed(b"\x1b[?2004h");
        assert_eq!(eng.encode_paste("ls"), b"\x1b[200~ls\x1b[201~");
        eng.feed(b"\x1b[?2004l");
        assert_eq!(eng.encode_paste("ls"), b"ls");
    }

    #[test]
    fn feed_strips_orphan_csi_without_esc() {
        // Fake-PTY / filter paths sometimes drop 0x1b and leave `[32m…`.
        let eng = VtEngine::new(80, 24);
        eng.feed(b"[32mWawona[39m zsh\r\n");
        let mut cells = vec![WwnTermCell::default(); 80 * 24];
        let _ = eng.write_viewport(0, &mut cells);
        let text: String = cells[..80]
            .iter()
            .map(|c| char::from_u32(c.cp).unwrap_or(' '))
            .collect::<String>()
            .trim_end()
            .to_string();
        assert!(text.starts_with("Wawona zsh"), "got {text:?}");
        assert!(!text.contains("[32m"));
    }
}
