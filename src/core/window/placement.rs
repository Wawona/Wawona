//! Compositor placement policy (position only — never buffer size).
//!
//! Sizing is negotiated via xdg-shell + [`super::size_authority`]. Placement
//! decides where a negotiated surface sits in the output/workspace.
//!
//! Default floating policy: **center** client-constrained surfaces
//! (weston-flower/smoke 200×200 on a large output/host).

use super::window::Window;

/// Placement policy for floating (non-tiled / non-fullscreen) surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PlacementPolicy {
    /// Center in the target output/workspace when smaller than the output.
    #[default]
    Center,
    /// Leave `window.x/y` unchanged (manual / user-dragged).
    Manual,
}

/// Center a floating window in the output when the client size is smaller
/// than the output. Does not change `width`/`height`.
///
/// Skips host-locked, maximized, and fullscreen windows. Surfaces that
/// already fill (or exceed) the output stay at the origin.
pub fn apply_placement(
    window: &mut Window,
    policy: PlacementPolicy,
    output_w: i32,
    output_h: i32,
) {
    if window.host_locked || window.maximized || window.fullscreen {
        return;
    }
    if window.width <= 0 || window.height <= 0 || output_w <= 0 || output_h <= 0 {
        return;
    }

    match policy {
        PlacementPolicy::Manual => {}
        PlacementPolicy::Center => {
            if window.width >= output_w && window.height >= output_h {
                window.x = 0;
                window.y = 0;
                return;
            }
            window.x = ((output_w - window.width) / 2).max(0);
            window.y = ((output_h - window.height) / 2).max(0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::window::Window;

    #[test]
    fn centers_fixed_size_client_on_large_output() {
        let mut w = Window::new(1, 1);
        w.width = 200;
        w.height = 200;
        apply_placement(&mut w, PlacementPolicy::Center, 1920, 1080);
        assert_eq!(w.x, (1920 - 200) / 2);
        assert_eq!(w.y, (1080 - 200) / 2);
        assert_eq!(w.width, 200);
        assert_eq!(w.height, 200);
    }

    #[test]
    fn skips_host_locked() {
        let mut w = Window::new(1, 1);
        w.width = 200;
        w.height = 200;
        w.host_locked = true;
        w.x = 12;
        w.y = 34;
        apply_placement(&mut w, PlacementPolicy::Center, 1920, 1080);
        assert_eq!((w.x, w.y), (12, 34));
    }

    #[test]
    fn fill_sized_stays_at_origin() {
        let mut w = Window::new(1, 1);
        w.width = 1920;
        w.height = 1080;
        apply_placement(&mut w, PlacementPolicy::Center, 1920, 1080);
        assert_eq!((w.x, w.y), (0, 0));
    }
}
