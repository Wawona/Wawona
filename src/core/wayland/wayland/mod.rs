pub mod display;
pub mod registry;
pub mod compositor;
pub mod seat;
pub mod output;

use wayland_server::DisplayHandle;
use crate::core::state::CompositorState;

/// Register core Wayland protocols
/// Phase D: Creates one wl_output global per output in state for multi-output support.
pub fn register(_state: &mut CompositorState, _dh: &DisplayHandle) {
}
