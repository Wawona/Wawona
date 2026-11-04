//! In-process Terminal VT (libghostty-vt via Terminal `engine.rs`).
//!
//! Materialized from flake input `terminal`: `cell.rs`, `engine.rs`,
//! `ffi_surface.rs`. Homemade `screen.rs` / `kitty.rs` are gone.
//!
//! Feature `libghostty-term` (Nix: `nix-ghostty-vt`) compiles the real
//! engine. macOS/Linux product backends pass flake `ghostty` `libghostty-vt`
//! and enable that feature. Without it (Apple-mobile / Android until VT
//! cross exists), [`engine_stub`] keeps UniFFI + C ABI linkable. Tip overlay
//! of `libwawona_terminal.a` is fallback only when the stub is still linked.

#[cfg(target_os = "android")]
mod android_shell;

mod cell;

#[cfg(feature = "libghostty-term")]
mod key_input;

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
