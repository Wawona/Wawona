//! In-process Terminal VT (libghostty-vt via Terminal `engine.rs`).
//!
//! Materialized from flake input `terminal`: `cell.rs`, `engine.rs`,
//! `ffi_surface.rs`. Homemade `screen.rs` / `kitty.rs` are gone.
//!
//! Feature `libghostty-term` (Nix: `nix-ghostty-vt`) compiles the real
//! engine. Without it (Apple-mobile / Android crate2nix until VT cross
//! exists), [`engine_stub`] keeps UniFFI + C ABI linkable. Tip macOS may
//! still overlay `libwawona_terminal.a` until the macOS backend always
//! enables `nix-ghostty-vt`.

#[cfg(target_os = "android")]
mod android_shell;

mod cell;

#[cfg(feature = "libghostty-term")]
#[path = "engine.rs"]
mod engine;

#[cfg(not(feature = "libghostty-term"))]
#[path = "engine_stub.rs"]
mod engine;

mod ffi_surface;
mod uniffi_api;

pub use cell::WwnTermCell;
pub use engine::{
    recommended_scroll_cap, PlacedImage, StyledLine, StyledSpan, VtEngine,
};
pub use uniffi_api::{TerminalImage, TerminalLine, TerminalSession, TerminalSpan};
