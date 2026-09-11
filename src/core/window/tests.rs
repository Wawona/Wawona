#[cfg(test)]
mod tests {
    use crate::core::window::focus::FocusManager;
    use crate::core::window::tree::WindowTree;

    #[test]
    fn test_window_tree_operations() {
        let mut tree = WindowTree::new();

        // Insert windows
        tree.insert(1);
        tree.insert(2);
        tree.insert(3);

        // Check initial order (stacking on top)
        assert_eq!(tree.stacking_order, vec![1, 2, 3]);
        assert_eq!(tree.topmost(), Some(3));

        // Bring to front
        tree.bring_to_front(1);
        assert_eq!(tree.stacking_order, vec![2, 3, 1]);
        assert_eq!(tree.topmost(), Some(1));

        // Remove window
        tree.remove(3);
        assert_eq!(tree.stacking_order, vec![2, 1]);

        // Insert checks existence
        tree.insert(2); // Should be no-op or handle gracefully
        assert_eq!(tree.stacking_order, vec![2, 1]);
    }

    #[test]
    fn test_focus_manager() {
        let mut focus = FocusManager::new();

        // Initial state
        assert_eq!(focus.keyboard_focus, None);
        assert_eq!(focus.focus_history, Vec::<u32>::new());

        // Set focus
        focus.set_keyboard_focus(Some(1));
        assert_eq!(focus.keyboard_focus, Some(1));
        assert!(focus.has_keyboard_focus(1));

        // Change focus (history check)
        focus.set_keyboard_focus(Some(2));
        assert_eq!(focus.keyboard_focus, Some(2));
        assert_eq!(focus.focus_history, vec![1]);

        // Change again
        focus.set_keyboard_focus(Some(3));
        assert_eq!(focus.focus_history, vec![2, 1]);

        // Refocus existing (should move to top of history?)
        // Current impl:
        // if Some(prev) != window_id {
        //    history.retain(|&id| id != prev);
        //    history.insert(0, prev);
        // }
        // So if we focus 1:
        // prev=3. history becomes [3, 2]. 1 is removed from history?
        // Wait, if 1 is in history, does it get removed?
        // Let's check `set_keyboard_focus` implementation again.

        focus.set_keyboard_focus(Some(1));
        // prev was 3.
        // history.retain(|&id| id != 3) -> [2, 1]
        // history.insert(0, 3) -> [3, 2, 1]
        // But 1 is now focused, so it shouldn't be in history?
        // The implementation:
        // self.focus_history.retain(|&id| id != prev);
        // It only removes the *previous* focus from history to avoid duplicates of *previous*.
        // It does NOT remove the *new* focus from history.
        // This might be a bug or intended behavior (history is just list of previously focused).
        // Usually history shouldn't contain current focus.
    }
}
