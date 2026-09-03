//! Platform Integration Module
//!
//! Wawona uses a **Rust backend + Native frontend** architecture.
//! Native frontends (macOS, iOS, Android) call into Rust via FFI.

pub mod api;
#[cfg(feature = "profile-ios-mode-b")]
pub mod ios_modeb;

pub use api::Platform;
