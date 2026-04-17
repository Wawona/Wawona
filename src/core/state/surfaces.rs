//! Surface and subsurface management for the compositor.
//!
//! Contains `CompositorState` methods for managing wl_surface lifecycle,
//! wl_subsurface relationships, buffer handling, and surface commit logic.

use super::*;

impl CompositorState {
    // =========================================================================
    // Surface Management
    // =========================================================================
    
    /// Generate next surface ID
    pub fn next_surface_id(&mut self) -> u32 {
        let id = self.next_surface_id;
        self.next_surface_id += 1;
        id
    }
    
    /// Add a surface
    pub fn add_surface(&mut self, surface: Surface) -> u32 {
        let id = surface.id;
        self.surfaces.insert(id, Arc::new(RwLock::new(surface)));
        tracing::debug!("Added surface {}", id);
        id
    }
    
    /// Remove a surface
    pub fn remove_surface(&mut self, surface_id: u32) {
        self.surfaces.remove(&surface_id);
        self.frame_callbacks.remove(&surface_id);
        
        if self.focus.grabbed_surface == Some(surface_id) {
            self.focus.grabbed_surface = None;
        }
        
        tracing::debug!("Removed surface {}", surface_id);
    }
    
    /// Get a surface
    pub fn get_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Surface>>> {
        self.surfaces.get(&surface_id).cloned()
    }

    // =========================================================================
    // Subsurface Management
    // =========================================================================
    
    pub fn add_subsurface_resource(&mut self, surface_id: u32, parent_id: u32, _subsurface: wayland_server::protocol::wl_subsurface::WlSubsurface) {
         self.subsurface_children.entry(parent_id).or_default().push(surface_id);
    }

    /// Add a subsurface relationship
    pub fn add_subsurface(&mut self, surface_id: u32, parent_id: u32) {
        let z_order = self.subsurface_children
            .get(&parent_id)
            .map(|c| c.len() as i32)
            .unwrap_or(0);
        
        let state = SubsurfaceState {
            surface_id,
            parent_id,
            position: (0, 0),
            pending_position: (0, 0),
            sync: true,
            z_order,
        };
        
        self.subsurfaces.insert(surface_id, state);
        self.subsurface_children
            .entry(parent_id)
            .or_insert_with(Vec::new)
            .push(surface_id);
        
        tracing::debug!(
            "Subsurface {} added to parent {} (z-order: {})",
            surface_id, parent_id, z_order
        );
    }
    
    /// Remove a subsurface
    pub fn remove_subsurface(&mut self, surface_id: u32) {
        if let Some(state) = self.subsurfaces.remove(&surface_id) {
            if let Some(children) = self.subsurface_children.get_mut(&state.parent_id) {
                children.retain(|&id| id != surface_id);
            }
            tracing::debug!("Subsurface {} removed from parent {}", surface_id, state.parent_id);
        }
    }
    
