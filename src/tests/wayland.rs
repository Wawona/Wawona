use crate::core::state::CompositorState;

#[test]
fn test_compositor_state_init() {
    let state = CompositorState::new(None);
    assert!(state.surfaces.is_empty());
    assert!(state.windows.is_empty());
    assert!(state.seat.keyboard.resources.is_empty());
    assert!(state.seat.pointer.resources.is_empty());
}

#[test]
fn test_seat_defaults() {
    let state = CompositorState::new(None);
    assert_eq!(state.seat.name, "seat0");
    assert!(state.seat.keyboard.focus.is_none());
    assert!(state.seat.pointer.focus.is_none());
    assert_eq!(state.seat.pointer.last_enter_serial, 0);
    assert_eq!(state.seat.pointer.last_button_serial, 0);
}

#[test]
fn test_id_generation() {
    let mut state = CompositorState::new(None);
    let id1 = state.next_surface_id();
    let id2 = state.next_surface_id();
    assert_eq!(id1 + 1, id2);
}

#[test]
fn test_default_output_exists() {
    let state = CompositorState::new(None);
    assert!(!state.outputs.is_empty(), "CompositorState must have at least one output for wl_output global registration");
    let primary = &state.outputs[state.primary_output];
    assert!(primary.width > 0);
    assert!(primary.height > 0);
}

#[test]
fn test_presentation_feedback_send_on_empty_is_noop() {
    use wayland_server::Display;

    let display = Display::<CompositorState>::new().unwrap();
    let _handle = display.handle();
    let mut state = CompositorState::new(None);

    // Presentation feedback fires only at the present boundary
    // (notify_frame_presented → send_presented_events). With no queued
    // feedbacks, delivery must be a no-op.
    assert!(state.ext.presentation.feedbacks.is_empty());
    let seq = state.next_presentation_seq();
    state
        .ext
        .presentation
        .send_presented_events(0, 16_666_666, seq);
    assert!(state.ext.presentation.feedbacks.is_empty());
}

#[test]
fn test_presentation_mark_committed() {
    use crate::core::wayland::ext::presentation_time::PresentationState;

    let mut pstate = PresentationState::default();
    assert!(pstate.feedbacks.is_empty());
    // mark_committed on empty list should not panic
    pstate.mark_committed(42);
}
