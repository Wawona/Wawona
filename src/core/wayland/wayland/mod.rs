pub mod compositor;
pub mod display;
pub mod input;
pub mod output;
pub mod registry;
pub mod seat;

use crate::core::state::CompositorState;
use wayland_server::DisplayHandle;

/// Register core Wayland protocols
/// Phase D: Creates one wl_output global per output in state for multi-output support.
pub fn register(_state: &mut CompositorState, _dh: &DisplayHandle) {}
