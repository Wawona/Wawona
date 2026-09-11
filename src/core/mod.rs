pub mod errors;
pub mod state;
pub mod traits;

pub mod compositor;
pub mod input;
pub mod ipc;
pub mod render;
pub mod runtime;
pub mod socket_manager;
pub mod surface;
pub mod time;
pub mod wayland;
pub mod weston_ini;
pub mod window;

// Re-export key types
pub use compositor::{Compositor, CompositorConfig, CompositorEvent};
pub use runtime::{FrameTiming, FrameTimingConfig, Runtime};
pub use state::CompositorState;
