// Wawona Compositor
// Copyright (c) 2026
//
// Rust-first, cross-platform Wayland compositor
// All shared logic lives in Rust core/, platform adapters handle
// native rendering (Metal on macOS/iOS, GPU backend on Android)

pub mod core;
pub mod platform;
pub mod ffi;
pub mod config;
pub mod util;
pub mod prelude;
pub mod version;
#[cfg(feature = "linux-ui")]
pub mod linux;

// Re-export FFI types at crate root for UniFFI
// UniFFI's generated code expects these types to be accessible from the crate root
pub use ffi::types::*;
pub use ffi::errors::*;
pub use ffi::api::{WawonaCore, version, build_info};

// When the waypipe feature is enabled (iOS/Android), force the linker to
// include waypipe's objects in the staticlib so waypipe_main is available
// to the native app layer. Without this extern crate, rustc strips the
// unreferenced dependency from the archive.
#[cfg(feature = "waypipe")]
extern crate waypipe;

// Generate UniFFI scaffolding
// This must be in lib.rs for the generated code to work correctly
uniffi::include_scaffolding!("wawona");

#[cfg(test)]
mod tests;
