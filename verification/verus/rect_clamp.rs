// Host-side Verus model of clamp_rect. Not linked into the app.
// Run: scripts/verify-verus.sh
use vstd::prelude::*;

verus! {

pub open spec fn spec_clamp_rect(x: int, y: int, width: int, height: int, max_width: int, max_height: int) -> (int, int, int, int) {
    let cx = if x > 0 { x } else { 0 };
    let cy = if y > 0 { y } else { 0 };
    let right0 = x + width;
    let bottom0 = y + height;
    let right = if right0 < max_width { right0 } else { max_width };
    let bottom = if bottom0 < max_height { bottom0 } else { max_height };
    let w0 = right - cx;
    let h0 = bottom - cy;
    let w = if w0 > 0 { w0 } else { 0 };
    let h = if h0 > 0 { h0 } else { 0 };
    (cx, cy, w, h)
}

proof fn clamp_nonnegative_box(x: int, y: int, width: int, height: int, max_width: int, max_height: int)
    requires
        max_width >= 0,
        max_height >= 0,
        width >= 0,
        height >= 0,
    ensures
        ({
            let (cx, cy, w, h) = spec_clamp_rect(x, y, width, height, max_width, max_height);
            cx >= 0 && cy >= 0 && w >= 0 && h >= 0 && cx <= max_width && cy <= max_height
        }),
{
}

} // verus!
