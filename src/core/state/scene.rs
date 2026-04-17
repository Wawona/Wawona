//! Scene graph building and layer surface positioning.
//!
//! Contains the `CompositorState` methods responsible for constructing
//! the scene graph from windows, layer surfaces, popups, and subsurfaces,
//! as well as repositioning layer surfaces and computing usable output area.

use super::*;

impl CompositorState {
    /// Report presentation feedback
    pub fn report_presentation_feedback(&mut self, _timestamp: std::time::Instant, refresh_mhz: u32) {
        let seq = self.next_presentation_seq();
        
        let refresh_ns = if refresh_mhz > 0 {
            1_000_000_000_000 / refresh_mhz as u64
        } else {
            16_666_666
        };
        
        let ts_ns = crate::core::Compositor::timestamp_ms() as u64 * 1_000_000;
        
        self.ext.presentation.send_presented_events(ts_ns, refresh_ns, seq);
    }

    /// Send a configure event to an xdg_toplevel and its associated xdg_surface.
    /// Size is clamped to the client's min/max constraints (unless fullscreen, which ignores constraints per spec).
    pub fn send_toplevel_configure(&mut self, client_id: ClientId, toplevel_id: u32, width: u32, height: u32) -> u32 {
        let serial = self.next_serial();
        crate::wlog!(crate::util::logging::COMPOSITOR, "send_toplevel_configure: client={:?} tl_id={} size={}x{} serial={}", 
            client_id, toplevel_id, width, height, serial);

        let mut to_send = None;
        if let Some(toplevel_data) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
            toplevel_data.pending_serial = serial;
            
            let (final_w, final_h) = if toplevel_data.pending_fullscreen {
                (width.max(1), height.max(1))
            } else if width == 0 && height == 0 {
                // Treat 0x0 as "unchanged" for non-fullscreen toplevels.
                // Some clients (e.g. weston-simple-shm) abort on zero configure sizes.
                let prev_w = toplevel_data.width.max(1);
                let prev_h = toplevel_data.height.max(1);
                (prev_w, prev_h)
            } else {
                let (clamped_w, clamped_h) = toplevel_data.clamp_size(width.max(1), height.max(1));
                (clamped_w.max(1), clamped_h.max(1))
            };

            toplevel_data.width = final_w;
            toplevel_data.height = final_h;

            if let Some(resource) = &toplevel_data.resource {
                let mut states = Vec::new();
                
                if toplevel_data.activated {
                    states.extend_from_slice(&(wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated as u32).to_ne_bytes());
                }
                
                if toplevel_data.pending_maximized {
                    states.extend_from_slice(&(wayland_protocols::xdg::shell::server::xdg_toplevel::State::Maximized as u32).to_ne_bytes());
                } 

                if toplevel_data.pending_fullscreen {
                    states.extend_from_slice(&(wayland_protocols::xdg::shell::server::xdg_toplevel::State::Fullscreen as u32).to_ne_bytes());
                }
                
                crate::wlog!(crate::util::logging::COMPOSITOR, "Configuring xdg_toplevel {} with states: {:?}, size={}x{}", toplevel_id, states, final_w, final_h);
                to_send = Some((resource.clone(), toplevel_data.xdg_surface_id, states, final_w, final_h));
            } else {
                crate::wlog!(crate::util::logging::COMPOSITOR, "send_toplevel_configure: No resource for tl_id={}", toplevel_id);
            }
        } else {
            crate::wlog!(crate::util::logging::COMPOSITOR, "send_toplevel_configure: tl_id={} NOT FOUND", toplevel_id);
        }
        
