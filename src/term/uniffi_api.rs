//! UniFFI host API for Wawona Terminal.
//!
//! Same records as the Terminal crate (`TerminalSession`, `TerminalLine`,
//! `TerminalSpan`). SwiftUI, Compose, and GTK draw those records. The VT
//! screen stays in `screen.rs`.

use std::sync::{Arc, Mutex};

use super::screen::{recommended_scroll_cap, StyledLine, Term};

/// Live RAM/CPU scrollback recommendation (same probe as `Term::new`).
#[uniffi::export]
pub fn terminal_recommended_scrollback_cap(cols: u32) -> u32 {
    recommended_scroll_cap(cols as usize) as u32
}

#[derive(uniffi::Record)]
pub struct TerminalSpan {
    pub text: String,
    pub fg: u32,
    pub bg: u32,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
    pub blink: bool,
    pub strike: bool,
}

#[derive(uniffi::Record)]
pub struct TerminalLine {
    pub spans: Vec<TerminalSpan>,
}

#[derive(uniffi::Record)]
pub struct TerminalImage {
    pub id: u32,
    pub column: i32,
    pub row: i32,
    pub x_px: i32,
    pub y_px: i32,
    pub pixel_width: u32,
    pub pixel_height: u32,
    pub columns: u32,
    pub rows: u32,
    pub z: i32,
    pub rgba: Vec<u8>,
}

#[derive(uniffi::Object)]
pub struct TerminalSession {
    inner: Mutex<Term>,
}

#[uniffi::export]
impl TerminalSession {
    #[uniffi::constructor]
    pub fn new(cols: u32, rows: u32) -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(Term::new(cols as usize, rows as usize)),
        })
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        if let Ok(mut term) = self.inner.lock() {
            term.resize(cols as usize, rows as usize);
            // Columns change bytes-per-row; re-probe available RAM/CPU.
            term.refresh_scroll_cap(1.0);
        }
    }

    pub fn set_scrollback_cap(&self, rows: u32) {
        if let Ok(mut term) = self.inner.lock() {
            term.set_scroll_cap(rows as usize);
        }
    }

    pub fn scrollback_cap(&self) -> u32 {
        self.inner
            .lock()
            .map(|term| term.scroll_cap() as u32)
            .unwrap_or(0)
    }

    /// Re-probe RAM/CPU. `host_factor` in 0.25…1.0 for Low Power / thermal.
    pub fn refresh_scrollback_cap(&self, host_factor: f32) {
        if let Ok(mut term) = self.inner.lock() {
            term.refresh_scroll_cap(host_factor);
        }
    }

    pub fn feed(&self, bytes: Vec<u8>) {
        if let Ok(mut term) = self.inner.lock() {
            term.feed(&bytes);
        }
    }

    pub fn take_reply(&self) -> Vec<u8> {
        self.inner
            .lock()
            .map(|mut term| term.drain_reply())
            .unwrap_or_default()
    }

    pub fn lines(&self) -> Vec<TerminalLine> {
        let Ok(term) = self.inner.lock() else {
            return Vec::new();
        };
        term.styled_lines().into_iter().map(uniffi_line).collect()
    }

    /// Same document as [`Self::lines`], for a host that has not compiled the
    /// generated module yet.
    pub fn lines_json(&self) -> String {
        self.inner
            .lock()
            .map(|term| term.lines_json())
            .unwrap_or_else(|_| "[]".to_string())
    }

    pub fn encode_paste(&self, text: String) -> Vec<u8> {
        self.inner
            .lock()
            .map(|term| term.encode_paste(&text))
            .unwrap_or_else(|_| text.into_bytes())
    }

    pub fn pointer(&self, button: u8, col: u32, row: u32, pressed: bool, motion: bool) {
        if let Ok(mut term) = self.inner.lock() {
            term.pointer(button, col, row, pressed, motion);
        }
    }

    pub fn title(&self) -> String {
        self.inner
            .lock()
            .map(|term| term.title().to_string())
            .unwrap_or_default()
    }

    pub fn set_cell_px(&self, width: u32, height: u32) {
        if let Ok(mut term) = self.inner.lock() {
            term.set_cell_px(width, height);
        }
    }

    pub fn images(&self) -> Vec<TerminalImage> {
        let Ok(term) = self.inner.lock() else {
            return Vec::new();
        };
        term.placed_images()
            .into_iter()
            .map(|image| TerminalImage {
                id: image.id,
                column: image.col,
                row: image.row,
                x_px: image.x_px,
                y_px: image.y_px,
                pixel_width: image.px_w,
                pixel_height: image.px_h,
                columns: image.cols,
                rows: image.rows,
                z: image.z,
                rgba: image.rgba,
            })
            .collect()
    }
}

fn uniffi_line(line: StyledLine) -> TerminalLine {
    TerminalLine {
        spans: line
            .spans
            .into_iter()
            .map(|span| TerminalSpan {
                text: span.text,
                fg: span.fg,
                bg: span.bg,
                bold: span.bold,
                italic: span.italic,
                underline: span.underline,
                blink: span.blink,
                strike: span.strike,
            })
            .collect(),
    }
}

/// Host pressure as permille (1000 = 1.0). Swift calls this on Low Power and thermal.
#[no_mangle]
pub extern "C" fn wwn_term_refresh_scrollback_cap(term: *mut Term, host_factor_permille: u32) {
    if term.is_null() {
        return;
    }
    let factor = (host_factor_permille as f32) / 1000.0;
    unsafe { (*term).refresh_scroll_cap(factor) }
}

#[no_mangle]
pub extern "C" fn wwn_term_scrollback_cap(term: *const Term) -> u32 {
    if term.is_null() {
        return 0;
    }
    unsafe { (*term).scroll_cap() as u32 }
}

#[no_mangle]
pub extern "C" fn wwn_term_recommended_scrollback_cap(cols: u32) -> u32 {
    recommended_scroll_cap(cols as usize) as u32
}
