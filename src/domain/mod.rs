//! Cross-platform product domain.
//!
//! This module owns Wawona's models, defaults, validation, policy, durable
//! state, and session orchestration. Native frontends consume JSON snapshots
//! and submit typed intents through the hand-written C ABI.

#[path = "../linux/machine_profile.rs"]
pub mod machine_profile;
pub mod preferences;
pub mod state;

pub use machine_profile::*;
pub use preferences::*;
pub use state::*;
