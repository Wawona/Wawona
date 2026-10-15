//! In-process link of the Terminal crate screen.
//! Canonical source: github.com/Wawona/Terminal `src/screen.rs`.
//! `screen.rs` in this directory is a symlink. Nix replaces it from the
//! `terminal` flake input in workspace-src. Do not grow a second parser here.
//!
//! Hosts draw [`TerminalSession`] lines. The C exports feed the in-process PTY.

#[cfg(target_os = "android")]
mod android_shell;

mod uniffi_api;

#[path = "screen.rs"]
mod screen;

pub use screen::*;
pub use uniffi_api::{TerminalImage, TerminalLine, TerminalSession, TerminalSpan};
