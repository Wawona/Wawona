//! Input injection and processing for the compositor.
//!
//! Contains all `CompositorState` methods related to keyboard, pointer,
//! touch input injection and the high-level `process_input_event` dispatcher.

use super::*;
use wayland_server::protocol::{wl_keyboard, wl_pointer};
use wayland_server::Resource;

impl CompositorState {
    // =========================================================================
    // Input Injection
    // =========================================================================

    /// Inject a key event and broadcast to all bound keyboards
    pub fn inject_key(&mut self, key: u32, key_state: wl_keyboard::KeyState, time: u32) {
        self.ext.idle_notify.record_activity();
        let mut new_mods = None;
        
        if let Some(state) = &self.seat.keyboard.xkb_state {
             if let Ok(mut state) = state.lock() {
                 let direction = match key_state {
                     wl_keyboard::KeyState::Pressed => xkbcommon::xkb::KeyDirection::Down,
                     wl_keyboard::KeyState::Released => xkbcommon::xkb::KeyDirection::Up,
                     _ => xkbcommon::xkb::KeyDirection::Up,
                 };
                 if state.update_key(key, direction) {
                     new_mods = Some(state.serialize_modifiers());
                 }
             }
        }

        if let Some((depressed, latched, locked, group)) = new_mods {
            self.seat.keyboard.mods_depressed = depressed;
            self.seat.keyboard.mods_latched = latched;
            self.seat.keyboard.mods_locked = locked;
            self.seat.keyboard.mods_group = group;
        }

        let serial = self.next_serial();
        self.seat.cleanup_resources();
        for keyboard in &self.seat.keyboard.resources {
            keyboard.key(serial, time, key, key_state);
            if let Some((depressed, latched, locked, group)) = new_mods {
                keyboard.modifiers(serial, depressed, latched, locked, group);
            }
        }
    }

    /// Inject modifier state and broadcast to all bound keyboards
    pub fn inject_modifiers(&mut self, depressed: u32, latched: u32, locked: u32, group: u32) {
        if let Some(state) = &self.seat.keyboard.xkb_state {
             if let Ok(mut state) = state.lock() {
                 state.update_mask(depressed, latched, locked, group);
             }
        }
        
        self.seat.keyboard.mods_depressed = depressed;
        self.seat.keyboard.mods_latched = latched;
        self.seat.keyboard.mods_locked = locked;
        self.seat.keyboard.mods_group = group;

        let serial = self.next_serial();
        self.seat.cleanup_resources();
        for keyboard in &self.seat.keyboard.resources {
            keyboard.modifiers(serial, depressed, latched, locked, group);
        }
    }

    /// Inject relative pointer motion and broadcast to all bound pointers
    pub fn inject_pointer_motion_relative(&mut self, dx: f64, dy: f64, time: u32) {
        self.seat.pointer.x += dx;
        self.seat.pointer.y += dy;

        self.ext.relative_pointers.broadcast_relative_motion(0, 0, time, dx, dy, dx, dy);

        if let Some(surface_id) = self.seat.pointer.focus {
            let client_id = self.surfaces.get(&surface_id).and_then(|s| s.read().unwrap().client_id.clone());
            if let Some(cid) = client_id {
                if self.ext.pointer_constraints.is_pointer_locked(cid, surface_id) {
                    return;
                }
            }
        }

        self.seat.cleanup_resources();
        let x = self.seat.pointer.x;
        let y = self.seat.pointer.y;
        for pointer in &self.seat.pointer.resources {
            pointer.motion(time, x, y);
        }
    }

