use crate::core::window::{DecorationMode, Window};

#[test]
fn test_window_creation() {
    let window = Window::new(1, 100);
    assert_eq!(window.id, 1);
    assert_eq!(window.surface_id, 100);
    assert_eq!(window.width, 800);
    assert_eq!(window.height, 600);
    assert_eq!(window.decoration_mode, DecorationMode::ClientSide);
    assert!(!window.maximized);
    assert!(!window.fullscreen);
}

#[test]
fn test_window_geometry() {
    let mut window = Window::new(1, 100);
    window.width = 1024;
    window.height = 768;
    let geo = window.geometry();
    assert_eq!(geo.width, 1024);
    assert_eq!(geo.height, 768);
    assert_eq!(geo.x, 0);
    assert_eq!(geo.y, 0);
}

#[test]
fn test_window_state_flags() {
    let mut window = Window::new(1, 100);
    window.maximized = true;
    window.fullscreen = true;
    assert!(window.maximized);
    assert!(window.fullscreen);
}
