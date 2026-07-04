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
fn test_find_surface_at_declared_buffer_scale_is_identity() {
    // Retina 2x with a properly declared wl_surface.set_buffer_scale: the
    // surface's logical size equals the presented view size, and wl_pointer
    // coordinates are surface-local *logical* — never buffer pixels — so the
    // view -> surface mapping must be identity.
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(102, None, None);
    // current.{width,height} are logical (buffer 1600x1200 / scale 2).
    surface.current.width = 800;
    surface.current.height = 600;
    surface.current.scale = 2;
    state.surfaces.insert(102, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(2, 102);
    window.width = 800;
    window.height = 600;
    state.windows.insert(2, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(102, 2);
    state.window_tree.stacking_order = vec![2];

    let (_, lx, ly) = state
        .find_surface_at(400.0, 300.0)
        .expect("center hit");
    assert!((lx - 400.0).abs() < 0.01, "lx={lx}");
    assert!((ly - 300.0).abs() < 0.01, "ly={ly}");
}

#[test]
fn test_view_to_surface_coords_identity() {
    // No crop, no scale mismatch: coordinates pass through untouched.
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(103, None, None);
    surface.current.width = 640;
    surface.current.height = 480;
    surface.current.scale = 1;
    state.surfaces.insert(103, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(3, 103);
    window.width = 640;
    window.height = 480;
    state.windows.insert(3, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(103, 3);

    let (x, y) = state.view_to_surface_coords(103, 640.0, 480.0, 123.0, 45.0);
    assert_eq!((x, y), (123.0, 45.0));
}

#[test]
fn test_view_to_surface_coords_csd_inset() {
    // Cropped CSD presentation: view (0,0) is the visible content origin, so
    // the xdg window geometry inset is added back 1:1 with no scaling.
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(104, None, None);
    surface.current.width = 800;
    surface.current.height = 600;
    surface.current.scale = 1;
    state.surfaces.insert(104, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(4, 104);
    window.width = 780;
    window.height = 560;
    window.geometry_x = 10;
    window.geometry_y = 32;
    state.windows.insert(4, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(104, 4);

    let (x, y) = state.view_to_surface_coords(104, 780.0, 560.0, 100.0, 50.0);
    assert_eq!((x, y), (110.0, 82.0));
}

#[test]
fn test_view_to_surface_coords_implicit_hidpi_commit() {
    // Nested-weston output-scale commit: buffer at 2x the view size without
    // set_buffer_scale means the surface's logical size really is 2x, so
    // pointer coordinates scale up by the same ratio.
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(105, None, None);
    surface.current.width = 780;
    surface.current.height = 1688;
    surface.current.scale = 1;
    state.surfaces.insert(105, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(5, 105);
    window.width = 390;
    window.height = 844;
    state.windows.insert(5, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(105, 5);

    let (x, y) = state.view_to_surface_coords(105, 390.0, 844.0, 195.0, 422.0);
    assert!((x - 390.0).abs() < 0.01, "x={x}");
    assert!((y - 844.0).abs() < 0.01, "y={y}");
}

#[test]
fn test_view_to_surface_coords_right_bottom_crop_not_hidpi() {
    // A small right/bottom-only geometry crop (ratio ~1.01) must not be
    // misclassified as an implicit HiDPI commit.
    let mut state = CompositorState::new(None);

    let mut surface = Surface::new(106, None, None);
    surface.current.width = 800;
    surface.current.height = 600;
    surface.current.scale = 1;
    state.surfaces.insert(106, Arc::new(RwLock::new(surface)));

    let mut window = Window::new(6, 106);
    window.width = 790;
    window.height = 592;
    state.windows.insert(6, Arc::new(RwLock::new(window)));
    state.surface_to_window.insert(106, 6);

    let (x, y) = state.view_to_surface_coords(106, 790.0, 592.0, 100.0, 100.0);
    assert_eq!((x, y), (100.0, 100.0));
}