    /// Find the surface at the given absolute coordinates.
    /// Phase E: Respects subsurface input region clipping — a point is only accepted
    /// if it lies within the surface's input_region (None = whole surface).
    pub fn find_surface_at(&mut self, x: f64, y: f64) -> Option<(u32, f64, f64)> {
        self.build_scene();
        let flattened = self.scene.flatten();
        
        for surface in flattened.iter().rev() {
            let sx = surface.x as f64;
            let sy = surface.y as f64;
            let sw = surface.width as f64;
            let sh = surface.height as f64;
            
            if x >= sx && x < sx + sw && y >= sy && y < sy + sh {
                let local_x = (x - sx) / surface.scale as f64;
                let local_y = (y - sy) / surface.scale as f64;
                let lx = local_x as i32;
                let ly = local_y as i32;
                
                if let Some(surf) = self.surfaces.get(&surface.surface_id) {
                    let guard = surf.read().unwrap();
                    if let Some(regions) = &guard.current.input_region {
                        let inside = regions.iter().any(|r| r.contains_point(lx, ly));
                        if !inside {
                            continue;
                        }
                    }
                }
                return Some((surface.surface_id, local_x, local_y));
            }
        }
        
        None
    }

    /// Inject absolute pointer motion and broadcast to all bound pointers.
    /// During an active drag, sends wl_data_device enter/leave/motion instead.
    pub fn inject_pointer_motion_absolute(&mut self, x: f64, y: f64, time: u32) {
        self.ext.idle_notify.record_activity();
        self.seat.pointer.x = x;
        self.seat.pointer.y = y;
        self.seat.cleanup_resources();
        
        let picking_res = self.find_surface_at(x, y);
        let old_focus = self.seat.pointer.focus;

        if self.data.drag.is_some() {
            let new_surface_id = picking_res.as_ref().map(|(sid, _, _)| *sid);
            let drag_focus = self.data.drag.as_ref().unwrap().focus_surface_id;

            if drag_focus != new_surface_id {
                if drag_focus.is_some() {
                    for device_data in self.data.devices.values() {
                        if device_data.resource.is_alive() {
                            device_data.resource.leave();
                        }
                    }
                }

                if let Some((sid, lx, ly)) = &picking_res {
                    if let Some(surface) = self.get_surface(*sid) {
                        let surface = surface.read().unwrap();
                        if let Some(res) = &surface.resource {
                            let serial = self.next_serial();
                            self.seat.pointer.last_enter_serial = serial;
                            let mut active_offer = None;
                            for device_data in self.data.devices.values() {
                                if device_data.resource.is_alive()
                                    && device_data.resource.client() == res.client()
                                {
                                    let offer = self
                                        .data
                                        .drag
                                        .as_ref()
                                        .and_then(|drag| drag.offer_by_device.get(&device_data.resource.id().protocol_id()))
                                        .and_then(|offer_id| self.data.offers.get(offer_id))
                                        .and_then(|offer_data| offer_data.resource.as_ref());
                                    if let Some(offer) = offer {
                                        active_offer = Some(offer.id().protocol_id());
                                    }
                                    device_data.resource.enter(serial, res, *lx, *ly, offer);
                                }
                            }
                            if let Some(drag) = &mut self.data.drag {
                                drag.current_offer_id = active_offer;
                            }
                        }
                    }
                }

                if let Some(drag) = &mut self.data.drag {
                    drag.focus_surface_id = new_surface_id;
                }
            } else if let Some((_sid, lx, ly)) = &picking_res {
                for device_data in self.data.devices.values() {
                    if device_data.resource.is_alive() {
                        device_data.resource.motion(time, *lx, *ly);
                    }
                }
            }

            if let Some(attachment) = &self.xdg.toplevel_drag.active {
                if let Some(wid) = attachment.window_id {
                    let new_x = x as i32 + attachment.x_offset;
                    let new_y = y as i32 + attachment.y_offset;
                    if let Some(window) = self.get_window(wid) {
                        let mut window = window.write().unwrap();
                        window.x = new_x;
                        window.y = new_y;
                    }
                }
            }

            return;
        }

        if let Some((surface_id, lx, ly)) = picking_res {
            if Some(surface_id) != old_focus {
                if let Some(old_id) = old_focus {
                    let old_client_id = self
                        .surfaces
                        .get(&old_id)
                        .and_then(|s| s.read().unwrap().client_id.clone());
                    if let Some(cid) = old_client_id {
                        self.ext.pointer_constraints.deactivate_constraints(cid, old_id);
                    }
                }
                if let Some(old_id) = old_focus {
                    if let Some(surface) = self.get_surface(old_id) {
                        let surface = surface.read().unwrap();
                        if let Some(res) = &surface.resource {
                            let serial = self.next_serial();
                            for pointer in &self.seat.pointer.resources {
                                pointer.leave(serial, res);
                            }
                        }
                    }
                }
                
                if let Some(surface) = self.get_surface(surface_id) {
                    let surface = surface.read().unwrap();
                    if let Some(res) = &surface.resource {
                        let serial = self.next_serial();
                            self.seat.pointer.last_enter_serial = serial;
                        for pointer in &self.seat.pointer.resources {
                            pointer.enter(serial, res, lx, ly);
                        }
                    }
                }
                self.seat.pointer.focus = Some(surface_id);
                self.focus.set_pointer_focus(self.surface_to_window.get(&surface_id).copied());
                let new_client_id = self
                    .surfaces
                    .get(&surface_id)
                    .and_then(|s| s.read().unwrap().client_id.clone());
                if let Some(cid) = new_client_id {
                    self.ext.pointer_constraints.activate_constraints(cid, surface_id);
                }
            }
            
            for pointer in &self.seat.pointer.resources {
                pointer.motion(time, lx, ly);
            }
        } else {
             if let Some(old_id) = old_focus {
                let old_client_id = self
                    .surfaces
                    .get(&old_id)
                    .and_then(|s| s.read().unwrap().client_id.clone());
                if let Some(cid) = old_client_id {
                    self.ext.pointer_constraints.deactivate_constraints(cid, old_id);
                }
                if let Some(surface) = self.get_surface(old_id) {
                    let surface = surface.read().unwrap();
                    if let Some(res) = &surface.resource {
                        let serial = self.next_serial();
                        for pointer in &self.seat.pointer.resources {
                            pointer.leave(serial, res);
                        }
                    }
                }
            }
            self.seat.pointer.focus = None;
            self.focus.set_pointer_focus(None);
        }
    }

