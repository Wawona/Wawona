//! Window management, clipboard/DnD, and decoration methods.
//!
//! Contains `CompositorState` methods for window lifecycle, decoration
//! reconfiguration, clipboard selection, and drag-and-drop operations.

use wayland_server::protocol::wl_data_device_manager::DndAction;
use wayland_server::Resource;

use super::*;

impl CompositorState {
    /// Add a window (Legacy - delegating to register_window)
    pub fn add_window(&mut self, window: Window) -> u32 {
        let surface_id = window.surface_id;
        self.register_window(surface_id, window)
    }
    
    /// Remove a window (Delegating to destroy_window)
    pub fn remove_window(&mut self, window_id: u32) {
        self.destroy_window(window_id);
    }
    
    /// Get window for surface
    pub fn get_window_for_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Window>>> {
        self.get_window_by_surface(surface_id)
    }
    
    /// Re-configure a window to ensure it updates its decoration mode.
    pub fn reconfigure_window_decorations(&mut self, window_id: u32) {
        let target_toplevel = self
            .xdg
            .toplevels
            .iter()
            .find(|(_, tl)| tl.window_id == window_id)
            .map(|(key, _)| key.clone());

        if let Some((client_id, toplevel_id)) = target_toplevel {
            let (width, height) = if let Some(window) = self.windows.get(&window_id) {
                let window = window.read().unwrap();
                (window.width.max(0) as u32, window.height.max(0) as u32)
            } else {
                (0, 0)
            };
            let serial = self
                .send_toplevel_configure(client_id, toplevel_id, width, height)
                .unwrap_or(0);
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "Reconfigured decorations via unified configure gateway (window={} serial={} size={}x{})",
                window_id,
                serial,
                width,
                height
            );
        }
    }

    /// Sync xdg toplevel state when the native host enters or leaves fullscreen
    /// (macOS Mission Control space, not zoom/maximize).
    /// Returns the configure serial and requested size when a configure was
    /// sent, so the FFI layer can open a resize transaction for it.
    pub fn apply_host_window_fullscreen(
        &mut self,
        window_id: u32,
        fullscreen: bool,
        width: u32,
        height: u32,
    ) -> Option<(u32, u32, u32)> {
        let target_toplevel = self
            .xdg
            .toplevels
            .iter()
            .find(|(_, tl)| tl.window_id == window_id)
            .map(|(key, _)| key.clone());

        let Some((client_id, toplevel_id)) = target_toplevel else {
            return None;
        };

        // Idempotence guard: host fullscreen notifications can arrive more
        // than once for the same transition (delegate callback + settled
        // resize). Re-applying an identical state would send a redundant
        // configure and open a new transaction, feeding back into the host.
        let current = self.get_window(window_id).map(|window| {
            let window = window.read().unwrap();
            (window.fullscreen, window.width, window.height)
        });
        if let Some((cur_fs, cur_w, cur_h)) = current {
            if cur_fs == fullscreen
                && (!fullscreen || (cur_w == width as i32 && cur_h == height as i32))
            {
                return None;
            }
        }

        if fullscreen {
            if let Some(geo) = self.get_window(window_id).map(|window| {
                let window = window.read().unwrap();
                (window.x, window.y, window.width as u32, window.height as u32)
            }) {
                if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    if tl.saved_geometry.is_none() {
                        tl.saved_geometry = Some(geo);
                    }
                    tl.pending_fullscreen = true;
                    tl.pending_maximized = false;
                }
            }
            if let Some(window) = self.get_window(window_id) {
                let mut window = window.write().unwrap();
                window.fullscreen = true;
                window.maximized = false;
                window.width = width as i32;
                window.height = height as i32;
            }
            let fw = width.max(1);
            let fh = height.max(1);
            self.send_toplevel_configure(client_id, toplevel_id, fw, fh)
                .map(|serial| (serial, fw, fh))
        } else {
            let saved = self
                .xdg
                .toplevels
                .get_mut(&(client_id.clone(), toplevel_id))
                .and_then(|tl| {
                    tl.pending_fullscreen = false;
                    tl.saved_geometry.take()
                });
            let (restore_w, restore_h) = if let Some((_x, _y, w, h)) = saved {
                (w, h)
            } else {
                (width.max(1), height.max(1))
            };
            if let Some(window) = self.get_window(window_id) {
                let mut window = window.write().unwrap();
                window.fullscreen = false;
                window.width = restore_w as i32;
                window.height = restore_h as i32;
            }
            self.send_toplevel_configure(client_id, toplevel_id, restore_w, restore_h)
                .map(|serial| (serial, restore_w, restore_h))
        }
    }

    /// Sync xdg toplevel maximize state when the native host zooms (macOS) or
    /// unzooms. Fullscreen and maximize are mutually exclusive in xdg state.
    ///
    /// Returns the configure serial and requested size when a configure was
    /// sent, so the FFI layer can open a resize transaction for it.
    pub fn apply_host_window_maximized(
        &mut self,
        window_id: u32,
        maximized: bool,
        width: u32,
        height: u32,
    ) -> Option<(u32, u32, u32)> {
        let target_toplevel = self
            .xdg
            .toplevels
            .iter()
            .find(|(_, tl)| tl.window_id == window_id)
            .map(|(key, _)| key.clone());

        let Some((client_id, toplevel_id)) = target_toplevel else {
            return None;
        };

        // Idempotence guard: skip re-applying an identical maximize state so
        // host zoom notifications never echo back extra configures.
        let current = self.get_window(window_id).map(|window| {
            let window = window.read().unwrap();
            (window.maximized, window.width, window.height)
        });
        if let Some((cur_max, cur_w, cur_h)) = current {
            if cur_max == maximized
                && (!maximized || (cur_w == width as i32 && cur_h == height as i32))
            {
                return None;
            }
        }

        if maximized {
            if let Some(geo) = self.get_window(window_id).map(|window| {
                let window = window.read().unwrap();
                (window.x, window.y, window.width as u32, window.height as u32)
            }) {
                if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    if tl.saved_geometry.is_none() {
                        tl.saved_geometry = Some(geo);
                    }
                    tl.pending_maximized = true;
                    tl.pending_fullscreen = false;
                }
            }
            if let Some(window) = self.get_window(window_id) {
                let mut window = window.write().unwrap();
                window.maximized = true;
                window.fullscreen = false;
                window.width = width as i32;
                window.height = height as i32;
            }
            let (cw, ch) = self
                .xdg
                .toplevels
                .get(&(client_id.clone(), toplevel_id))
                .map(|tl| tl.clamp_size(width.max(1), height.max(1)))
                .unwrap_or((width.max(1), height.max(1)));
            self.send_toplevel_configure(client_id, toplevel_id, cw, ch)
                .map(|serial| (serial, cw, ch))
        } else {
            let saved = self
                .xdg
                .toplevels
                .get_mut(&(client_id.clone(), toplevel_id))
                .and_then(|tl| {
                    tl.pending_maximized = false;
                    tl.saved_geometry.take()
                });
            let (restore_w, restore_h) = if let Some((_x, _y, w, h)) = saved {
                (w, h)
            } else {
                (width.max(1), height.max(1))
            };
            if let Some(window) = self.get_window(window_id) {
                let mut window = window.write().unwrap();
                window.maximized = false;
                window.width = restore_w as i32;
                window.height = restore_h as i32;
            }
            self.send_toplevel_configure(client_id, toplevel_id, restore_w, restore_h)
                .map(|serial| (serial, restore_w, restore_h))
        }
    }

    /// Register a new window for a surface
    pub fn register_window(&mut self, surface_id: u32, window: Window) -> u32 {
        let window_id = window.id;
        self.windows.insert(window_id, Arc::new(RwLock::new(window)));
        self.surface_to_window.insert(surface_id, window_id);
        self.window_tree.insert(window_id);
        
        self.focus.set_keyboard_focus(Some(window_id));
        if let Some(old_focus_wid) = self.focus.pointer_focus {
            if let Some(old_window) = self.windows.get(&old_focus_wid) {
                let (sid, cid) = {
                    let w = old_window.read().unwrap();
                    let sid = w.surface_id;
                    let cid = self.get_surface(sid).and_then(|s| s.read().unwrap().client_id.clone());
                    (sid, cid)
                };
                if let Some(cid) = cid {
                    self.ext.pointer_constraints.deactivate_constraints(cid, sid);
                }
            }
        }
        self.focus.set_pointer_focus(Some(window_id));
        
        if let Some(pending_wid) = self.pending_keyboard_focus_window.take() {
            if pending_wid == window_id as u64 {
                let serial = self.next_serial();
                if let Some(surface) = self.surfaces.get(&surface_id).cloned() {
                    let surface = surface.read().unwrap();
                    if let Some(res) = &surface.resource {
                        crate::wlog!(
                            crate::util::logging::COMPOSITOR,
                            "Delivering deferred keyboard enter to window {} surface {}",
                            window_id,
                            surface_id
                        );
                        self.seat.keyboard.focus = Some(surface_id);
                        if let Some(keyboard) = self
                            .smithay_runtime
                            .seat
                            .as_ref()
                            .and_then(|seat| seat.get_keyboard())
                        {
                            keyboard.set_focus(self, Some(res.clone()), serial.into());
                        } else {
                            self.seat.broadcast_keyboard_enter(serial, res, &[]);
                        }
                        self.ext.text_input.enter(res, Some(surface_id));
                    }
                }
            } else {
                self.pending_keyboard_focus_window = Some(pending_wid);
            }
        }
        
        let client_id = self.get_surface(surface_id).and_then(|s| s.read().unwrap().client_id.clone());
        if let Some(cid) = client_id {
            self.ext.pointer_constraints.activate_constraints(cid, surface_id);
        }
        self.window_tree.bring_to_front(window_id);
        
        tracing::info!("Registered window {} for surface {}", window_id, surface_id);
        window_id
    }

    /// Get a window by ID
    pub fn get_window(&self, window_id: u32) -> Option<Arc<RwLock<Window>>> {
        self.windows.get(&window_id).cloned()
    }
    
    /// Get a window by Surface ID
    pub fn get_window_by_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Window>>> {
        let wid = self.surface_to_window.get(&surface_id)?;
        self.get_window(*wid)
    }

    /// Destroy a window
    pub fn destroy_window(&mut self, window_id: u32) {
        if let Some(window) = self.windows.remove(&window_id) {
            let surface_id = match window.read() {
                Ok(w) => w.surface_id,
                Err(_) => {
                    tracing::error!(
                        "destroy_window: poisoned window lock for window {}, skipping teardown",
                        window_id
                    );
                    return;
                }
            };
            self.surface_to_window.remove(&surface_id);
            self.window_tree.remove(window_id);

            if self.ext.fullscreen_shell.presented_window_id == Some(window_id) {
                self.ext.fullscreen_shell.presented_window_id = None;
                self.ext.fullscreen_shell.presented_surface = None;
            }
            
            if self.focus.has_keyboard_focus(window_id) {
                let next = self.focus.focus_history.first().copied();
                self.focus.set_keyboard_focus(next);
            }
            if let Some(old_focus_wid) = self.focus.pointer_focus {
                if old_focus_wid == window_id {
                    let (sid, cid) = {
                        let sid = match window.read() {
                            Ok(w) => w.surface_id, // window removed from map, Arc still valid
                            Err(_) => {
                                tracing::warn!(
                                    "destroy_window: poisoned window lock while clearing pointer focus for {}",
                                    window_id
                                );
                                0
                            }
                        };
                        let cid = self.get_surface(sid).and_then(|s| {
                            s.read()
                                .ok()
                                .and_then(|surf| surf.client_id.clone())
                        });
                        (sid, cid)
                    };
                    if sid != 0 {
                        if let Some(cid) = cid {
                        self.ext.pointer_constraints.deactivate_constraints(cid, sid);
                        }
                    }
                    self.focus.set_pointer_focus(None);
                }
            }
            
            tracing::info!("Destroyed window {}", window_id);

            crate::core::wayland::wlr::foreign_toplevel_management::notify_toplevel_destroyed(
                self, window_id,
            );
            
            self.pending_compositor_events.push(crate::core::compositor::CompositorEvent::WindowDestroyed {
                window_id,
            });
        }
    }

    // =========================================================================
    // Clipboard
    // =========================================================================
    //
    // wl_data_device clipboard and drag-and-drop are owned entirely by
    // Smithay (DataDeviceState + delegate_data_device + SeatHandler::
    // focus_changed). The only compositor-side selection bookkeeping left is
    // the wlr-data-control bridge below.

    /// Record the clipboard source set by a zwlr_data_control client so
    /// offer.receive can be forwarded to it.
    pub fn set_clipboard_source(&mut self, source: Option<SelectionSource>) {
        tracing::debug!("Clipboard source set to: {:?}", source);
        self.seat.current_selection = source;
    }

    // =========================================================================
    // DMABUF Export Management
    // =========================================================================

    /// Add a DMABUF export frame
    pub fn add_dmabuf_export_frame(&mut self, resource_id: u32, frame: DmabufExportFrame) {
        self.wlr.export_dmabuf.frames.insert(resource_id, frame);
        tracing::debug!("Added DMABUF export frame for resource {}", resource_id);
    }

    /// Remove a DMABUF export frame
    pub fn remove_dmabuf_export_frame(&mut self, resource_id: u32) {
        self.wlr.export_dmabuf.frames.remove(&resource_id);
        tracing::debug!("Removed DMABUF export frame for resource {}", resource_id);
    }

    // =========================================================================
    // Virtual Pointer Management
    // =========================================================================

    /// Add a virtual pointer
    pub fn add_virtual_pointer(&mut self, client_id: ClientId, resource_id: u32, pointer: VirtualPointerState) {
        self.wlr.virtual_pointers.insert((client_id, resource_id), pointer);
        tracing::debug!("Added virtual pointer device for resource {}", resource_id);
    }

    /// Remove a virtual pointer
    pub fn remove_virtual_pointer(&mut self, client_id: ClientId, resource_id: u32) {
        self.wlr.virtual_pointers.remove(&(client_id, resource_id));
        tracing::debug!("Removed virtual pointer device for resource {}", resource_id);
    }

    // =========================================================================
    // Virtual Keyboard Management
    // =========================================================================

    /// Add a virtual keyboard
    pub fn add_virtual_keyboard(&mut self, client_id: ClientId, resource_id: u32, keyboard: VirtualKeyboardState) {
        self.wlr.virtual_keyboards.insert((client_id, resource_id), keyboard);
        tracing::debug!("Added virtual keyboard device for resource {}", resource_id);
    }

    /// Remove a virtual keyboard
    pub fn remove_virtual_keyboard(&mut self, client_id: ClientId, resource_id: u32) {
        self.wlr.virtual_keyboards.remove(&(client_id, resource_id));
        tracing::debug!("Removed virtual keyboard device for resource {}", resource_id);
    }

    // =========================================================================
    // Presentation Time
    // =========================================================================
    
    /// Get next presentation sequence number
    pub fn next_presentation_seq(&mut self) -> u64 {
        let seq = self.ext.presentation.next_seq;
        self.ext.presentation.next_seq = self.ext.presentation.next_seq.wrapping_add(1);
        seq
    }

    // =========================================================================
    // Output Management
    // =========================================================================

    /// Update output configuration and notify all bound clients.
    pub fn update_output_configuration(
        &mut self,
        output_id: u32,
        width: Option<u32>,
        height: Option<u32>,
        refresh: Option<u32>,
        scale: Option<f32>,
        x: Option<i32>,
        y: Option<i32>,
    ) -> bool {
        let idx = match self.outputs.iter().position(|o| o.id == output_id) {
            Some(i) => i,
            None => return false,
        };

        let mut changed = false;
        {
            let output = &mut self.outputs[idx];
            if let Some(w) = width {
                if output.width != w { output.width = w; changed = true; }
            }
            if let Some(h) = height {
                if output.height != h { output.height = h; changed = true; }
            }
            if let Some(r) = refresh {
                if output.refresh != r { output.refresh = r; changed = true; }
            }
            if let Some(s) = scale {
                if (output.scale - s).abs() > 0.001 { output.scale = s; changed = true; }
            }
            if let Some(px) = x {
                if output.x != px { output.x = px; changed = true; }
            }
            if let Some(py) = y {
                if output.y != py { output.y = py; changed = true; }
            }

            if changed {
                if let Some(mode) = output.modes.iter_mut().find(|m| m.preferred) {
                    mode.width = output.width;
                    mode.height = output.height;
                    mode.refresh = output.refresh;
                }
                output.usable_area = crate::util::geometry::Rect::new(
                    output.x, output.y, output.width, output.height
                );
                tracing::info!(
                    "Output {} updated: {}x{} @ {}mHz, scale {}",
                    output_id, output.width, output.height, output.refresh, output.scale
                );
            }
        }

        if changed {
            crate::core::wayland::wayland::output::notify_output_change(self, output_id);
        }

        true
    }
    
    // =========================================================================
    // Idle Inhibition
    // =========================================================================
    
    // =========================================================================
    // Layer Surface Management
    // =========================================================================
    
    /// Add a layer surface
    pub fn add_layer_surface(&mut self, client_id: ClientId, surface: LayerSurface) -> u32 {
        let id = surface.surface_id;
        self.wlr.layer_surfaces.insert((client_id.clone(), id), Arc::new(RwLock::new(surface)));
        tracing::debug!("Added layer surface {}", id);
        id
    }
    
    /// Remove a layer surface
    pub fn remove_layer_surface(&mut self, client_id: ClientId, surface_id: u32) {
        self.wlr.layer_surfaces.remove(&(client_id, surface_id));
        tracing::debug!("Removed layer surface {}", surface_id);
    }
    
    /// Get a layer surface
    pub fn get_layer_surface(&self, client_id: ClientId, surface_id: u32) -> Option<Arc<RwLock<LayerSurface>>> {
        self.wlr.layer_surfaces.get(&(client_id, surface_id)).cloned()
    }
    
    /// Get all layer surfaces for an output
    pub fn layer_surfaces_for_output(&self, output_id: u32) -> Vec<Arc<RwLock<LayerSurface>>> {
        self.wlr.layer_surfaces.values()
            .filter(|ls| ls.read().unwrap().output_id == output_id)
            .cloned()
            .collect()
    }
}
