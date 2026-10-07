//! Pure compositor checks. Kani, Verus, proptest, and Loom point here.
//! Product code calls these functions. There is no second implementation.

pub use super::generation_counter::GenerationCounter;

/// Clamp a damage rectangle into `0..max_width` x `0..max_height`.
///
/// Width and height are the span from the original origin, matching
/// `DamageRegion::clamp`. Adds saturate so a hostile span cannot wrap.
pub fn clamp_rect(
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    max_width: i32,
    max_height: i32,
) -> (i32, i32, i32, i32) {
    let cx = x.max(0).min(max_width.max(0));
    let cy = y.max(0).min(max_height.max(0));
    let right = x.saturating_add(width).min(max_width);
    let bottom = y.saturating_add(height).min(max_height);
    let w = right.saturating_sub(cx).max(0);
    let h = bottom.saturating_sub(cy).max(0);
    (cx, cy, w, h)
}

#[cfg(kani)]
mod kani_proofs {
    use super::clamp_rect;

    #[kani::proof]
    fn clamped_rect_stays_inside_nonnegative_bounds() {
        let x: i32 = kani::any();
        let y: i32 = kani::any();
        let width: i32 = kani::any();
        let height: i32 = kani::any();
        let max_width: i32 = kani::any();
        let max_height: i32 = kani::any();
        kani::assume(max_width >= 0 && max_height >= 0);
        kani::assume(width >= 0 && height >= 0);
        let (cx, cy, w, h) = clamp_rect(x, y, width, height, max_width, max_height);
        assert!(cx >= 0 && cy >= 0);
        assert!(w >= 0 && h >= 0);
        assert!(cx <= max_width && cy <= max_height);
        if w > 0 {
            assert!(cx.saturating_add(w) <= max_width);
        }
        if h > 0 {
            assert!(cy.saturating_add(h) <= max_height);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_matches_damage_examples() {
        assert_eq!(clamp_rect(-4, -2, 10, 8, 6, 5), (0, 0, 6, 5));
        assert_eq!(clamp_rect(2, 2, 2, 2, 10, 10), (2, 2, 2, 2));
        assert_eq!(clamp_rect(8, 1, 4, 2, 10, 10), (8, 1, 2, 2));
    }

    #[test]
    fn bump_is_monotonic_on_one_thread() {
        let counter = GenerationCounter::new();
        assert_eq!(counter.bump(), 0);
        assert_eq!(counter.bump(), 1);
        assert_eq!(counter.load(), 2);
    }
}

#[cfg(all(test, not(loom)))]
mod proptests {
    use super::clamp_rect;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn clamp_stays_in_box(x in -1000i32..1000, y in -1000i32..1000, w in 0i32..500, h in 0i32..500, mw in 0i32..800, mh in 0i32..800) {
            let (cx, cy, cw, ch) = clamp_rect(x, y, w, h, mw, mh);
            prop_assert!(cx >= 0 && cy >= 0);
            prop_assert!(cw >= 0 && ch >= 0);
            prop_assert!(cx <= mw && cy <= mh);
            if cw > 0 {
                prop_assert!(cx.saturating_add(cw) <= mw);
            }
            if ch > 0 {
                prop_assert!(cy.saturating_add(ch) <= mh);
            }
        }
    }
}

