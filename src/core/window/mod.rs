pub mod window;
pub mod tree;
pub mod focus;
pub mod resize;
pub mod size_authority;
pub mod placement;
pub mod fullscreen;
mod tests;

pub use placement::{apply_placement, PlacementPolicy};
pub use size_authority::{ClientCommitDecision, HostRequestDecision, SizeAuthority};
pub use window::{Window, DecorationMode};
