//! Common imports and types used throughout Wawona.

pub use std::collections::HashMap;
pub use std::sync::{Arc, RwLock};

// Add common internal types here
pub type Result<T> = std::result::Result<T, crate::core::errors::CoreError>;
