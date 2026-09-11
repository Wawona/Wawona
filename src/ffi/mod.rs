//! FFI module - Stable API boundary for platform integration
//!
//! This module provides a UniFFI-based API that platforms (macOS, iOS, Android)
//! use to interact with the Wawona compositor core.

pub mod api;
pub mod callbacks;
pub mod errors;
pub mod types;

// Re-export for convenience
pub use api::*;

pub use callbacks::*;
pub mod c_api;
pub mod ssh;