    /// Inject a pointer button event and broadcast to all bound pointers.
    pub fn inject_pointer_button(&mut self, button: u32, state: wl_pointer::ButtonState, time: u32) {
        self.ext.idle_notify.record_activity();
        let serial = self.next_serial();
        self.seat.pointer.last_button_serial = serial;
        self.seat.cleanup_resources();
        
        if state == wl_pointer::ButtonState::Pressed {
            self.seat.pointer.button_count += 1;
            
            if !self.seat.popup_grab_stack.is_empty() {
                let mut on_grab_tree = false;
                if let Some(focus_id) = self.seat.pointer.focus {
                    for &(ref cid, popup_id) in &self.seat.popup_grab_stack {
                        if let Some(popup) = self.xdg.popups.get(&(cid.clone(), popup_id)) {
                            if popup.surface_id == focus_id {
                                on_grab_tree = true;
                                break;
                            }
                            if let Some(&wid) = self.surface_to_window.get(&focus_id) {
                                if wid == popup.window_id {
                                    on_grab_tree = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                
                if !on_grab_tree {
                    self.dismiss_popup_grab();
                }
            }
        } else {
            self.seat.pointer.button_count = self.seat.pointer.button_count.saturating_sub(1);

            if self.seat.pointer.button_count == 0 && self.data.drag.is_some() {
                let has_focus = self.data.drag.as_ref().unwrap().focus_surface_id.is_some();
                self.end_drag(has_focus);
                return;
            }
        }

        if self.data.drag.is_some() {
            return;
        }

        for pointer in &self.seat.pointer.resources {
            pointer.button(serial, time, button, state);
        }
    }

    /// Flush pending pointer events (send frame event)
    pub fn flush_pointer_events(&mut self) {
        self.seat.cleanup_resources();
        let client = self.focused_pointer_client();
        self.seat.broadcast_pointer_frame(client.as_ref());
    }

    /// Look up a surface's absolute position in the scene graph.
    fn surface_position_in_scene(&mut self, surface_id: u32) -> Option<(i32, i32, f32)> {
        self.build_scene();
        let flattened = self.scene.flatten();
        for node in &flattened {
            if node.surface_id == surface_id {
                return Some((node.x, node.y, node.scale));
            }
        }
        None
    }

    /// Inject touch down event.
    /// Performs surface hit-testing at (x, y) to find the target surface,
    /// records the touch point, sets keyboard focus, and sends wl_touch.down.
    pub fn inject_touch_down(&mut self, id: i32, x: f64, y: f64, time: u32) {
        self.ext.idle_notify.record_activity();
        self.seat.cleanup_resources();

        let picking = self.find_surface_at(x, y);
        if let Some((surface_id, local_x, local_y)) = picking {
            self.seat.touch.touch_down(id, surface_id, local_x, local_y);

            if let Some(&window_id) = self.surface_to_window.get(&surface_id) {
                self.set_focused_window(Some(window_id));
                self.window_tree.bring_to_front(window_id);
            }

            let serial = self.next_serial();
            if let Some(surface) = self.surfaces.get(&surface_id).cloned() {
                let surface = surface.read().unwrap();
                if let Some(res) = &surface.resource {
                    self.seat.broadcast_touch_down(serial, time, res, id, local_x, local_y);
                    let client = res.client();
                    self.seat.broadcast_touch_frame(client.as_ref());
                }
            }
        }
    }

    /// Inject touch up event.
    /// Looks up the target surface from the active touch state (not pointer focus).
    pub fn inject_touch_up(&mut self, id: i32, time: u32) {
        self.seat.cleanup_resources();

        let client = self.seat.touch.get_touch_surface(id).and_then(|sid| {
            self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|r| r.client())
            })
        });

        let serial = self.next_serial();
        self.seat.broadcast_touch_up(serial, time, id, client.as_ref());
        self.seat.touch.touch_up(id);
        self.seat.broadcast_touch_frame(client.as_ref());
    }

    /// Inject touch motion event.
    /// Computes surface-local coordinates from the scene graph for the
    /// surface that originally received the touch-down.
    pub fn inject_touch_motion(&mut self, id: i32, x: f64, y: f64, time: u32) {
        self.seat.cleanup_resources();

        let surface_id = self.seat.touch.get_touch_surface(id);
        if let Some(sid) = surface_id {
            let pos = self.surface_position_in_scene(sid);
            if let Some((sx, sy, scale)) = pos {
                let local_x = (x - sx as f64) / scale as f64;
                let local_y = (y - sy as f64) / scale as f64;

                self.seat.touch.touch_motion(id, local_x, local_y);

                let client = self.surfaces.get(&sid).and_then(|surf| {
                    surf.read().unwrap().resource.as_ref().and_then(|r| r.client())
                });
                self.seat.broadcast_touch_motion(time, id, local_x, local_y, client.as_ref());
                self.seat.broadcast_touch_frame(client.as_ref());
            }
        }
    }

    /// Inject touch frame event.
    /// Sends frame to all clients that have active touch points.
    pub fn inject_touch_frame(&mut self) {
        self.seat.cleanup_resources();
        let surface_ids: Vec<u32> = self.seat.touch.active_points.values()
            .map(|p| p.surface_id)
            .collect();
        let mut seen = std::collections::HashSet::new();
        for sid in surface_ids {
            let client = self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|r| r.client())
            });
            if let Some(ref c) = client {
                if seen.insert(c.id()) {
                    self.seat.broadcast_touch_frame(client.as_ref());
                }
            }
        }
    }

    /// Inject touch cancel event.
    /// Sends cancel to all clients with active touch points, then clears state.
    pub fn inject_touch_cancel(&mut self) {
        self.seat.cleanup_resources();
        let surface_ids: Vec<u32> = self.seat.touch.active_points.values()
            .map(|p| p.surface_id)
            .collect();
        let mut seen = std::collections::HashSet::new();
        for sid in &surface_ids {
            let client = self.surfaces.get(sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|r| r.client())
            });
            if let Some(ref c) = client {
                if seen.insert(c.id()) {
                    self.seat.broadcast_touch_cancel(client.as_ref());
                }
            }
        }
        self.seat.touch.touch_cancel();
    }

    // =========================================================================
    // Focus Management
    // =========================================================================
    
    /// Set focused window
    pub fn set_focused_window(&mut self, window_id: Option<u32>) {
        self.focus.set_keyboard_focus(window_id);
        
        if let Some(wid) = window_id {
            if let Some(window) = self.windows.get(&wid) {
                let window = window.read().unwrap();
                self.seat.keyboard.focus = Some(window.surface_id);
            }
        } else {
            self.seat.keyboard.focus = None;
        }
        
        tracing::debug!("Focus changed to window: {:?}", window_id);
    }

    /// Get the client of the currently focused keyboard surface
    pub fn focused_keyboard_client(&self) -> Option<wayland_server::Client> {
        self.seat.keyboard.focus.and_then(|sid| {
            self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
            })
        })
    }

    /// Get the client of the currently focused pointer surface
    pub fn focused_pointer_client(&self) -> Option<wayland_server::Client> {
        self.seat.pointer.focus.and_then(|sid| {
            self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
            })
        })
    }
    
    /// Get focused window
    pub fn focused_window(&self) -> Option<u32> {
        self.focus.keyboard_focus
    }

    // =========================================================================
    // Input Processing
    // =========================================================================

    /// Process a raw input event from the platform/FFI
    pub fn process_input_event(&mut self, event: crate::core::input::InputEvent) {
        use crate::core::input::InputEvent;
        use wayland_server::protocol::wl_pointer::ButtonState;
        use wayland_server::protocol::wl_keyboard::KeyState;

        match event {
            InputEvent::TouchDown { id, x, y, time_ms } => {
                self.inject_touch_down(id, x, y, time_ms);
            }
            InputEvent::TouchUp { id, time_ms } => {
                self.inject_touch_up(id, time_ms);
            }
            InputEvent::TouchMotion { id, x, y, time_ms } => {
                self.inject_touch_motion(id, x, y, time_ms);
            }
            InputEvent::TouchFrame => {
                self.inject_touch_frame();
            }
            InputEvent::TouchCancel => {
                self.inject_touch_cancel();
            }
            InputEvent::PointerMotion { x, y, time_ms } => {
                self.seat.pointer.x = x;
                self.seat.pointer.y = y;

                let window_info = {
                     let under = self.window_tree.window_under(x, y, &self.windows);
                     if let Some(wid) = under {
                         if let Some(window) = self.windows.get(&wid) {
                             let w = window.read().unwrap();
                             Some((wid, w.surface_id, w.geometry()))
                         } else {
                             None
                         }
                     } else {
                         None
                     }
                };
                
                if let Some((_window_id, surface_id, win_geo)) = window_info {
                        if self.seat.pointer.focus != Some(surface_id) {
                            if let Some(old_focus) = self.seat.pointer.focus {
                                let old_resource = if let Some(surf) = self.surfaces.get(&old_focus) {
                                     let surf = surf.read().unwrap();
                                     surf.resource.clone()
                                } else {
                                    None
                                };

                                if let Some(res) = old_resource {
                                    self.serial += 1;
                                    let serial = self.serial;
                                    self.seat.broadcast_pointer_leave(serial, &res);
                                }
                            }
                            
                            let new_resource = if let Some(surf) = self.surfaces.get(&surface_id) {
                                let surf = surf.read().unwrap();
                                surf.resource.clone()
                            } else {
                                None
                            };

                            if let Some(res) = new_resource {
                                let lx = x - win_geo.x as f64;
                                let ly = y - win_geo.y as f64;
                                
                                self.serial += 1;
                                let serial = self.serial;
                                self.seat.pointer.last_enter_serial = serial;
                                self.seat.broadcast_pointer_enter(serial, &res, lx, ly);
                            }
                            
                            self.seat.pointer.focus = Some(surface_id);
                        }
                        
                         let dx = x - self.seat.pointer.x;
                         let dy = y - self.seat.pointer.y;
                         self.ext.relative_pointers.broadcast_relative_motion(0, 0, time_ms, dx, dy, dx, dy);

                        self.seat.pointer.x = x;
                        self.seat.pointer.y = y;

                        let client_id = self.surfaces.get(&surface_id).and_then(|s| s.read().unwrap().client_id.clone());
                        let locked = if let Some(cid) = client_id {
                             self.ext.pointer_constraints.is_pointer_locked(cid, surface_id)
                        } else {
                             false
                        };
                        if !locked {
                             let lx = x - win_geo.x as f64;
                             let ly = y - win_geo.y as f64;
                             
                             let client = if let Some(sid) = self.seat.pointer.focus {
                                if let Some(surf) = self.surfaces.get(&sid) {
                                    surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                                } else {
                                    None
                                }
                             } else {
                                 None
                             };
                             
                             self.seat.broadcast_pointer_motion(time_ms, lx, ly, client.as_ref());
                        }

                } else {
                     if let Some(old_focus) = self.seat.pointer.focus {
                        let old_resource = if let Some(surf) = self.surfaces.get(&old_focus) {
                             let surf = surf.read().unwrap();
                             surf.resource.clone()
                        } else {
                            None
                        };

                        if let Some(res) = old_resource {
                             self.serial += 1;
                             let serial = self.serial;
                             self.seat.broadcast_pointer_leave(serial, &res);
                        }
                    }
                    self.seat.pointer.focus = None;
                }
            }
            InputEvent::PointerButton { button, state, time_ms } => {
                let wl_state = if state == crate::core::input::KeyState::Pressed {
                    ButtonState::Pressed
                } else {
                    ButtonState::Released
                };
                
                if wl_state == ButtonState::Pressed {
                    let window_under = self.window_tree.window_under(self.seat.pointer.x, self.seat.pointer.y, &self.windows);
                    if let Some(window_id) = window_under {
                        self.set_focused_window(Some(window_id));
                        self.window_tree.bring_to_front(window_id);
                    }
                }

                let client = if let Some(sid) = self.seat.pointer.focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.pointer.last_button_serial = serial;
                self.seat.broadcast_pointer_button(serial, time_ms, button, wl_state, client.as_ref());
            }
            InputEvent::PointerAxis { horizontal, vertical, time_ms } => {
                self.ext.idle_notify.record_activity();
                let client = self.seat.pointer.focus.as_ref().and_then(|s| {
                    self.get_surface(*s).and_then(|sf| {
                        let sf = sf.read().unwrap();
                        sf.resource.as_ref().and_then(|r| r.client())
                    })
                });
                if vertical != 0.0 {
                    self.seat.broadcast_pointer_axis(
                        time_ms,
                        wl_pointer::Axis::VerticalScroll,
                        vertical,
                        client.as_ref(),
                    );
                }
                if horizontal != 0.0 {
                    self.seat.broadcast_pointer_axis(
                        time_ms,
                        wl_pointer::Axis::HorizontalScroll,
                        horizontal,
                        client.as_ref(),
                    );
                }
                self.seat.broadcast_pointer_frame(client.as_ref());
            }
            InputEvent::KeyboardKey { keycode, state, time_ms } => {
                 let wl_state = if state == crate::core::input::KeyState::Pressed {
                    KeyState::Pressed
                } else {
                    KeyState::Released
                };
                
                let client = if let Some(sid) = self.seat.keyboard.focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.broadcast_key(serial, time_ms, keycode, wl_state, client.as_ref());
            }
            InputEvent::KeyboardModifiers { depressed, latched, locked, group } => {
                self.seat.keyboard.mods_depressed = depressed;
                self.seat.keyboard.mods_latched = latched;
                self.seat.keyboard.mods_locked = locked;
                self.seat.keyboard.mods_group = group;
                
                let client = if let Some(sid) = self.seat.keyboard.focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.broadcast_modifiers(
                    serial, 
                    depressed, 
                    latched, 
                    locked, 
                    group, 
                    client.as_ref()
                );
            }
        }
    }
}
