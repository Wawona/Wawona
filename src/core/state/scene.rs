//! Scene graph building and layer surface positioning.
//!
//! Contains the `CompositorState` methods responsible for constructing
//! the scene graph from windows, layer surfaces, popups, and subsurfaces,
//! as well as repositioning layer surfaces and computing usable output area.

use super::*;

impl CompositorState {
    /// Report presentation feedback
    pub fn report_presentation_feedback(
        &mut self,
        _timestamp: std::time::Instant,
        refresh_mhz: u32,
    ) {
        let seq = self.next_presentation_seq();

        let refresh_ns = if refresh_mhz > 0 {
            1_000_000_000_000 / refresh_mhz as u64
        } else {
            16_666_666
        };

        let ts_ns = crate::core::Compositor::timestamp_ms() as u64 * 1_000_000;

        self.ext
            .presentation
            .send_presented_events(ts_ns, refresh_ns, seq);
    }

    /// If an `xdg_surface.configure` is still unacked, queue this size and return `None`.
    /// Otherwise send configure and return `Some(serial)`.
    pub fn flush_deferred_toplevel_configure(&mut self, client_id: ClientId, xdg_surface_id: u32) {
        let key_size = self
            .xdg
            .toplevels
            .iter()
            .find(|(k, tl)| k.0 == client_id && tl.xdg_surface_id == xdg_surface_id)
            .and_then(|(k, tl)| tl.deferred_configure_size.map(|sz| (k.clone(), sz)));
        let Some((key, (dw, dh))) = key_size else {
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "flush_deferred_toplevel_configure: none pending for xdg_surface={}",
                xdg_surface_id
            );
            return;
        };
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "flush_deferred_toplevel_configure: xdg_surface={} -> tl_id={} size={}x{}",
            xdg_surface_id,
            key.1,
            dw,
            dh
        );
        let _ = self.send_toplevel_configure(key.0, key.1, dw, dh);
    }

    /// Send a configure event to an xdg_toplevel and its associated xdg_surface.
    /// Size is clamped to the client's min/max constraints (unless fullscreen, which ignores constraints per spec).
    pub fn send_toplevel_configure(
        &mut self,
        client_id: ClientId,
        toplevel_id: u32,
        width: u32,
        height: u32,
    ) -> Option<u32> {
        let xdg_surface_id = match self.xdg.toplevels.get(&(client_id.clone(), toplevel_id)) {
            Some(tl) => tl.xdg_surface_id,
            None => {
                crate::wlog!(
                    crate::util::logging::COMPOSITOR,
                    "send_toplevel_configure: tl_id={} NOT FOUND",
                    toplevel_id
                );
                return None;
            }
        };

        let superseded_pending_serial = self
            .xdg
            .surfaces
            .get(&(client_id.clone(), xdg_surface_id))
            .map(|surf| surf.pending_serial)
            .unwrap_or(0);
        // Previously we deferred when pending_serial != 0 (nested native
        // ack latency). Over waypipe RTT that blocked mid-drag live resize
        // (#63/#80/#88): host streamed injectWindowResize but configures
        // only flushed after ack. Always emit a fresh configure; xdg-shell
        // clients ack the latest serial. Still stash deferred size so an
        // ack path can reconcile if send fails below.
        if superseded_pending_serial != 0 {
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "send_toplevel_configure: live-supersede unacked serial {} with new size={}x{} for xdg_surface={}",
                superseded_pending_serial,
                width,
                height,
                xdg_surface_id
            );
            if let Some(toplevel_data) = self
                .xdg
                .toplevels
                .get_mut(&(client_id.clone(), toplevel_id))
            {
                toplevel_data.deferred_configure_size = Some((width, height));
            }
        }

        let smithay_surface = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .and_then(|tl| tl.toplevel_surface.clone());

        if let Some(toplevel_surface) = smithay_surface {
            let fallback_fs = self
                .outputs
                .get(self.primary_output)
                .map(|o| (o.width.max(1), o.height.max(1)))
                .unwrap_or((1024, 768));
            let (
                final_w,
                final_h,
                activated,
                pending_maximized,
                pending_fullscreen,
                interactive_resize,
            ) = {
                let Some(toplevel_data) = self
                    .xdg
                    .toplevels
                    .get_mut(&(client_id.clone(), toplevel_id))
                else {
                    return None;
                };
                toplevel_data.deferred_configure_size = None;
                let (final_w, final_h) = if toplevel_data.pending_fullscreen {
                    // Nested weston copies configure size into its output.
                    // `max(1)` of a 0x0 fullscreen made a 1x1 mode (blank window).
                    if width > 0 && height > 0 {
                        (width, height)
                    } else {
                        fallback_fs
                    }
                } else if width == 0 && height == 0 {
                    // Per xdg-shell, 0x0 means "the client decides its own
                    // size". Pass it through (first-commit trust).
                    (0, 0)
                } else {
                    let (clamped_w, clamped_h) =
                        toplevel_data.clamp_size(width.max(1), height.max(1));
                    (clamped_w.max(1), clamped_h.max(1))
                };
                toplevel_data.width = final_w;
                toplevel_data.height = final_h;
                (
                    final_w,
                    final_h,
                    toplevel_data.activated,
                    toplevel_data.pending_maximized,
                    toplevel_data.pending_fullscreen,
                    toplevel_data.interactive_resize,
                )
            };

            toplevel_surface.with_pending_state(|state| {
                use wayland_protocols::xdg::shell::server::xdg_toplevel::State;
                state.size = Some((final_w as i32, final_h as i32).into());
                if activated {
                    state.states.set(State::Activated);
                } else {
                    state.states.unset(State::Activated);
                }
                if pending_maximized {
                    state.states.set(State::Maximized);
                } else {
                    state.states.unset(State::Maximized);
                }
                if pending_fullscreen {
                    state.states.set(State::Fullscreen);
                } else {
                    state.states.unset(State::Fullscreen);
                }
                // xdg-shell: Resizing must be set for the duration of an
                // interactive resize and cleared on the settle configure
                // (niri/smithay/WSLg RAIL pattern). Mid-drag suggestions
                // without this bit are not a live resize session.
                if interactive_resize {
                    state.states.set(State::Resizing);
                } else {
                    state.states.unset(State::Resizing);
                }
            });
            let serial = u32::from(toplevel_surface.send_configure());
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "send_toplevel_configure: client={:?} tl_id={} size={}x{} serial={} resizing={} (smithay)",
                client_id,
                toplevel_id,
                final_w,
                final_h,
                serial,
                interactive_resize
            );
            if let Some(toplevel_data) = self
                .xdg
                .toplevels
                .get_mut(&(client_id.clone(), toplevel_id))
            {
                toplevel_data.pending_serial = serial;
            }
            if let Some(surface_data) = self
                .xdg
                .surfaces
                .get_mut(&(client_id.clone(), xdg_surface_id))
            {
                surface_data.pending_serial = serial;
                surface_data.pending_serials.push(serial);
                surface_data.configured = false;
            }
            return Some(serial);
        }

        let v6_resource = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .and_then(|tl| tl.v6_resource.clone());

        if let Some(v6_toplevel) = v6_resource {
            let fallback_fs = self
                .outputs
                .get(self.primary_output)
                .map(|o| (o.width.max(1), o.height.max(1)))
                .unwrap_or((1024, 768));
            let (
                final_w,
                final_h,
                activated,
                pending_maximized,
                pending_fullscreen,
                interactive_resize,
            ) = {
                let Some(toplevel_data) = self
                    .xdg
                    .toplevels
                    .get_mut(&(client_id.clone(), toplevel_id))
                else {
                    return None;
                };
                toplevel_data.deferred_configure_size = None;
                let (final_w, final_h) = if toplevel_data.pending_fullscreen {
                    if width > 0 && height > 0 {
                        (width, height)
                    } else {
                        fallback_fs
                    }
                } else if width == 0 && height == 0 {
                    (0, 0)
                } else {
                    let (clamped_w, clamped_h) =
                        toplevel_data.clamp_size(width.max(1), height.max(1));
                    (clamped_w.max(1), clamped_h.max(1))
                };
                toplevel_data.width = final_w;
                toplevel_data.height = final_h;
                (
                    final_w,
                    final_h,
                    toplevel_data.activated,
                    toplevel_data.pending_maximized,
                    toplevel_data.pending_fullscreen,
                    toplevel_data.interactive_resize,
                )
            };

            let mut states_bytes = Vec::new();
            if pending_maximized {
                states_bytes.extend_from_slice(
                    &(crate::core::wayland::xdg::v6::protocol::zxdg_toplevel_v6::State::Maximized as u32)
                        .to_ne_bytes(),
                );
            }
            if pending_fullscreen {
                states_bytes.extend_from_slice(
                    &(crate::core::wayland::xdg::v6::protocol::zxdg_toplevel_v6::State::Fullscreen as u32)
                        .to_ne_bytes(),
                );
            }
            if interactive_resize {
                states_bytes.extend_from_slice(
                    &(crate::core::wayland::xdg::v6::protocol::zxdg_toplevel_v6::State::Resizing as u32)
                        .to_ne_bytes(),
                );
            }
            if activated {
                states_bytes.extend_from_slice(
                    &(crate::core::wayland::xdg::v6::protocol::zxdg_toplevel_v6::State::Activated as u32)
                        .to_ne_bytes(),
                );
            }

            v6_toplevel.configure(final_w as i32, final_h as i32, states_bytes);
            let serial = self.next_serial();
            if let Some(surf_res) = self
                .xdg
                .surfaces
                .get(&(client_id.clone(), xdg_surface_id))
                .and_then(|s| s.v6_resource.as_ref())
            {
                surf_res.configure(serial);
            }

            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "send_toplevel_configure (v6): client={:?} tl_id={} size={}x{} serial={}",
                client_id,
                toplevel_id,
                final_w,
                final_h,
                serial
            );
            if let Some(toplevel_data) = self
                .xdg
                .toplevels
                .get_mut(&(client_id.clone(), toplevel_id))
            {
                toplevel_data.pending_serial = serial;
            }
            if let Some(surface_data) = self
                .xdg
                .surfaces
                .get_mut(&(client_id.clone(), xdg_surface_id))
            {
                surface_data.pending_serial = serial;
                surface_data.pending_serials.push(serial);
                surface_data.configured = false;
            }
            return Some(serial);
        }

        // Smithay is the only serial namespace: every real toplevel is created
        // by smithay's XdgShellHandler::new_toplevel and always carries a
        // ToplevelSurface. A missing one means teardown is racing. Do not
        // fall back to a hand-rolled configure with a self-invented serial
        // (the old path double-tracked serials and desynced ack matching).
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "send_toplevel_configure: tl_id={} has no smithay ToplevelSurface (teardown?); skipping",
            toplevel_id
        );
        None
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
                if let Some(res) = &data.v6_resource {
                    crate::wlog!(
                        crate::util::logging::COMPOSITOR,
                        "Sending zxdg_toplevel_v6.close for window_id={}",
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

    /// Restore `wl_keyboard` focus to `window_id` (popup parent after grab
    /// dismiss). GTK menus need the parent focused again before a second
    /// `xdg_popup.grab` will succeed.
    fn restore_keyboard_focus_to_window(&mut self, window_id: u32) {
        let surface_id = self
            .surface_to_window
            .iter()
            .find(|(_, &wid)| wid == window_id)
            .map(|(sid, _)| *sid);
        let Some(sid) = surface_id else {
            return;
        };
        let serial = self.next_serial();
        let Some(surface) = self.surfaces.get(&sid).cloned() else {
            return;
        };
        let surface = surface.read().unwrap();
        let Some(res) = surface.resource.as_ref() else {
            return;
        };
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Restoring keyboard focus to parent window_id={} surface={}",
            window_id,
            sid
        );
        self.focus.set_keyboard_focus(Some(window_id));
        self.seat.keyboard.focus = Some(sid);
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
        self.ext.text_input.enter(res, Some(sid));
    }

    /// Send `xdg_popup.popup_done` for the popup hosted by `window_id` (host
    /// dismissed it: click-away, Escape, parent teardown). Returns `true` if a
    /// matching popup was found.
    pub fn send_popup_done_for_window(&mut self, window_id: u32) -> bool {
        let mut parent_id = None;
        let mut found = false;
        let mut popup_key = None;
        for ((cid, pid), data) in self.xdg.popups.iter() {
            if data.window_id == window_id {
                parent_id = data.parent_id;
                popup_key = Some((cid.clone(), *pid));
                crate::wlog!(
                    crate::util::logging::COMPOSITOR,
                    "Sending xdg_popup.popup_done for window_id={} popup={}",
                    window_id,
                    pid
                );
                if let Some(ps) = data.popup_surface.clone() {
                    ps.send_popup_done();
                } else if let Some(res) = data.resource.clone() {
                    res.popup_done();
                }
                if let Some(res) = data.v6_resource.clone() {
                    res.popup_done();
                }
                found = true;
                break;
            }
        }
        if let Some(key) = popup_key {
            self.seat
                .popup_grab_stack
                .retain(|(gcid, gpid)| !(gcid == &key.0 && *gpid == key.1));
            // Tear down host chrome immediately; client destroy may lag over
            // waypipe and leave a stuck grab UI.
            self.pending_compositor_events
                .push(crate::core::compositor::CompositorEvent::WindowDestroyed {
                    window_id,
                });
        }
        if let Some(parent) = parent_id {
            self.restore_keyboard_focus_to_window(parent);
        }
        found
    }

    /// Dismiss the active popup grab and all its child popups
    pub fn dismiss_popup_grab(&mut self) {
        let mut parent_to_restore = None;
        let mut destroyed = Vec::new();
        while let Some((cid, pid)) = self.seat.popup_grab_stack.pop() {
            if let Some(data) = self.xdg.popups.get(&(cid.clone(), pid)) {
                let window_id = data.window_id;
                if parent_to_restore.is_none() {
                    parent_to_restore = data.parent_id;
                }
                crate::wlog!(
                    crate::util::logging::COMPOSITOR,
                    "Dismissing popup grab window_id={} popup={}",
                    window_id,
                    pid
                );
                if let Some(ps) = data.popup_surface.clone() {
                    ps.send_popup_done();
                } else if let Some(res) = data.resource.clone() {
                    res.popup_done();
                }
                if let Some(res) = data.v6_resource.clone() {
                    res.popup_done();
                }
                destroyed.push(window_id);
            }
        }
        for window_id in destroyed {
            self.pending_compositor_events
                .push(crate::core::compositor::CompositorEvent::WindowDestroyed {
                    window_id,
                });
        }
        if let Some(parent) = parent_to_restore {
            self.restore_keyboard_focus_to_window(parent);
        }
    }

    /// Returns true when `surface_id` is the grabbed popup or a subsurface in
    /// its tree (GTK menu rows can live in subsurfaces).
    fn surface_in_popup_grab_tree(&self, surface_id: u32) -> bool {
        for &(ref cid, popup_id) in &self.seat.popup_grab_stack {
            let Some(popup) = self.xdg.popups.get(&(cid.clone(), popup_id)) else {
                continue;
            };
            if popup.surface_id == surface_id {
                return true;
            }
            let mut sid = surface_id;
            for _ in 0..16 {
                if sid == popup.surface_id {
                    return true;
                }
                if let Some(sub) = self.subsurfaces.get(&sid) {
                    sid = sub.parent_id;
                } else {
                    break;
                }
            }
            if let Some(&wid) = self.surface_to_window.get(&surface_id) {
                if wid == popup.window_id {
                    return true;
                }
            }
        }
        false
    }

    /// xdg_popup grab: dismiss when the user presses a button outside the grab
    /// tree. Returns true if any popup was dismissed.
    pub fn maybe_dismiss_popup_grab_on_press(&mut self) -> bool {
        if self.seat.popup_grab_stack.is_empty() {
            return false;
        }
        let focus = self.seat.pointer.focus;
        let on_grab_tree = focus.is_some_and(|focus_id| self.surface_in_popup_grab_tree(focus_id));
        if on_grab_tree {
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "popup grab press on grab tree (focus={:?}); keeping grab",
                focus
            );
            return false;
        }
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "popup grab press outside tree (focus={:?}, stack={}); dismissing",
            focus,
            self.seat.popup_grab_stack.len()
        );
        let had_grabs = !self.seat.popup_grab_stack.is_empty();
        self.dismiss_popup_grab();
        had_grabs
    }

    /// Get the geometry of an output (x, y, width, height)
    pub fn get_output_geometry(&self, output_id: u32) -> Option<(i32, i32, u32, u32)> {
        self.outputs
            .iter()
            .find(|o| o.id == output_id)
            .map(|o| (o.x, o.y, o.width, o.height))
    }

    /// Usable region of an output: the output minus safe-area insets and
    /// layer-shell exclusive zones, as last arranged by
    /// [`Self::reposition_layer_surfaces`].
    pub fn get_usable_region(&self, output_id: u32) -> Option<(i32, i32, u32, u32)> {
        let output = self.outputs.iter().find(|o| o.id == output_id)?;
        let usable = output.usable_area;
        Some((usable.x, usable.y, usable.width, usable.height))
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
        let geom_by_surface: std::collections::HashMap<u32, (i32, i32, i32, i32)> = self
            .xdg
            .surfaces
            .values()
            .filter_map(|s| s.geometry.map(|g| (s.surface_id, g)))
            .collect();

        let mut ordered_windows = self.window_tree.stacking_order.clone();
        for window_id in self.windows.keys().copied() {
            if !ordered_windows.contains(&window_id) {
                ordered_windows.push(window_id);
            }
        }

        for window_id in ordered_windows {
            // A platform host hides minimized windows itself and never
            // clears `minimized`, so only the headless window manager
            // drops them from the scene (and from input picking).
            if self.headless_host && !self.is_window_shown(window_id) {
                continue;
            }
            if let Some(window) = self.get_window(window_id) {
                let window = window.read().unwrap();
                if !self.surface_has_content(window.surface_id, window.has_committed_buffer) {
                    continue;
                }
                let node_id = self.next_node_id();
                let mut node = SceneNode::new(node_id).with_surface(window.surface_id);
                let is_kiosk_window = self.is_host_locked_window(window.id);

                node.set_position(window.x, window.y);
                // Present at committed buffer size (OWL: frame == buffer).
                // Only while the host is size-authoritative mid live-resize
                // (#111) stretch the last buffer into the host size so nested
                // niri does not flash before/after sizes. Never leave a giant
                // host frame around a small demo client. That is a sync bug.
                let mut render_width = window.width.max(0) as u32;
                let mut render_height = window.height.max(0) as u32;
                if !is_kiosk_window {
                    let output_scale = self
                        .outputs
                        .get(self.primary_output)
                        .map(|o| o.scale)
                        .unwrap_or(1.0);
                    if let Some(surface_ref) = self.get_surface(window.surface_id) {
                        let surface = surface_ref.read().unwrap();
                        let committed_width = surface.current.width.max(0) as u32;
                        let committed_height = surface.current.height.max(0) as u32;
                        let win_w = window.width.max(0) as u32;
                        let win_h = window.height.max(0) as u32;
                        let surface_scale = surface.current.scale.max(1) as u32;
                        // current.{width,height} are already logical
                        // (buffer / wl_surface.set_buffer_scale). Do not divide
                        // again or a scale-2 800x600 surface becomes 400x300.
                        let host_ahead = window.size_authority.is_host()
                            && win_w > 0
                            && win_h > 0
                            && committed_width > 0
                            && committed_height > 0
                            && (committed_width != win_w || committed_height != win_h);
                        if host_ahead {
                            render_width = win_w;
                            render_height = win_h;
                        } else if committed_width > 0 && committed_height > 0 {
                            render_width = committed_width;
                            render_height = committed_height;
                        }
                        node.scale = surface_scale as f32;
                        let viewport = self.ext.viewporter.for_surface(window.surface_id);
                        let has_viewport_dest = viewport
                            .and_then(|v| v.destination)
                            .is_some();
                        // GTK4 / fractional-scale path: buffer is physical,
                        // current size is viewport destination (logical).
                        // Present scale must be buffer/logical so CALayer
                        // contentsScale matches; otherwise only one Retina
                        // quadrant shows.
                        if has_viewport_dest {
                            if let Some((bw, bh)) = surface.current.buffer.dimensions() {
                                if committed_width > 0 && committed_height > 0 {
                                    let sx = bw as f32 / committed_width as f32;
                                    let sy = bh as f32 / committed_height as f32;
                                    if sx >= 1.0 && sy >= 1.0 {
                                        node.scale = ((sx + sy) * 0.5).clamp(1.0, 8.0);
                                    }
                                }
                            }
                            crate::wlog_hot!(
                                crate::util::logging::STATE,
                                "Viewport present: surf={} buf={:?} logical={}x{} scale={} dest={:?}",
                                window.surface_id,
                                surface.current.buffer.dimensions(),
                                committed_width,
                                committed_height,
                                node.scale,
                                viewport.and_then(|v| v.destination)
                            );
                        } else if surface.current.scale <= 1 && output_scale > 1.0 {
                            // Weston-style HiDPI: the client committed a buffer at
                            // output-scale x window-size without calling
                            // wl_surface.set_buffer_scale. Present it at logical
                            // (window) size with the inferred scale so it is not
                            // drawn double-sized and pointer coords stay aligned.
                            let scaled_w = (win_w as f32 * output_scale).round() as u32;
                            let scaled_h = (win_h as f32 * output_scale).round() as u32;
                            if win_w > 0
                                && win_h > 0
                                && committed_width == scaled_w
                                && committed_height == scaled_h
                            {
                                render_width = win_w;
                                render_height = win_h;
                                node.scale = output_scale;
                            } else if let Some(output) = self.outputs.get(self.primary_output) {
                                // Window size may already equal the physical
                                // buffer (client/host raced before density
                                // applied). Still present at output *logical*
                                // size when the buffer matches output×scale -
                                // otherwise Android draws a 1080 quad into a
                                // 360 viewport and only a black corner shows
                                // (weston-simple-egl flash-then-black).
                                let out_w = output.width;
                                let out_h = output.height;
                                let out_scaled_w = (out_w as f32 * output_scale).round() as u32;
                                let out_scaled_h = (out_h as f32 * output_scale).round() as u32;
                                if out_w > 0
                                    && out_h > 0
                                    && committed_width == out_scaled_w
                                    && committed_height == out_scaled_h
                                {
                                    render_width = out_w;
                                    render_height = out_h;
                                    node.scale = output_scale;
                                }
                            }
                        }
                    }
                } else if let Some(surface_ref) = self.get_surface(window.surface_id) {
                    let surface = surface_ref.read().unwrap();
                    node.scale = (surface.current.scale.max(1)) as f32;
                }
                node.set_size(render_width, render_height);

                // Crop client-drawn CSD chrome from the buffer when appropriate.
                // CSD mode uses client geometry; Force SSD still crops if the client
                // keeps painting decorations (weston-terminal over waypipe, etc.).
                if let Some(surf_ref) = self.get_surface(window.surface_id) {
                    let surf = surf_ref.read().unwrap();
                    let xdg_geometry = geom_by_surface.get(&window.surface_id).copied();
                    let window_policy = window.decoration_policy.unwrap_or(self.decoration_policy);
                    if let Some((inter_x1, inter_y1, inter_w, inter_h)) =
                        crate::core::wayland::xdg::decoration::resolve_window_content_geometry(
                            window_policy,
                            &window.app_id,
                            window.decoration_mode,
                            surf.current.width,
                            surf.current.height,
                            xdg_geometry,
                        )
                    {
                        let buf_w = surf.current.width as f32;
                        let buf_h = surf.current.height as f32;
                        if buf_w > 0.0 && buf_h > 0.0 {
                            node.content_rect = ContentRect {
                                x: inter_x1 as f32 / buf_w,
                                y: inter_y1 as f32 / buf_h,
                                w: inter_w as f32 / buf_w,
                                h: inter_h as f32 / buf_h,
                            };
                            // Kiosk surfaces stay output-sized; only crop in presentation.
                            if !is_kiosk_window {
                                node.set_size(inter_w as u32, inter_h as u32);
                            }
                        }
                    }
                }

                // wp_viewport.set_source is buffer-local; override UV crop when set.
                if let Some(src) = self
                    .ext
                    .viewporter
                    .for_surface(window.surface_id)
                    .and_then(|v| v.source)
                {
                    if let Some(surf_ref) = self.get_surface(window.surface_id) {
                        let surf = surf_ref.read().unwrap();
                        if let Some((bw, bh)) = surf.current.buffer.dimensions() {
                            if bw > 0 && bh > 0 {
                                node.content_rect = ContentRect {
                                    x: (src.x / bw as f64) as f32,
                                    y: (src.y / bh as f64) as f32,
                                    w: (src.width / bw as f64) as f32,
                                    h: (src.height / bh as f64) as f32,
                                };
                            }
                        }
                    }
                }

                let alpha = self.ext.alpha_modifier.get_alpha_f64(window.surface_id) as f32;
                node.opacity = alpha;

                new_scene.add_node(node);
                new_scene.add_child(root_id, node_id);

                let geom_offset = (window.geometry_x, window.geometry_y);
                self.add_subsurfaces_to_scene(
                    &mut new_scene,
                    node_id,
                    window.surface_id,
                    geom_offset,
                );
            }
        }

        let popup_data_list: Vec<_> = self
            .xdg
            .popups
            .iter()
            .filter(|(_, p)| p.parent_surface_id.is_none())
            .map(|((cid, _), p)| (cid.clone(), p.surface_id, p.geometry, p.parent_id))
            .collect();

        for (cid, popup_surface_id, geometry, parent_window_id) in popup_data_list {
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id).with_surface(popup_surface_id);

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

    /// Arrange layer surfaces on every output and update usable areas.
    ///
    /// Surfaces with a positive exclusive zone are placed first, highest
    /// layer first and in creation order, each inside the area left by the
    /// ones before it, and reserve their zone. The rest are placed inside the
    /// final usable area, or the whole output for an exclusive zone of -1.
    /// A changed arranged size is configured; a changed usable area
    /// reconfigures maximized toplevels.
    pub fn reposition_layer_surfaces(&mut self) {
        use crate::core::wayland::wlr::layer_shell::{
            layer_configure_size, layer_position, reserve_exclusive_zone,
        };

        let order: Vec<_> = self
            .smithay_runtime
            .layer_shell
            .as_ref()
            .map(|shell| {
                shell
                    .layer_surfaces()
                    .filter_map(|handle| self.internal_surface_id(handle.wl_surface()))
                    .filter_map(|sid| self.layer_surface_for(sid))
                    .collect()
            })
            .unwrap_or_default();

        let mut usable_changed = Vec::new();
        for i in 0..self.outputs.len() {
            let (output_id, full, previous) = {
                let o = &self.outputs[i];
                (
                    o.id,
                    crate::util::geometry::Rect::new(o.x, o.y, o.width, o.height),
                    o.usable_area,
                )
            };
            let mut usable = full;
            let (sa_top, sa_right, sa_bottom, sa_left) = self.outputs[i].safe_area_insets;
            for (anchor, inset) in [(1, sa_top), (2, sa_bottom), (4, sa_left), (8, sa_right)] {
                crate::core::wayland::wlr::layer_shell::reserve_exclusive_zone(
                    &mut usable,
                    anchor,
                    inset,
                    (0, 0, 0, 0),
                );
            }

            let on_output: Vec<_> = order
                .iter()
                .filter(|ls| {
                    ls.read()
                        .map(|ls| ls.output_id == output_id && ls.initialized)
                        .unwrap_or(false)
                })
                .cloned()
                .collect();

            let place = |ls_lock: &std::sync::Arc<std::sync::RwLock<LayerSurface>>,
                         area: &crate::util::geometry::Rect| {
                let Ok(mut ls) = ls_lock.write() else {
                    return;
                };
                let size = layer_configure_size(ls.requested, ls.anchor, ls.margin, area);
                let (x, y) = ls
                    .position_override
                    .unwrap_or_else(|| layer_position(size, ls.anchor, ls.margin, area));
                ls.x = x;
                ls.y = y;
                ls.width = size.0;
                ls.height = size.1;
            };

            for layer in (0..4).rev() {
                for ls_lock in &on_output {
                    let (matches, anchor, zone, margin) = match ls_lock.read() {
                        Ok(ls) => (
                            ls.layer == layer && ls.exclusive_zone > 0,
                            ls.anchor,
                            ls.exclusive_zone,
                            ls.margin,
                        ),
                        Err(_) => continue,
                    };
                    if matches {
                        place(ls_lock, &usable);
                        reserve_exclusive_zone(&mut usable, anchor, zone, margin);
                    }
                }
            }
            for layer in (0..4).rev() {
                for ls_lock in &on_output {
                    let (matches, zone) = match ls_lock.read() {
                        Ok(ls) => (
                            ls.layer == layer && ls.exclusive_zone <= 0,
                            ls.exclusive_zone,
                        ),
                        Err(_) => continue,
                    };
                    if matches {
                        let area = if zone < 0 { full } else { usable };
                        place(ls_lock, &area);
                    }
                }
            }

            self.outputs[i].usable_area = usable;
            if (previous.x, previous.y, previous.width, previous.height)
                != (usable.x, usable.y, usable.width, usable.height)
            {
                usable_changed.push(output_id);
            }

            for ls_lock in &on_output {
                let Ok(ls) = ls_lock.read() else {
                    continue;
                };
                let Some(handle) = ls.handle.as_ref() else {
                    continue;
                };
                let initial_sent =
                    smithay::wayland::compositor::with_states(handle.wl_surface(), |states| {
                        states
                            .data_map
                            .get::<smithay::wayland::shell::wlr_layer::LayerSurfaceData>()
                            .and_then(|d| d.lock().ok().map(|a| a.initial_configure_sent))
                            .unwrap_or(false)
                    });
                let size = (
                    i32::try_from(ls.width).unwrap_or(0),
                    i32::try_from(ls.height).unwrap_or(0),
                );
                handle.with_pending_state(|state| state.size = Some(size.into()));
                if initial_sent {
                    handle.send_pending_configure();
                }
            }
        }
        for output_id in usable_changed {
            self.reconfigure_maximized_toplevels(output_id);
        }
    }

    fn add_layer_to_scene(&mut self, scene: &mut Scene, root_id: u32, layer: u32) {
        let mut node_data: Vec<_> = self
            .wlr
            .layer_surfaces
            .values()
            .filter_map(|ls_ref| {
                let ls = ls_ref.read().ok()?;
                (ls.layer == layer && ls.mapped).then_some((ls.surface_id, ls.x, ls.y))
            })
            .collect();
        // Creation order keeps stacking stable within a layer.
        node_data.sort_by_key(|(sid, _, _)| *sid);

        for (surface_id, x, y) in node_data {
            let Some(surface_ref) = self.get_surface(surface_id) else {
                continue;
            };
            let (width, height, scale) = match surface_ref.read() {
                Ok(s) => (
                    s.current.width.max(0) as u32,
                    s.current.height.max(0) as u32,
                    s.current.scale.max(1) as f32,
                ),
                Err(_) => continue,
            };
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id).with_surface(surface_id);
            node.set_position(x, y);
            node.set_size(width, height);
            node.scale = scale;

            scene.add_node(node);
            scene.add_child(root_id, node_id);

            self.add_subsurfaces_to_scene(scene, node_id, surface_id, (0, 0));
            self.add_layer_popups_to_scene(scene, node_id, surface_id);
        }
    }

    /// `zwlr_layer_surface_v1.get_popup` children, positioned relative to
    /// their layer surface.
    fn add_layer_popups_to_scene(&mut self, scene: &mut Scene, parent_node_id: u32, parent: u32) {
        let popups: Vec<_> = self
            .xdg
            .popups
            .values()
            .filter(|p| p.parent_surface_id == Some(parent))
            .map(|p| (p.surface_id, p.geometry))
            .collect();
        for (surface_id, geometry) in popups {
            if !self.surface_has_content(surface_id, true) {
                continue;
            }
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id).with_surface(surface_id);
            node.set_position(geometry.0, geometry.1);
            node.set_size(
                u32::try_from(geometry.2).unwrap_or(0),
                u32::try_from(geometry.3).unwrap_or(0),
            );
            node.opacity = self.ext.alpha_modifier.get_alpha_f64(surface_id) as f32;
            scene.add_node(node);
            scene.add_child(parent_node_id, node_id);
            self.add_subsurfaces_to_scene(scene, node_id, surface_id, (0, 0));
        }
    }

    /// Whether a window root or subsurface has a buffer. A null buffer
    /// commit unmaps the surface together with its subsurface tree, so it
    /// leaves the scene and input picking. Platform hosts keep a placeholder
    /// for a window that never committed a buffer; the headless manager
    /// does not.
    fn surface_has_content(&self, surface_id: u32, has_committed_buffer: bool) -> bool {
        if !self.headless_host && !has_committed_buffer {
            return true;
        }
        self.get_surface(surface_id)
            .and_then(|surface| surface.read().ok().map(|s| s.current.buffer_id.is_some()))
            .unwrap_or(false)
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
        let (children, below_parent) = self.subsurface_stacking(parent_surface_id);
        let mut added_below = 0;
        for (index, child_surface_id) in children.into_iter().enumerate() {
            let Some(pos) = self.subsurfaces.get(&child_surface_id).map(|s| s.position) else {
                continue;
            };
            if !self.surface_has_content(child_surface_id, true) {
                continue;
            }
            let node_id = self.next_node_id();
            let mut node = SceneNode::new(node_id).with_surface(child_surface_id);

            node.set_position(pos.0 - geometry_offset.0, pos.1 - geometry_offset.1);

            if let Some(surface_ref) = self.get_surface(child_surface_id) {
                if let Ok(surface) = surface_ref.read() {
                    node.set_size(
                        surface.current.width.max(0) as u32,
                        surface.current.height.max(0) as u32,
                    );
                    node.scale = (surface.current.scale.max(1)) as f32;
                }
            }

            scene.add_node(node);
            scene.add_child(parent_node_id, node_id);
            if index < below_parent {
                added_below += 1;
            }

            self.add_subsurfaces_to_scene(scene, node_id, child_surface_id, (0, 0));
        }
        if let Some(parent) = scene.nodes.get_mut(&parent_node_id) {
            parent.children_below = added_below;
        }
    }

    /// Direct subsurfaces of `surface_id` bottom to top, as Smithay's surface
    /// tree orders them, and how many of them stack below `surface_id`.
    fn subsurface_stacking(&self, surface_id: u32) -> (Vec<u32>, usize) {
        use smithay::wayland::compositor::{with_surface_tree_upward, TraversalAction};

        let Some(parent) = self.wl_surface_for(surface_id) else {
            return (Vec::new(), 0);
        };
        // `None` marks the parent's own slot in its children list.
        let mut order = Vec::new();
        with_surface_tree_upward(
            &parent,
            false,
            |_, _, &is_child| {
                if is_child {
                    TraversalAction::SkipChildren
                } else {
                    TraversalAction::DoChildren(true)
                }
            },
            |surface, _, &is_child| order.push(is_child.then(|| surface.clone())),
            |_, _, _| true,
        );

        let below_parent = order.iter().take_while(|slot| slot.is_some()).count();
        let mut children = Vec::with_capacity(order.len());
        let mut below = 0;
        for (index, slot) in order.iter().enumerate() {
            let Some(id) = slot.as_ref().and_then(|s| self.internal_surface_id(s)) else {
                continue;
            };
            if index < below_parent {
                below += 1;
            }
            children.push(id);
        }
        (children, below)
    }
}
