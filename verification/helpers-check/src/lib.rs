#[path = "../../../src/core/generation_counter.rs"]
mod generation_counter;

#[path = "../../../src/core/invariants.rs"]
pub mod invariants;

#[path = "../../../src/domain/sanitize_ssh_host.rs"]
pub mod sanitize_ssh_host;

/// Wayland protocol erroneous-check helpers + Kani harnesses.
#[path = "../../../src/core/wayland/protocol_proofs.rs"]
pub mod protocol_proofs;
