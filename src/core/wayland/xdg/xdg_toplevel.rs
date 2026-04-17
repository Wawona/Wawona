//! XDG Toplevel protocol implementation.
//!
//! This implements the xdg_toplevel protocol from the xdg-shell extension.
//! It provides the interface for managing toplevel (window) surfaces.

use wayland_server::{
    Dispatch, DisplayHandle, Resource,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_toplevel;

use crate::core::state::CompositorState;

impl Dispatch<xdg_toplevel::XdgToplevel, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &xdg_toplevel::XdgToplevel,
        request: xdg_toplevel::Request,
        _data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let toplevel_id = resource.id().protocol_id();
        let client_id = _client.id();
        let _window_id = *_data;
        let data = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).cloned();
        
        match request {
            xdg_toplevel::Request::SetTitle { title } => {
                tracing::debug!("xdg_toplevel.set_title: \"{}\"", title);
                if let Some(data) = &data {
                    if let Some(window) = state.get_window(data.window_id) {
                        {
                            let mut window = window.write().unwrap();
                            window.title = title.clone();
                        }
                        
                        // Push event for platform
                        state.pending_compositor_events.push(
                            crate::core::compositor::CompositorEvent::WindowTitleChanged {
                                window_id: data.window_id,
                                title,
                            }
                        );
                    }
                }
            }
            xdg_toplevel::Request::SetAppId { app_id } => {
                tracing::debug!("xdg_toplevel.set_app_id: \"{}\"", app_id);
                // Store app_id - could be used for window grouping
            }
            xdg_toplevel::Request::SetMaxSize { width, height } => {
                tracing::trace!("xdg_toplevel.set_max_size: {}x{}", width, height);
                if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    tl_data.max_width = width;
                    tl_data.max_height = height;
                }
            }
            xdg_toplevel::Request::SetMinSize { width, height } => {
                tracing::trace!("xdg_toplevel.set_min_size: {}x{}", width, height);
                if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    tl_data.min_width = width;
                    tl_data.min_height = height;
                }
            }
            xdg_toplevel::Request::SetMaximized => {
                tracing::debug!("xdg_toplevel.set_maximized for toplevel {}", toplevel_id);
                
                // 1. Determine target output and calculate geometry
                let (output_id, width, height) = {
                    let output_id = if let Some(tl_data) = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)) {
                         if let Some(window) = state.get_window(tl_data.window_id) {
                             let window = window.read().unwrap();
                             window.outputs.first().copied().unwrap_or(
                                 state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                             )
                         } else {
                             state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                         }
                    } else {
                        state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                    };

                    let (w, h) = if let Some((_, _, w, h)) = state.get_usable_region(output_id) {
                        (w as i32, h as i32)
                    } else {
                        (0, 0)
                    };
                    (output_id, w, h)
                };

                // 2. Save current geometry and update Window state
                let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                if let Some(wid) = window_id {
                    if let Some(window) = state.get_window(wid) {
                        if let Ok(mut w) = window.write() {
                            // Save geometry before maximizing (only if not already saved)
                            if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                                if tl_data.saved_geometry.is_none() {
                                    tl_data.saved_geometry = Some((w.x, w.y, w.width as u32, w.height as u32));
                                }
                            }
                            w.maximized = true;
                        }
                    }
                }

                // 3. Update Toplevel state and clamp to size constraints
                let (clamped_w, clamped_h) = if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    tl_data.pending_maximized = true;
                    tl_data.clamp_size(width as u32, height as u32)
                } else {
                    (width as u32, height as u32)
                };

                // 4. Send configure
                tracing::debug!("Maximized to {}x{} on output {}", clamped_w, clamped_h, output_id);
                state.send_toplevel_configure(client_id.clone(), toplevel_id, clamped_w, clamped_h);
                
                // 5. Push event for platform
                if let Some(wid) = window_id {
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowMaximized {
                            window_id: wid,
                            maximized: true,
                        }
                    );
                }
            }
            xdg_toplevel::Request::UnsetMaximized => {
                tracing::debug!("xdg_toplevel.unset_maximized for toplevel {}", toplevel_id);
                
                // Restore saved geometry
                let saved = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)).and_then(|tl| {
                    tl.pending_maximized = false;
                    tl.saved_geometry.take()
                });

                let (restore_w, restore_h) = if let Some((x, y, w, h)) = saved {
                    // Restore window position
                    let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                    if let Some(wid) = window_id {
                        if let Some(window) = state.get_window(wid) {
                            if let Ok(mut win) = window.write() {
                                win.maximized = false;
                                win.x = x;
                                win.y = y;
                            }
                        }
                    }
                    (w, h)
                } else {
                    let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                    if let Some(wid) = window_id {
                        if let Some(window) = state.get_window(wid) {
                            if let Ok(mut win) = window.write() {
                                win.maximized = false;
                                let fallback_w = win.width.max(1) as u32;
                                let fallback_h = win.height.max(1) as u32;
                                (fallback_w, fallback_h)
                            } else {
                                (1, 1)
                            }
                        } else {
                            (1, 1)
                        }
                    } else {
                        (1, 1)
                    }
                };
                
                state.send_toplevel_configure(client_id.clone(), toplevel_id, restore_w, restore_h);
                
                // Push event for platform
                let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                if let Some(wid) = window_id {
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowMaximized {
                            window_id: wid,
                            maximized: false,
                        }
                    );
                }
            }
            xdg_toplevel::Request::SetFullscreen { output } => {
                tracing::debug!("xdg_toplevel.set_fullscreen for toplevel {}", toplevel_id);
                
                // 1. Determine target output and calculate geometry
                let (output_id, width, height) = {
                    let output_id = if let Some(o) = output {
                        state
                            .output_id_by_resource
                            .get(&o.id())
                            .copied()
                            .unwrap_or_else(|| o.id().protocol_id())
                    } else {
                         if let Some(tl_data) = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)) {
                             if let Some(window) = state.get_window(tl_data.window_id) {
                                 let window = window.read().unwrap();
                                 window.outputs.first().copied().unwrap_or(
                                     state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                                 )
                             } else {
                                 state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                             }
                        } else {
                            state.outputs.get(state.primary_output).map(|o| o.id).unwrap_or(0)
                        }
                    };
                    
                    let (w, h) = if let Some((_, _, w, h)) = state.get_output_geometry(output_id) {
                        (w as i32, h as i32)
                    } else {
                        (0, 0)
                    };
                    (output_id, w, h)
                };

                // 2. Save geometry and update Window state
                let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                if let Some(wid) = window_id {
                    if let Some(window) = state.get_window(wid) {
                        if let Ok(mut w) = window.write() {
                            if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                                if tl_data.saved_geometry.is_none() {
                                    tl_data.saved_geometry = Some((w.x, w.y, w.width as u32, w.height as u32));
                                }
                            }
                            w.fullscreen = true;
                        }
                    }
                }

                // 3. Update Toplevel state (fullscreen ignores min/max per spec)
                if let Some(tl_data) = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    tl_data.pending_fullscreen = true;
                }

                tracing::debug!("Fullscreen to {}x{} on output {}", width, height, output_id);
                state.send_toplevel_configure(client_id.clone(), toplevel_id, width as u32, height as u32);
            }
            xdg_toplevel::Request::UnsetFullscreen => {
                tracing::debug!("xdg_toplevel.unset_fullscreen for toplevel {}", toplevel_id);

                // Restore saved geometry
                let saved = state.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)).and_then(|tl| {
                    tl.pending_fullscreen = false;
                    tl.saved_geometry.take()
                });

                let (restore_w, restore_h) = if let Some((x, y, w, h)) = saved {
                    let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                    if let Some(wid) = window_id {
                        if let Some(window) = state.get_window(wid) {
                            if let Ok(mut win) = window.write() {
                                win.fullscreen = false;
                                win.x = x;
                                win.y = y;
                            }
                        }
                    }
                    (w, h)
                } else {
                    let window_id = state.xdg.toplevels.get(&(client_id.clone(), toplevel_id)).map(|t| t.window_id);
                    if let Some(wid) = window_id {
                        if let Some(window) = state.get_window(wid) {
                            if let Ok(mut win) = window.write() {
                                win.fullscreen = false;
                                let fallback_w = win.width.max(1) as u32;
                                let fallback_h = win.height.max(1) as u32;
                                (fallback_w, fallback_h)
                            } else {
                                (1, 1)
                            }
                        } else {
                            (1, 1)
                        }
                    } else {
                        (1, 1)
                    }
                };
                
                state.send_toplevel_configure(client_id, toplevel_id, restore_w, restore_h);
            }
            xdg_toplevel::Request::SetMinimized => {
                tracing::debug!("xdg_toplevel.set_minimized");
                if let Some(data) = &data {
                    if let Some(window) = state.get_window(data.window_id) {
                        let mut window = window.write().unwrap();
                        window.minimized = true;
                        
                        // Push event for platform
                        state.pending_compositor_events.push(
                            crate::core::compositor::CompositorEvent::WindowMinimized {
                                window_id: data.window_id,
                                minimized: true,
                            }
                        );
                    }
                }
            }
            xdg_toplevel::Request::Move { seat, serial } => {
                let seat_id = seat.id().protocol_id();
                tracing::debug!("xdg_toplevel.move requested: seat={}, serial={}", seat_id, serial);
                if let Some(data) = &data {
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowMoveRequested {
                            window_id: data.window_id,
                            seat_id,
                            serial,
                        }
                    );
                }
            }
            xdg_toplevel::Request::Resize { seat, serial, edges } => {
                let seat_id = seat.id().protocol_id();
                let edge_val = match edges {
                    wayland_server::WEnum::Value(v) => v.into(),
                    wayland_server::WEnum::Unknown(v) => v,
                };
                tracing::debug!("xdg_toplevel.resize requested: seat={}, serial={}, edges={}", seat_id, serial, edge_val);
                if let Some(data) = &data {
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowResizeRequested {
                            window_id: data.window_id,
                            seat_id,
                            serial,
                            edges: edge_val,
                        }
                    );
                }
            }
            xdg_toplevel::Request::ShowWindowMenu { seat: _, serial: _, x, y } => {
                tracing::debug!("xdg_toplevel.show_window_menu at ({}, {})", x, y);
             }
            xdg_toplevel::Request::Destroy => {
                if let Some(data) = &data {
                    tracing::debug!("xdg_toplevel destroyed: window_id={}", data.window_id);
                    state.remove_window(data.window_id);
                }
                state.xdg.toplevels.remove(&(client_id, toplevel_id));
            }
            _ => {}
        }
    }
}

