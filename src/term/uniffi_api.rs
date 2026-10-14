//! UniFFI host API for Wawona Terminal.
//!
//! Same records as the Terminal crate (`TerminalSession`, `TerminalLine`,
//! `TerminalSpan`). SwiftUI, Compose, and GTK draw those records. The VT
//! screen stays in `screen.rs`.

use std::sync::{Arc, Mutex};

use super::screen::{StyledLine, Term};

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
