//! Deprecated JSON mirror. Source of truth is `crate::domain::machine_profile`.
//!
//! Do not add fields here. Linux GTK keeps this path so existing
//! `crate::linux::machine_profile` imports compile. Schema changes go through
//! rust UniFFI / `src/domain`.

pub use crate::domain::machine_profile::*;
