//! Keyboard eligibility for Wayland windows.
//!
//! Closing a window removes that id from the eligible set and clears keyboard
//! focus when the closed window held it. Selecting an id that is not eligible
//! is refused. Bend in `verification/bend/` checks the model of `without`,
//! `select`, and `clear`.

/// Ids that remain eligible after `closed` is destroyed.
pub fn eligible_after_close(ids: &[u32], closed: u32) -> Vec<u32> {
    ids.iter().copied().filter(|id| *id != closed).collect()
}

/// `Some(id)` when `id` is still eligible. A missing id is refused.
pub fn select_window(ids: &[u32], id: u32) -> Option<u32> {
    ids.contains(&id).then_some(id)
}

/// Drop keyboard or pointer focus when it names the closed window.
pub fn clear_closed_focus(focus: Option<u32>, closed: u32) -> Option<u32> {
    focus.filter(|id| *id != closed)
}

/// Keyboard focus after close.
///
/// The closed id is never the result. When it held focus, the first history
/// id that is still eligible becomes focus. Any other focus stays.
pub fn focus_after_close(
    focused: Option<u32>,
    history: &[u32],
    eligible: &[u32],
    closed: u32,
) -> Option<u32> {
    match focused {
        Some(id) if id == closed => history.iter().copied().find(|id| eligible.contains(id)),
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn close_removes_every_copy_and_select_refuses_it() {
        for closed in 0..5 {
            for a in 0..4 {
                for b in 0..4 {
                    for c in 0..4 {
                        let before = [a, b, c];
                        let after = eligible_after_close(&before, closed);
                        assert!(!after.contains(&closed));
                        assert_eq!(select_window(&after, closed), None);
                        for id in before {
                            if id != closed {
                                assert!(after.contains(&id));
                                assert_eq!(select_window(&after, id), Some(id));
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn close_clears_focus_and_keeps_another() {
        assert_eq!(clear_closed_focus(Some(7), 7), None);
        assert_eq!(clear_closed_focus(Some(4), 7), Some(4));
        assert_eq!(clear_closed_focus(None, 7), None);
    }

    #[test]
    fn focus_after_close_uses_history_only_for_the_closed_window() {
        let eligible = [2, 3];
        assert_eq!(focus_after_close(Some(1), &[9, 2, 1], &eligible, 1), Some(2));
        assert_eq!(focus_after_close(Some(3), &[1], &eligible, 1), Some(3));
        assert_eq!(focus_after_close(Some(1), &[1, 9], &eligible, 1), None);
    }
}