// Wawona Compositor
// Copyright (c) 2026
//
// Rust-first, cross-platform Wayland compositor
// All shared logic lives in Rust core/, platform adapters handle
// native rendering (Metal on macOS/iOS, GPU backend on Android)

pub mod config;
pub mod core;
pub mod domain;
pub mod ffi;
pub mod platform;
pub mod prelude;
pub mod util;
pub mod version;
// Linux GTK + file store. Domain types live in `domain` (always compiled).
// This module stays `linux-ui` / `test` only so Apple/Android release builds
// do not pull GTK helpers.
#[cfg(any(feature = "linux-ui", test))]
pub mod linux;

// iland Mode B (bare-metal WindowServer replacement) gate. It is macOS-only,
// opt-in, and not App-Store-safe; it must never be compiled for mobile Apple
// targets or without a desktop runtime profile. See the `iland-baremetal`
// feature in Cargo.toml.
#[cfg(all(
    feature = "iland-baremetal",
    any(
        target_os = "ios",
        target_os = "tvos",
        target_os = "watchos",
        target_os = "visionos",
        target_os = "android"
    )
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

#[cfg(all(feature = "profile-ios-mode-b", not(target_os = "ios")))]
compile_error!("feature `profile-ios-mode-b` is restricted to iOS/iPadOS targets");

#[cfg(all(
    feature = "profile-ios-mode-b",
    any(feature = "profile-store-safe", feature = "profile-store-safe-remote")
))]
compile_error!("feature `profile-ios-mode-b` cannot be combined with a store-safe profile");

// Re-export FFI types at crate root for UniFFI
// UniFFI's generated code expects these types to be accessible from the crate root
pub use ffi::api::{build_info, build_number, version, WawonaCore};
pub use ffi::errors::*;
pub use ffi::types::*;
pub use domain::error::DomainError;
pub use domain::machine_profile::{
    ClientLauncher, ContainerMachineSettings, DomainEnvironmentOverride, MachineProfile,
    MachineRuntimeOverrides, MachineStatus, MachineType,
};
pub use domain::uniffi_api::{
    machine_profiles_decode_v1, machine_profiles_encode_v1, normalize_ssh_port_uniffi,
    sanitize_ssh_host_uniffi, validate_machine_editor, validate_machine_profile,
    MachineProfileStoreApi,
};

// When the waypipe feature is enabled (iOS/Android), force the linker to
// include waypipe's objects in the staticlib so waypipe_main is available
// to the native app layer. Without this extern crate, rustc strips the
// unreferenced dependency from the archive.
#[cfg(feature = "waypipe")]
extern crate waypipe;

// Same rationale as waypipe: when the coreutils feature is enabled (mobile +
// macOS), force the linker to keep the uutils umbrella objects so the C entry
// point wawona_coreutils_main survives dead-strip and is reachable from the
// in-process dispatch shim in libwwn-pty.a.
#[cfg(feature = "coreutils")]
extern crate coreutils;

// Generate UniFFI scaffolding purely from the proc-macro metadata
// (#[uniffi::export] / #[derive(uniffi::…)]). The UDL is empty (namespace
// only), so no build-script scaffolding is needed. Using setup_scaffolding!
// instead of a build.rs + uniffi_build build-dependency keeps uniffi_bindgen
// in a single crate2nix dependency graph and avoids E0460 (see build.rs).
uniffi::setup_scaffolding!("wawona");

#[cfg(test)]
mod tests;
