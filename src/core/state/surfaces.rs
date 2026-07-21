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
    
    /// Copy `xdg_surface.set_window_geometry` from Smithay into our xdg surface
    /// bookkeeping so scene building and host window sizing can crop CSD chrome.
    pub fn sync_xdg_window_geometry_from_surface(
        &mut self,
        wl_surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
        surface_id: u32,
    ) {
        use smithay::utils::Rectangle;
        use smithay::wayland::compositor::with_states;
        use smithay::wayland::shell::xdg::SurfaceCachedState;

        let geometry: Option<Rectangle<i32, smithay::utils::Logical>> =
            with_states(wl_surface, |states| {
                states
                    .cached_state
                    .get::<SurfaceCachedState>()
                    .current()
                    .geometry
            });

        let Some(geometry) = geometry else {
            return;
        };

        for data in self.xdg.surfaces.values_mut() {
            if data.surface_id == surface_id {
                data.geometry = Some((
                    geometry.loc.x,
                    geometry.loc.y,
                    geometry.size.w,
                    geometry.size.h,
                ));
                return;
            }
        }
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
                crate::wlog_hot!(
                    crate::util::logging::STATE,
                    "Commit arrived before latest ack: surface={} pending_serial={} count={}",
                    surface_id,
                    xdg_surface_data.pending_serial,
                    self.commit_before_ack_count
                );
            }
        }

        // Smithay owns sync-subsurface caching: this handler is only invoked
        // once a surface's state has actually been applied (for sync
        // subsurfaces that happens on the ancestor's commit, and smithay
        // re-invokes CompositorHandler::commit for each surface in the
        // transaction). So the shadow state always does a direct commit here.
        let release_id = if let Some(surface) = self.get_surface(surface_id) {
            let mut surface = surface.write().unwrap();
            surface.commit()
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

        if let Some(children) = self.subsurface_children.get(&surface_id).cloned() {
            for child_id in children {
                self.commit_subsurface_position(child_id);
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

    /// Finalize commit logic (emits events, handles window/layer mapping)
    fn finalize_surface_commit(&mut self, id: u32) {
        let surface_ref = if let Some(s) = self.get_surface(id) { s } else { return };
        let surface = surface_ref.write().unwrap();
        
        let direct_window_id = self.surface_to_window.get(&id).copied();
        let mut window_id = direct_window_id;
        
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
            // Only the root/toplevel wl_surface that is directly mapped to a host window
            // may drive platform window-size synchronization.
            //
            // Subsurfaces can resolve to the parent window_id above, but their commit
            // buffer sizes/geometries are not the host toplevel size. Letting subsurface
            // commits emit WindowSizeChanged can make host windows oscillate between
            // unrelated dimensions (seen as flicker with nested clients).
            let should_sync_host_window_size = direct_window_id.is_some();
            // Synchronize window dimensions with surface dimensions.
            //
            // When xdg_surface geometry is set, use the geometry width/height
            // so the platform window matches the content area (excluding the
            // CSD shadow).  Store the geometry origin so pointer coordinates
            // can be offset to surface-local coords.
            let mut size_changed = false;
            let (xdg_geometry, xdg_pending_serial, xdg_last_acked_serial) = self
                .xdg
                .surfaces
                .values()
                .find(|s| s.surface_id == id)
                .map(|s| (s.geometry, s.pending_serial, s.last_acked_serial))
                .unwrap_or((None, 0, 0));
            let (expected_toplevel_size, toplevel_pending_serial, toplevel_last_acked_serial) = self
                .xdg
                .toplevels
                .values()
                .find(|tl| tl.surface_id == id)
                .map(|tl| {
                    (
                        Some((tl.width as i32, tl.height as i32)),
                        tl.pending_serial,
                        tl.last_acked_serial,
                    )
                })
                .unwrap_or((None, 0, 0));
            if should_sync_host_window_size {
                if let Some(window) = self.get_window(wid) {
                    let mut window = window.write().unwrap();
                    let old_w = window.width;
                    let old_h = window.height;
                    let is_kiosk_window = Self::is_host_locked_window_flags(
                        wid,
                        window.host_locked,
                        self.ext.fullscreen_shell.presented_window_id,
                    );
                    let should_apply_window_geometry =
                        crate::core::wayland::xdg::decoration::should_crop_buffer_to_window_geometry(
                            self,
                            window.decoration_mode,
                        );
                    if is_kiosk_window {
                        if let Some(output) = self.outputs.get(self.primary_output) {
                            window.width = output.width as i32;
                            window.height = output.height as i32;
                        }
                        window.geometry_x = 0;
                        window.geometry_y = 0;
                    } else {
                        // Ignore client-driven size churn while a configure is still pending.
                        // This prevents host/client resize ping-pong loops with nested clients.
                        if xdg_pending_serial == 0 {
                            let mut target_width = surface.current.width;
                            let mut target_height = surface.current.height;
                            let mut target_geometry_x = 0;
                            let mut target_geometry_y = 0;

                            if should_apply_window_geometry {
                                let app_id = window.app_id.clone();
                                let decoration_mode = window.decoration_mode;
                                let buf_w = surface.current.width as i32;
                                let buf_h = surface.current.height as i32;
                                if let Some((inter_x1, inter_y1, inter_w, inter_h)) =
                                    crate::core::wayland::xdg::decoration::resolve_window_content_geometry(
                                        self,
                                        &app_id,
                                        decoration_mode,
                                        buf_w,
                                        buf_h,
                                        xdg_geometry,
                                    )
                                {
                                    target_width = inter_w;
                                    target_height = inter_h;
                                    target_geometry_x = inter_x1;
                                    target_geometry_y = inter_y1;
                                }
                            }

                            // Permanent size-authority state machine — see
                            // `core::window::size_authority`. Exactly one side
                            // may change agreed size; no host↔client ping-pong.
                            let decision = window.size_authority.clone().on_client_commit(
                                target_width,
                                target_height,
                                window.width,
                                window.height,
                                xdg_pending_serial,
                                window.has_committed_buffer,
                            );
                            crate::wlog_hot!(
                                crate::util::logging::STATE,
                                "SizeAuthority decision: window={} surf={} reason={} apply={} emit={} stretch={} pending_serial={} committed={}x{} current={}x{} auth_host={}",
                                wid,
                                id,
                                decision.reason,
                                decision.apply_client_size,
                                decision.emit_size_changed,
                                decision.stretch_present_to_host,
                                xdg_pending_serial,
                                target_width,
                                target_height,
                                window.width,
                                window.height,
                                decision.authority.is_host()
                            );

                            window.size_authority = decision.authority;
                            if decision.apply_client_size {
                                if decision.emit_size_changed
                                    || window.width != target_width
                                    || window.height != target_height
                                {
                                    size_changed = true;
                                }
                                window.width = target_width;
                                window.height = target_height;
                                window.geometry_x = target_geometry_x;
                                window.geometry_y = target_geometry_y;
                                window.has_committed_buffer = true;
                                // Placement ≠ sizing: center client-constrained
                                // surfaces in the output (flower/smoke 200×200).
                                if window.size_authority.is_client() {
                                    let (ow, oh) = self
                                        .outputs
                                        .get(self.primary_output)
                                        .map(|o| (o.width as i32, o.height as i32))
                                        .unwrap_or((0, 0));
                                    crate::core::window::apply_placement(
                                        &mut window,
                                        crate::core::window::PlacementPolicy::Center,
                                        ow,
                                        oh,
                                    );
                                }
                                for tl in self.xdg.toplevels.values_mut() {
                                    if tl.surface_id == id {
                                        tl.width = target_width.max(0) as u32;
                                        tl.height = target_height.max(0) as u32;
                                        break;
                                    }
                                }
                            } else {
                                crate::wlog!(
                                    crate::util::logging::STATE,
                                    "SizeAuthority hold: window={} reason={} committed={}x{} expected_toplevel={:?} pending_serial={} tl_pending_serial={}",
                                    wid,
                                    decision.reason,
                                    target_width,
                                    target_height,
                                    expected_toplevel_size,
                                    xdg_pending_serial,
                                    toplevel_pending_serial
                                );
                            }
                        } else {
                            crate::wlog!(
                                crate::util::logging::STATE,
                                "Deferring host sync due to pending configure: window={} surf={} pending_serial={} last_acked_serial={} tl_pending_serial={} tl_last_acked_serial={} committed={}x{} expected_toplevel={:?}",
                                wid,
                                id,
                                xdg_pending_serial,
                                xdg_last_acked_serial,
                                toplevel_pending_serial,
                                toplevel_last_acked_serial,
                                surface.current.width,
                                surface.current.height,
                                expected_toplevel_size
                            );
                        }
                    }
                    if window.width != old_w || window.height != old_h {
                        size_changed = true;
                    }
                }
            }

            // Notify the platform when the committed surface size differs from
            // the window size the platform created.  Fullscreen-shell windows
            // are excluded: their size is dictated by the output, not the
            // client buffer.
            if should_sync_host_window_size
                && size_changed
                && !self.is_host_locked_window(wid)
            {
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
        let key = (client_id.clone(), buffer_id);
        let mut retire_entry = false;
        if let Some(buffer) = self.buffers.get(&key) {
            let mut buffer = buffer.write().unwrap();
            buffer.release();
            retire_entry = buffer
                .resource
                .as_ref()
                .map(|res| !res.is_alive())
                .unwrap_or(true);
            tracing::debug!("Released buffer {}", buffer_id);
        }
        // Retire dead entries so repeated release attempts do not keep hitting
        // stale wl_buffer resources.
        if retire_entry {
            self.buffers.remove(&key);
        }
    }

    /// Remove a buffer
    pub fn remove_buffer(&mut self, client_id: ClientId, id: u32) {
        self.buffers.remove(&(client_id, id));
        tracing::debug!("Removed buffer {}", id);
    }
}