        if let Some((toplevel, xdg_surface_id, states, final_w, final_h)) = to_send {
            toplevel.configure(final_w as i32, final_h as i32, states);
            
            if let Some(surface_data) = self.xdg.surfaces.get_mut(&(client_id, xdg_surface_id)) {
                surface_data.pending_serial = serial;
                surface_data.configured = false;
                if let Some(resource) = &surface_data.resource {
                    crate::wlog!(crate::util::logging::COMPOSITOR, "Actually sending xdg_surface.configure(serial={}) to xdg_surface_id={}", serial, xdg_surface_id);
                    resource.configure(serial);
                } else {
                    crate::wlog!(crate::util::logging::COMPOSITOR, "No resource for xdg_surface_id={} when sending configure", xdg_surface_id);
                }
            } else {
                crate::wlog!(crate::util::logging::COMPOSITOR, "xdg_surface_id={} NOT FOUND in xdg.surfaces", xdg_surface_id);
            }
        }
        
        serial
    }

    /// Send `xdg_toplevel.close` so the client can shut down cleanly before the host
    /// tears down the NSWindow.  Returns `true` if a matching toplevel was found.
    pub fn send_toplevel_close_for_window(&mut self, window_id: u32) -> bool {
        for data in self.xdg.toplevels.values_mut() {
            if data.window_id == window_id {
                if let Some(res) = &data.resource {
                    crate::wlog!(
                        crate::util::logging::COMPOSITOR,
                        "Sending xdg_toplevel.close for window_id={}",
                        window_id
                    );
                    res.close();
                    return true;
                }
                break;
            }
        }
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "send_toplevel_close_for_window: no toplevel for window_id={}",
            window_id
        );
        false
    }

    /// Dismiss the active popup grab and all its child popups
    pub fn dismiss_popup_grab(&mut self) {
        while let Some((cid, pid)) = self.seat.popup_grab_stack.pop() {
            if let Some(data) = self.xdg.popups.get(&(cid.clone(), pid)) {
                let resource = data.resource.clone();
                if let Some(res) = resource {
                    tracing::debug!("Dismissing popup {} for client {:?}", pid, cid);
                    res.popup_done();
                }
            }
        }
    }

    /// Get the geometry of an output (x, y, width, height)
    pub fn get_output_geometry(&self, output_id: u32) -> Option<(i32, i32, u32, u32)> {
        self.outputs.iter().find(|o| o.id == output_id)
            .map(|o| (o.x, o.y, o.width, o.height))
    }

    /// Get the usable region of an output (excluding layer shell exclusive zones)
    pub fn get_usable_region(&self, output_id: u32) -> Option<(i32, i32, u32, u32)> {
        let (mut ox, mut oy, mut owidth, mut oheight) = self.get_output_geometry(output_id)?;
        
        let mut top_zone = 0;
        let mut bottom_zone = 0;
        let mut left_zone = 0;
        let mut right_zone = 0;

        for layer_surface in self.wlr.layer_surfaces.values() {
            let ls = layer_surface.read().unwrap();
            if ls.output_id != output_id || ls.exclusive_zone <= 0 {
                continue;
            }

            let anchor = ls.anchor;
            let zone = ls.exclusive_zone as i32;

            if (anchor & 1) != 0 && (anchor & 2) == 0 {
                 top_zone += zone;
            } else if (anchor & 2) != 0 && (anchor & 1) == 0 {
                 bottom_zone += zone;
            } else if (anchor & 4) != 0 && (anchor & 8) == 0 {
                 left_zone += zone;
            } else if (anchor & 8) != 0 && (anchor & 4) == 0 {
                 right_zone += zone;
            }
        }
        
        ox += left_zone;
        oy += top_zone;
        
        let width_reduction = (left_zone + right_zone) as u32;
        let height_reduction = (top_zone + bottom_zone) as u32;
        
        owidth = owidth.saturating_sub(width_reduction);
        oheight = oheight.saturating_sub(height_reduction);
        
        Some((ox, oy, owidth, oheight))
    }

    /// Generate next scene node ID
    pub fn next_node_id(&mut self) -> u32 {
        let id = self.next_node_id;
        self.next_node_id += 1;
        id
    }

    /// Rebuild the scene graph from windows and layers
    pub fn build_scene(&mut self) {
        let mut new_scene = Scene::new();
        let root_id = self.next_node_id();
        let mut root = SceneNode::new(root_id);
        
        if let Some(output) = self.outputs.get(self.primary_output) {
            root.set_size(output.width, output.height);
        }
        
        new_scene.add_node(root);
        new_scene.set_root(root_id);
        
        self.add_layer_to_scene(&mut new_scene, root_id, 0);
        self.add_layer_to_scene(&mut new_scene, root_id, 1);
        
        // Pre-collect xdg_surface geometry data keyed by wl_surface ID
        let geom_by_surface: std::collections::HashMap<u32, (i32, i32, i32, i32)> =
            self.xdg.surfaces.values()
                .filter_map(|s| s.geometry.map(|g| (s.surface_id, g)))
                .collect();

        let mut ordered_windows = self.window_tree.stacking_order.clone();
        for window_id in self.windows.keys().copied() {
            if !ordered_windows.contains(&window_id) {
                ordered_windows.push(window_id);
            }
        }

        for window_id in ordered_windows {
            if let Some(window) = self.get_window(window_id) {
                let window = window.read().unwrap();
                let node_id = self.next_node_id();
                let mut node = SceneNode::new(node_id)
                    .with_surface(window.surface_id);
                let is_fullscreen_shell_window =
                    self.ext.fullscreen_shell.presented_window_id == Some(window.id);
                
                node.set_position(window.x, window.y);
                // Render to the client's last committed buffer size when available.
                // During live resize the requested window size can change before the
                // client submits a matching buffer; using the requested size here
                // stretches the old frame instead of showing the real committed size.
                let mut render_width = window.width.max(0) as u32;
                let mut render_height = window.height.max(0) as u32;
                if !is_fullscreen_shell_window {
                    if let Some(surface_ref) = self.get_surface(window.surface_id) {
                        let surface = surface_ref.read().unwrap();
                        let committed_width = surface.current.width.max(0) as u32;
                        let committed_height = surface.current.height.max(0) as u32;
                        if committed_width > 0 && committed_height > 0 {
                            render_width = committed_width;
                            render_height = committed_height;
                        }
                        node.scale = (surface.current.scale.max(1)) as f32;
                    }
                } else if let Some(surface_ref) = self.get_surface(window.surface_id) {
                    let surface = surface_ref.read().unwrap();
                    node.scale = (surface.current.scale.max(1)) as f32;
                }
                node.set_size(render_width, render_height);

                // When xdg_surface geometry is set, compute a normalized
                // content_rect so the platform renderer crops the buffer
                // to the content area (excluding CSD/SSD shadow).
                if let Some(&(gx, gy, gw, gh)) = geom_by_surface.get(&window.surface_id) {
                    if let Some(surf_ref) = self.get_surface(window.surface_id) {
                        let surf = surf_ref.read().unwrap();
                        let buf_w = surf.current.width as f32;
                        let buf_h = surf.current.height as f32;
                        if buf_w > 0.0 && buf_h > 0.0 && gw > 0 && gh > 0 {
                            node.content_rect = ContentRect {
                                x: gx as f32 / buf_w,
                                y: gy as f32 / buf_h,
                                w: gw as f32 / buf_w,
                                h: gh as f32 / buf_h,
                            };
                        }
                    }
                }

                let alpha = self.ext.alpha_modifier.get_alpha_f64(window.surface_id) as f32;
                node.opacity = alpha;
                
                new_scene.add_node(node);
                new_scene.add_child(root_id, node_id);
                
                let geom_offset = geom_by_surface.get(&window.surface_id)
                    .map(|&(gx, gy, _, _)| (gx, gy))
                    .unwrap_or((0, 0));
                self.add_subsurfaces_to_scene(&mut new_scene, node_id, window.surface_id, geom_offset);
            }
        }
        
        let popup_data_list: Vec<_> = self.xdg.popups.iter()
            .map(|((cid, _), p)| (cid.clone(), p.surface_id, p.geometry, p.parent_id))
            .collect();

        for (cid, popup_surface_id, geometry, parent_window_id) in popup_data_list {
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id)
                .with_surface(popup_surface_id);
            
            node.set_position(geometry.0, geometry.1);
            node.set_size(geometry.2 as u32, geometry.3 as u32);
            
            let alpha = self.ext.alpha_modifier.get_alpha_f64(popup_surface_id) as f32;
            node.opacity = alpha;
            
            new_scene.add_node(node);
            
            let mut parent_node_id = root_id;
            if let Some(pwid) = parent_window_id {
                if let Some(parent_window) = self.get_window(pwid) {
                    let parent_surf_id = parent_window.read().unwrap().surface_id;
                    for n in new_scene.nodes.values() {
                        if n.surface_id == Some(parent_surf_id) {
                            parent_node_id = n.id;
                            break;
                        }
                    }
                }
            }
            
            new_scene.add_child(parent_node_id, node_id);
            
            self.add_subsurfaces_to_scene(&mut new_scene, node_id, popup_surface_id, (0, 0));
        }
        
        self.add_layer_to_scene(&mut new_scene, root_id, 2);
        self.add_layer_to_scene(&mut new_scene, root_id, 3);
        
        self.scene = new_scene;
    }

    /// Reposition all layer surfaces and update output usable areas.
    pub fn reposition_layer_surfaces(&mut self) {
        let output_count = self.outputs.len();
        for i in 0..output_count {
            let (output_id, ox, oy, ow, oh) = {
                let o = &self.outputs[i];
                (o.id, o.x, o.y, o.width as i32, o.height as i32)
            };
            
            let mut usable = crate::util::geometry::Rect::new(ox, oy, ow as u32, oh as u32);
            
            // Apply platform safe area insets as implicit exclusive zones.
            let (sa_top, sa_right, sa_bottom, sa_left) = self.outputs[i].safe_area_insets;
            if sa_top > 0 {
                usable.y += sa_top;
                usable.height = (usable.height as i32 - sa_top).max(0) as u32;
            }
            if sa_bottom > 0 {
                usable.height = (usable.height as i32 - sa_bottom).max(0) as u32;
            }
            if sa_left > 0 {
                usable.x += sa_left;
                usable.width = (usable.width as i32 - sa_left).max(0) as u32;
            }
            if sa_right > 0 {
                usable.width = (usable.width as i32 - sa_right).max(0) as u32;
            }
            
            let ls_refs: Vec<_> = self.wlr.layer_surfaces.values()
                .filter(|ls| ls.read().unwrap().output_id == output_id)
                .cloned()
                .collect();
                
            for layer in 0..4 {
                for ls_lock in &ls_refs {
                    let ls_read = ls_lock.read().unwrap();
                    if ls_read.layer != layer || ls_read.exclusive_zone <= 0 {
                        continue;
                    }
                    
                    let zone = ls_read.exclusive_zone;
                    let anchor = ls_read.anchor;
                    
                    // Anchor bits: 1=top, 2=bottom, 4=left, 8=right
                    if (anchor & 1) != 0 && (anchor & 4) != 0 && (anchor & 8) != 0 {
                        usable.y += zone;
                        usable.height = (usable.height as i32 - zone).max(0) as u32;
                    } else if (anchor & 2) != 0 && (anchor & 4) != 0 && (anchor & 8) != 0 {
                        usable.height = (usable.height as i32 - zone).max(0) as u32;
                    } else if (anchor & 4) != 0 && (anchor & 1) != 0 && (anchor & 2) != 0 {
                        usable.x += zone;
                        usable.width = (usable.width as i32 - zone).max(0) as u32;
                    } else if (anchor & 8) != 0 && (anchor & 1) != 0 && (anchor & 2) != 0 {
                        usable.width = (usable.width as i32 - zone).max(0) as u32;
                    } else if anchor == 1 {
                         usable.y += zone;
                         usable.height = (usable.height as i32 - zone).max(0) as u32;
                    } else if anchor == 2 {
                         usable.height = (usable.height as i32 - zone).max(0) as u32;
                    } else if anchor == 4 {
                         usable.x += zone;
                         usable.width = (usable.width as i32 - zone).max(0) as u32;
                    } else if anchor == 8 {
                         usable.width = (usable.width as i32 - zone).max(0) as u32;
                    }
                }
            }
            
            self.outputs[i].usable_area = usable;
            
            for ls_lock in &ls_refs {
                let mut ls = ls_lock.write().unwrap();
                let anchor = ls.anchor;
                let margin = ls.margin;
                let mut w = ls.width;
                let mut h = ls.height;
                
                let x;
                let y;
                
                if (anchor & 4) != 0 && (anchor & 8) != 0 {
                    w = (ow - margin.1 - margin.3).max(0) as u32;
                    x = ox + margin.3;
                } else if (anchor & 8) != 0 {
                    x = ox + ow - w as i32 - margin.1;
                } else if (anchor & 4) != 0 {
                    x = ox + margin.3;
                } else {
                    x = ox + (ow - w as i32) / 2;
                }
                
                if (anchor & 1) != 0 && (anchor & 2) != 0 {
                    h = (oh - margin.0 - margin.2).max(0) as u32;
                    y = oy + margin.0;
                } else if (anchor & 2) != 0 {
                    y = oy + oh - h as i32 - margin.2;
                } else if (anchor & 1) != 0 {
                    y = oy + margin.0;
                } else {
                    y = oy + (oh - h as i32) / 2;
                }
                
                ls.x = x;
                ls.y = y;
                ls.width = w;
                ls.height = h;
            }
        }
    }

    fn add_layer_to_scene(&mut self, scene: &mut Scene, root_id: u32, layer: u32) {
        self.reposition_layer_surfaces();

        let mut node_data = Vec::new();
        for ls_ref in self.wlr.layer_surfaces.values() {
            let ls = ls_ref.read().unwrap();
            if ls.layer == layer {
                node_data.push((ls.surface_id, ls.x, ls.y, ls.width, ls.height));
            }
        }
        
        for (surface_id, x, y, width, height) in node_data {
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id)
                .with_surface(surface_id);
            
            node.set_position(x, y);
            node.set_size(width, height);
            if let Some(surface_ref) = self.get_surface(surface_id) {
                let surface = surface_ref.read().unwrap();
                node.scale = (surface.current.scale.max(1)) as f32;
            }
            
            scene.add_node(node);
            scene.add_child(root_id, node_id);
            
            self.add_subsurfaces_to_scene(scene, node_id, surface_id, (0, 0));
        }
    }

    /// Build subsurface scene nodes for `parent_surface_id`.
    ///
    /// `geometry_offset` is subtracted from the positions of **direct**
    /// children only, converting surface-local coordinates to
    /// geometry-local coordinates when the parent window's buffer is
    /// cropped to its `set_window_geometry` content area.  Nested
    /// subsurfaces recurse with `(0, 0)` because their positions are
    /// already relative to their (shifted) parent.
    fn add_subsurfaces_to_scene(
        &mut self,
        scene: &mut Scene,
        parent_node_id: u32,
        parent_surface_id: u32,
        geometry_offset: (i32, i32),
    ) {
        if let Some(children) = self.subsurface_children.get(&parent_surface_id).cloned() {
            for child_surface_id in children {
                let sub_info = self.subsurfaces.get(&child_surface_id).map(|s| (s.position, s.sync));
                
                if let Some((pos, _sync)) = sub_info {
                    let node_id = self.next_node_id();
                    let mut node = SceneNode::new(node_id)
                        .with_surface(child_surface_id);
                    
                    node.set_position(pos.0 - geometry_offset.0, pos.1 - geometry_offset.1);
                    
                    if let Some(surface_ref) = self.get_surface(child_surface_id) {
                        let surface = surface_ref.read().unwrap();
                        node.set_size(surface.current.width.max(0) as u32, surface.current.height.max(0) as u32);
                        node.scale = (surface.current.scale.max(1)) as f32;
                    }
                    
                    scene.add_node(node);
                    scene.add_child(parent_node_id, node_id);
                    
                    self.add_subsurfaces_to_scene(scene, node_id, child_surface_id, (0, 0));
                }
            }
        }
    }
}
