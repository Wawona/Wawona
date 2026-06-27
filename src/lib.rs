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

// iland Mode B (bare-metal WindowServer replacement) gate. It is macOS-only,
// opt-in, and not App-Store-safe; it must never be compiled for mobile Apple
// targets or without a desktop runtime profile. See the `iland-baremetal`
// feature in Cargo.toml.
#[cfg(all(
    feature = "iland-baremetal",
    any(target_os = "ios", target_os = "tvos", target_os = "watchos", target_os = "visionos", target_os = "android")
))]
compile_error!(
    "feature `iland-baremetal` (iland Mode B) is macOS-only and cannot be built \
     for mobile/Android targets; it requires SIP off + root and is not \
     App-Store-safe. Use iland Mode A (default) on these platforms."
);

#[cfg(all(
    feature = "iland-baremetal",
    not(any(feature = "profile-desktop-host", feature = "profile-full-dev"))
))]
compile_error!(
    "feature `iland-baremetal` (iland Mode B) requires `profile-desktop-host` \
     or `profile-full-dev`; it is not permitted in store-safe profiles."
);

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