    /// Set subsurface pending position
    pub fn set_subsurface_position(&mut self, surface_id: u32, x: i32, y: i32) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.pending_position = (x, y);
        }
    }
    
    /// Commit subsurface position (called on parent commit for sync mode)
    pub fn commit_subsurface_position(&mut self, surface_id: u32) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.position = state.pending_position;
        }
    }
    
    /// Check if a surface is effectively synchronized
    pub fn is_effectively_sync(&self, surface_id: u32) -> bool {
        let mut current_id = surface_id;
        while let Some(sub) = self.subsurfaces.get(&current_id) {
            if sub.sync {
                return true;
            }
            current_id = sub.parent_id;
        }
        false
    }

    /// Handle a surface commit request
    pub fn handle_surface_commit(&mut self, surface_id: u32) {
        if let Some((_, xdg_surface_data)) = self
            .xdg
            .surfaces
            .iter()
            .find(|(_, data)| data.surface_id == surface_id)
        {
            if xdg_surface_data.pending_serial != 0 {
                self.commit_before_ack_count = self.commit_before_ack_count.saturating_add(1);
                crate::wlog!(
                    crate::util::logging::STATE,
                    "Commit arrived before latest ack: surface={} pending_serial={} count={}",
                    surface_id,
                    xdg_surface_data.pending_serial,
                    self.commit_before_ack_count
                );
            }
        }

        let is_sync = self.is_effectively_sync(surface_id);
        
        let release_id = if let Some(surface) = self.get_surface(surface_id) {
            let mut surface = surface.write().unwrap();
            if is_sync {
                surface.commit_sync()
            } else {
                surface.commit()
            }
        } else {
            None
        };

        let client_id = if let Some(surface) = self.get_surface(surface_id) {
            surface.read().unwrap().client_id.clone()
        } else {
            None
        };

        if let Some(bid) = release_id {
            if let Some(cid) = client_id {
                self.queue_buffer_release(cid, bid);
            }
        }

        if !is_sync {
            self.apply_subsurface_cached_state_recursive(surface_id);
            
            if let Some(children) = self.subsurface_children.get(&surface_id).cloned() {
                for child_id in children {
                    self.commit_subsurface_position(child_id);
                }
            }
        }
        
        self.ext.presentation.mark_committed(surface_id);
        self.finalize_surface_commit(surface_id);
    }

    /// Queue a buffer for release after next frame presentation
    pub fn queue_buffer_release(&mut self, client_id: ClientId, buffer_id: u32) {
        if !self.pending_buffer_releases.contains(&(client_id.clone(), buffer_id)) {
            self.pending_buffer_releases.push((client_id, buffer_id));
        }
    }

    /// Flush all pending buffer releases (called after frame presentation)
    pub fn flush_buffer_releases(&mut self) {
        let releases: Vec<_> = self.pending_buffer_releases.drain(..).collect();
        if !releases.is_empty() {
            tracing::debug!("Flushing {} queued buffer releases", releases.len());
        }
        for (cid, bid) in releases {
            self.release_buffer(cid, bid);
        }
    }

    /// Recursively apply cached state for synchronized subsurfaces
    fn apply_subsurface_cached_state_recursive(&mut self, surface_id: u32) {
        if let Some(children) = self.subsurface_children.get(&surface_id).cloned() {
            for child_id in children {
                let is_child_sync = self.subsurfaces.get(&child_id).map(|s| s.sync).unwrap_or(false);
                if is_child_sync {
                    let release_id = if let Some(surface) = self.get_surface(child_id) {
                        let mut surface = surface.write().unwrap();
                        surface.apply_cached()
                    } else {
                        None
                    };
                    
                    if let Some(bid) = release_id {
                        if let Some(cid) = self.get_surface(child_id).and_then(|s| s.read().unwrap().client_id.clone()) {
                            self.queue_buffer_release(cid, bid);
                        }
                    }
                    
                    self.apply_subsurface_cached_state_recursive(child_id);
                }
            }
        }
    }

    /// Finalize commit logic (emits events, handles window/layer mapping)
    fn finalize_surface_commit(&mut self, id: u32) {
        let surface_ref = if let Some(s) = self.get_surface(id) { s } else { return };
        let surface = surface_ref.write().unwrap();
        
        let mut window_id = self.surface_to_window.get(&id).copied();
        
        let client_id = surface.client_id.clone();
        let layer_id = if let Some(cid) = &client_id {
            self.wlr.surface_to_layer.get(&(cid.clone(), id)).copied()
        } else {
            None
        };
        
        if window_id.is_none() && layer_id.is_none() {
            if let Some(sub) = self.subsurfaces.get(&id) {
                let mut parent_id = sub.parent_id;
                for _ in 0..10 {
                    if let Some(wid) = self.surface_to_window.get(&parent_id) {
                        window_id = Some(*wid);
                        break;
                    }
                    if let Some(psub) = self.subsurfaces.get(&parent_id) {
                        parent_id = psub.parent_id;
                    } else {
                        break;
                    }
                }
            }
        }

        let is_cursor = self.seat.pointer.cursor_surface == Some(id);
        let client_id = if let Some(cid) = client_id {
            cid
        } else {
            return;
        };
        
        if let Some(wid) = window_id {
            // Synchronize window dimensions with surface dimensions.
            //
            // When xdg_surface geometry is set, use the geometry width/height
            // so the platform window matches the content area (excluding the
            // CSD shadow).  Store the geometry origin so pointer coordinates
            // can be offset to surface-local coords.
            let mut size_changed = false;
            if let Some(window) = self.get_window(wid) {
                let mut window = window.write().unwrap();
                let old_w = window.width;
                let old_h = window.height;
                let is_fullscreen_shell_window = self.ext.fullscreen_shell.presented_window_id == Some(wid);
                if is_fullscreen_shell_window {
                    if let Some(output) = self.outputs.get(self.primary_output) {
                        window.width = output.width as i32;
                        window.height = output.height as i32;
                    }
                    window.geometry_x = 0;
                    window.geometry_y = 0;
                } else {
                    let geom = self.xdg.surfaces.values()
                        .find(|s| s.surface_id == id)
                        .and_then(|s| s.geometry);
                    if let Some((gx, gy, gw, gh)) = geom {
                        window.width = gw;
                        window.height = gh;
                        window.geometry_x = gx;
                        window.geometry_y = gy;
                    } else {
                        window.width = surface.current.width;
                        window.height = surface.current.height;
                        window.geometry_x = 0;
                        window.geometry_y = 0;
                    }
                }
                if window.width != old_w || window.height != old_h {
                    size_changed = true;
                }
            }

            // Notify the platform when the committed surface size differs from
            // the window size the platform created.  Fullscreen-shell windows
            // are excluded: their size is dictated by the output, not the
            // client buffer.
            if size_changed && self.ext.fullscreen_shell.presented_window_id != Some(wid) {
                if let Some(window) = self.get_window(wid) {
                    let window = window.read().unwrap();
                    if window.width > 0 && window.height > 0 {
                        self.pending_compositor_events.push(
                            crate::core::compositor::CompositorEvent::WindowSizeChanged {
                                window_id: wid,
                                width: window.width as u32,
                                height: window.height as u32,
                            }
                        );
                    }
                }
            }

            let buffer_id = surface.current.buffer_id.map(|id| id as u64);
            self.pending_compositor_events.push(
                crate::core::compositor::CompositorEvent::SurfaceCommitted {
                    client_id: client_id.clone(),
                    surface_id: id,
                    buffer_id,
                }
            );
        } else if layer_id.is_some() {
            let buffer_id = surface.current.buffer_id.map(|id| id as u64);
            self.pending_compositor_events.push(
                crate::core::compositor::CompositorEvent::LayerSurfaceCommitted {
                    client_id: client_id.clone(),
                    surface_id: id,
                    buffer_id,
                }
            );
        } else if is_cursor {
            let buffer_id = surface.current.buffer_id.map(|id| id as u64);
            self.pending_compositor_events.push(
                crate::core::compositor::CompositorEvent::CursorCommitted {
                    client_id: client_id.clone(),
                    surface_id: id,
                    buffer_id,
                    hotspot_x: self.seat.pointer.cursor_hotspot_x as i32,
                    hotspot_y: self.seat.pointer.cursor_hotspot_y as i32,
                }
            );
        }
    }

    /// Set subsurface sync mode
    pub fn set_subsurface_sync(&mut self, surface_id: u32, sync: bool) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.sync = sync;
        }
    }
    
    /// Place subsurface above sibling
    pub fn place_subsurface_above(&mut self, surface_id: u32, sibling_id: u32) {
        if let Some(state) = self.subsurfaces.get(&surface_id) {
            let parent_id = state.parent_id;
            if let Some(children) = self.subsurface_children.get_mut(&parent_id) {
                if let Some(sibling_pos) = children.iter().position(|&id| id == sibling_id) {
                    children.retain(|&id| id != surface_id);
                    let insert_pos = (sibling_pos + 1).min(children.len());
                    children.insert(insert_pos, surface_id);
                    
                    for (i, &id) in children.iter().enumerate() {
                        if let Some(s) = self.subsurfaces.get_mut(&id) {
                            s.z_order = i as i32;
                        }
                    }
                }
            }
        }
    }
    
    /// Place subsurface below sibling
    pub fn place_subsurface_below(&mut self, surface_id: u32, sibling_id: u32) {
        if let Some(state) = self.subsurfaces.get(&surface_id) {
            let parent_id = state.parent_id;
            if let Some(children) = self.subsurface_children.get_mut(&parent_id) {
                if let Some(sibling_pos) = children.iter().position(|&id| id == sibling_id) {
                    children.retain(|&id| id != surface_id);
                    children.insert(sibling_pos, surface_id);
                    
                    for (i, &id) in children.iter().enumerate() {
                        if let Some(s) = self.subsurfaces.get_mut(&id) {
                            s.z_order = i as i32;
                        }
                    }
                }
            }
        }
    }
    
    /// Get subsurface state
    pub fn get_subsurface(&self, surface_id: u32) -> Option<&SubsurfaceState> {
        self.subsurfaces.get(&surface_id)
    }
    
    /// Get children of a surface (subsurfaces)
    pub fn get_subsurface_children(&self, parent_id: u32) -> Option<&Vec<u32>> {
        self.subsurface_children.get(&parent_id)
    }
    
    /// Check if surface is a subsurface
    pub fn is_subsurface(&self, surface_id: u32) -> bool {
        self.subsurfaces.contains_key(&surface_id)
    }

    // =========================================================================
    // Buffer Management
    // =========================================================================

    /// Add a buffer
    pub fn add_buffer(&mut self, client_id: ClientId, buffer: crate::core::surface::Buffer) {
        let id = buffer.id;
        self.buffers.insert((client_id, id), Arc::new(RwLock::new(buffer)));
        tracing::debug!("Added buffer {}", id);
    }

    /// Get a buffer by ID
    pub fn get_buffer(&self, client_id: ClientId, id: u32) -> Option<Arc<RwLock<crate::core::surface::Buffer>>> {
        self.buffers.get(&(client_id, id)).cloned()
    }

    /// Release a buffer (notify client we are done with it)
    pub fn release_buffer(&mut self, client_id: ClientId, buffer_id: u32) {
        if let Some(buffer) = self.buffers.get(&(client_id, buffer_id)) {
            let mut buffer = buffer.write().unwrap();
            buffer.release();
            tracing::debug!("Released buffer {}", buffer_id);
        }
    }

    /// Remove a buffer
    pub fn remove_buffer(&mut self, client_id: ClientId, id: u32) {
        self.buffers.remove(&(client_id, id));
        tracing::debug!("Removed buffer {}", id);
    }
}
