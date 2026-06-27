use std::sync::{Arc, RwLock};

use crate::core::state::CompositorState;
use crate::core::surface::Surface;
use crate::core::window::Window;

#[test]
fn test_scene_uses_window_tree_stacking_order() {
    let mut state = CompositorState::new(None);

    let w1 = Window::new(1, 11);
    let w2 = Window::new(2, 22);
    state.windows.insert(1, Arc::new(RwLock::new(w1)));
    state.windows.insert(2, Arc::new(RwLock::new(w2)));
    state.surface_to_window.insert(11, 1);
    state.surface_to_window.insert(22, 2);
    state.window_tree.stacking_order = vec![2, 1];

    state.build_scene();
    let flattened = state.scene.flatten();
    let surfaces: Vec<u32> = flattened.into_iter().map(|n| n.surface_id).collect();
    assert_eq!(surfaces, vec![22, 11]);
}

#[test]
fn test_scene_propagates_surface_scale() {
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(101, None, None);
    surface.current.width = 800;
    surface.current.height = 600;
    surface.current.scale = 2;
    state.surfaces.insert(101, Arc::new(RwLock::new(surface)));

    let window = Window::new(1, 101);
    state.windows.insert(1, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(101, 1);
    state.window_tree.stacking_order = vec![1];

    state.build_scene();
    let flattened = state.scene.flatten();
    let node = flattened
        .iter()
        .find(|n| n.surface_id == 101)
        .expect("surface not found in scene");
    assert_eq!(node.scale, 2.0);
}

#[test]
fn test_scene_keeps_fullscreen_shell_node_at_output_size() {
    let mut state = CompositorState::new(None);
    state.set_output_size(1280, 720, 1.0);

    let mut surface = Surface::new(201, None, None);
    surface.current.width = 640;
    surface.current.height = 360;
    surface.current.scale = 1;
    state.surfaces.insert(201, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(9, 201);
    window.width = 1280;
    window.height = 720;
    state.windows.insert(9, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(201, 9);
    state.ext.fullscreen_shell.presented_window_id = Some(9);
    state.window_tree.stacking_order = vec![9];

    state.build_scene();
    let flattened = state.scene.flatten();
    let node = flattened
        .iter()
        .find(|n| n.surface_id == 201)
        .expect("surface not found in scene");

    assert_eq!(node.width, 1280);
    assert_eq!(node.height, 720);
}

#[test]
fn test_output_resize_updates_fullscreen_shell_window_geometry() {
    let mut state = CompositorState::new(None);

    let window = Window::new(21, 501);
    state.windows.insert(21, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(501, 21);
    state.ext.fullscreen_shell.presented_window_id = Some(21);

    state.set_output_size(720, 1280, 1.0);

    let window_ref = state.get_window(21).expect("window missing");
    let window = window_ref.read().unwrap();
    assert_eq!(window.x, 0);
    assert_eq!(window.y, 0);
    assert_eq!(window.width, 720);
    assert_eq!(window.height, 1280);
}

#[test]
fn test_output_resize_updates_host_locked_window_geometry() {
    let mut state = CompositorState::new(None);

    let mut window = Window::new(31, 601);
    window.host_locked = true;
    state.windows.insert(31, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(601, 31);

    state.set_output_size(720, 1280, 1.0);

    let window_ref = state.get_window(31).expect("window missing");
    let window = window_ref.read().unwrap();
    assert_eq!(window.x, 0);
    assert_eq!(window.y, 0);
    assert_eq!(window.width, 720);
    assert_eq!(window.height, 1280);
}

#[test]
fn test_find_surface_at_scales_weston_style_buffer_without_set_buffer_scale() {
    let mut state = CompositorState::new(None);
    state.set_output_size(390, 844, 2.0);

    let mut surface = Surface::new(101, None, None);
    surface.current.width = 780;
    surface.current.height = 1688;
    surface.current.scale = 1;
    state.surfaces.insert(101, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(1, 101);
    window.width = 390;
    window.height = 844;
    state.windows.insert(1, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(101, 1);
    state.window_tree.stacking_order = vec![1];

    let (sid, lx, ly) = state
        .find_surface_at(195.0, 422.0)
        .expect("center hit");
    assert_eq!(sid, 101);
    assert!((lx - 390.0).abs() < 0.01, "lx={lx}");
    assert!((ly - 844.0).abs() < 0.01, "ly={ly}");
}

#[test]
fn test_find_surface_at_scales_with_wl_surface_buffer_scale() {
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(102, None, None);
    surface.current.width = 800;
    surface.current.height = 600;
    surface.current.scale = 2;
    state.surfaces.insert(102, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(2, 102);
    window.width = 400;
    window.height = 300;
    state.windows.insert(2, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(102, 2);
    state.window_tree.stacking_order = vec![2];

    let (_, lx, ly) = state
        .find_surface_at(200.0, 150.0)
        .expect("center hit");
    assert!((lx - 400.0).abs() < 0.01, "lx={lx}");
    assert!((ly - 300.0).abs() < 0.01, "ly={ly}");
}
