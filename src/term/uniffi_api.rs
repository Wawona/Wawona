//! UniFFI host API for Wawona Terminal.
//!
//! Same records as the Terminal crate (`TerminalSession`, `TerminalLine`,
//! `TerminalSpan`). SwiftUI, Compose, and GTK draw those records. VT is
//! [`super::engine::VtEngine`] (libghostty-vt or mobile stub).

use std::sync::Arc;

use super::engine::{recommended_scroll_cap, StyledLine, VtEngine};

/// Live RAM/CPU scrollback recommendation (same probe as `VtEngine::new`).
#[uniffi::export]
pub fn terminal_recommended_scrollback_cap(cols: u32) -> u32 {
    u32::try_from(recommended_scroll_cap(cols)).unwrap_or(u32::MAX)
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
    inner: VtEngine,
}

#[uniffi::export]
impl TerminalSession {
    #[uniffi::constructor]
    pub fn new(cols: u32, rows: u32) -> Arc<Self> {
        Arc::new(Self {
            inner: VtEngine::new(cols, rows),
        })
    }

    pub fn resize(&self, cols: u32, rows: u32) {
        self.inner.resize(cols, rows);
        self.inner.set_scroll_cap(recommended_scroll_cap(cols));
    }

    pub fn set_scrollback_cap(&self, rows: u32) {
        self.inner.set_scroll_cap(rows as usize);
    }

    pub fn scrollback_cap(&self) -> u32 {
        u32::try_from(self.inner.scroll_cap()).unwrap_or(u32::MAX)
    }

    /// Re-probe RAM/CPU. `host_factor` in 0.25…1.0 for Low Power / thermal.
    pub fn refresh_scrollback_cap(&self, host_factor: f32) {
        let factor = host_factor.clamp(0.25, 1.0);
        let cols = self.inner.cols();
        let base = recommended_scroll_cap(cols);
        let capped = ((base as f32) * factor).round() as usize;
        self.inner.set_scroll_cap(capped.clamp(1_000, 100_000));
    }

    pub fn feed(&self, bytes: Vec<u8>) {
        self.inner.feed(&bytes);
    }

    pub fn take_reply(&self) -> Vec<u8> {
        self.inner.take_reply()
    }

    pub fn lines(&self) -> Vec<TerminalLine> {
        self.inner
            .styled_lines()
            .into_iter()
            .map(uniffi_line)
            .collect()
    }

    /// Same document as [`Self::lines`], for a host that has not compiled the
    /// generated module yet.
    pub fn lines_json(&self) -> String {
        self.inner.lines_json()
    }

    pub fn encode_paste(&self, text: String) -> Vec<u8> {
        self.inner.encode_paste(&text)
    }

    pub fn pointer(&self, button: u8, col: u32, row: u32, pressed: bool, motion: bool) {
        self.inner.pointer(button, col, row, pressed, motion);
    }

    pub fn title(&self) -> String {
        self.inner.title()
    }

    pub fn set_cell_px(&self, width: u32, height: u32) {
        self.inner.set_cell_px(width, height);
    }

    pub fn images(&self) -> Vec<TerminalImage> {
        self.inner
            .placed_images()
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
