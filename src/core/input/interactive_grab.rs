//! Compositor-owned interactive move / resize (`xdg_toplevel.move` /
//! `xdg_toplevel.resize`) for hosts without a window system. Platform hosts
//! run these drags natively; a headless host has nobody else to do it.

/// Edges dragged by an interactive resize. Opposite edges are exclusive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct GrabEdges {
    pub left: bool,
    pub right: bool,
    pub top: bool,
    pub bottom: bool,
}

impl GrabEdges {
    /// From an `xdg_toplevel.resize_edge` value. Unknown values select no
    /// edge, which degrades the resize to a no-op.
    pub fn from_xdg(edge: u32) -> Self {
        // xdg_toplevel.resize_edge: top=1, bottom=2, left=4, right=8 bit layout.
        Self {
            top: edge & 1 != 0 && edge & 2 == 0,
            bottom: edge & 2 != 0 && edge & 1 == 0,
            left: edge & 4 != 0 && edge & 8 == 0,
            right: edge & 8 != 0 && edge & 4 == 0,
        }
    }
}

/// An interactive move (`edges == None`) or resize in progress.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InteractiveGrab {
    pub window_id: u32,
    pub start_pointer: (f64, f64),
    /// Window rect (x, y, width, height) when the grab started.
    pub start_rect: (i32, i32, i32, i32),
    pub edges: Option<GrabEdges>,
}

/// Largest pointer delta, in logical pixels, a grab applies on one axis.
const MAX_GRAB_DELTA: f64 = 1_000_000.0;

fn axis_delta(from: f64, to: f64) -> i32 {
    let delta = to - from;
    if !delta.is_finite() {
        return 0;
    }
    delta.round().clamp(-MAX_GRAB_DELTA, MAX_GRAB_DELTA) as i32
}

/// One axis of a resize: dragging the near edge moves the origin and keeps
/// the far edge fixed; size never drops below 1.
fn resize_axis(origin: i32, size: i32, delta: i32, near: bool, far: bool) -> (i32, i32) {
    if near {
        let new_size = size.saturating_sub(delta).max(1);
        (
            origin.saturating_add(size.saturating_sub(new_size)),
            new_size,
        )
    } else if far {
        (origin, size.saturating_add(delta).max(1))
    } else {
        (origin, size)
    }
}

/// Window rect for the grab with the pointer at `pointer`.
pub fn grab_rect(grab: &InteractiveGrab, pointer: (f64, f64)) -> (i32, i32, i32, i32) {
    let dx = axis_delta(grab.start_pointer.0, pointer.0);
    let dy = axis_delta(grab.start_pointer.1, pointer.1);
    let (x, y, w, h) = grab.start_rect;
    match grab.edges {
        None => (x.saturating_add(dx), y.saturating_add(dy), w, h),
        Some(edges) => {
            let (nx, nw) = resize_axis(x, w, dx, edges.left, edges.right);
            let (ny, nh) = resize_axis(y, h, dy, edges.top, edges.bottom);
            (nx, ny, nw, nh)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn grab(edges: Option<GrabEdges>) -> InteractiveGrab {
        InteractiveGrab {
            window_id: 1,
            start_pointer: (105.0, 105.0),
            start_rect: (100, 100, 420, 390),
            edges,
        }
    }

    #[test]
    fn move_follows_pointer_delta() {
        assert_eq!(grab_rect(&grab(None), (165.0, 65.0)), (160, 60, 420, 390));
    }

    #[test]
    fn top_left_resize_moves_origin_and_keeps_far_edge() {
        let g = grab(Some(GrabEdges::from_xdg(5)));
        assert_eq!(grab_rect(&g, (165.0, 65.0)), (160, 60, 360, 430));
    }

    #[test]
    fn bottom_right_resize_keeps_origin() {
        let g = grab(Some(GrabEdges::from_xdg(10)));
        assert_eq!(grab_rect(&g, (115.0, 125.0)), (100, 100, 430, 410));
    }

    #[test]
    fn resize_never_collapses_below_one_pixel() {
        let g = grab(Some(GrabEdges::from_xdg(5)));
        let (x, y, w, h) = grab_rect(&g, (10_000.0, 10_000.0));
        assert_eq!((w, h), (1, 1));
        assert_eq!((x + w, y + h), (520, 490), "far edge stays fixed");
        let g = grab(Some(GrabEdges::from_xdg(10)));
        assert_eq!(grab_rect(&g, (-10_000.0, -10_000.0)), (100, 100, 1, 1));
    }

    #[test]
    fn non_finite_pointer_does_not_move() {
        assert_eq!(
            grab_rect(&grab(None), (f64::NAN, f64::INFINITY)),
            (100, 100, 420, 390)
        );
    }

    #[test]
    fn huge_delta_saturates() {
        let g = InteractiveGrab {
            start_rect: (i32::MAX - 5, i32::MIN + 5, 10, 10),
            ..grab(None)
        };
        let (x, y, _, _) = grab_rect(&g, (1e300, -1e300));
        assert_eq!((x, y), (i32::MAX, i32::MIN));
    }

    #[test]
    fn contradictory_and_unknown_edges_select_nothing() {
        assert_eq!(GrabEdges::from_xdg(3), GrabEdges::default());
        assert_eq!(GrabEdges::from_xdg(12), GrabEdges::default());
        assert_eq!(GrabEdges::from_xdg(0), GrabEdges::default());
        assert_eq!(
            grab_rect(&grab(Some(GrabEdges::default())), (500.0, 500.0)),
            (100, 100, 420, 390)
        );
    }
}
