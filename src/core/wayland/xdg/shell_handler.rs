//! Smithay `XdgShellHandler` implementation for Wawona core shell lifecycle.

use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel;
use smithay::reexports::wayland_server::protocol::wl_output::WlOutput;
use smithay::reexports::wayland_server::protocol::wl_seat::WlSeat;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::reexports::wayland_server::{backend::ClientId, Resource};
use smithay::utils::{Logical, Rectangle, Serial};
use smithay::wayland::shell::xdg::{
    Configure, PopupSurface, PositionerState, ShellClient, ToplevelSurface, XdgShellHandler,
    XdgShellState,
};

use crate::core::compositor::CompositorEvent;
use crate::core::state::{CompositorState, DecorationPolicy, XdgPopupData, XdgSurfaceData, XdgToplevelData};
use crate::core::surface::SurfaceRole;
use crate::core::window::{DecorationMode, Window};

impl CompositorState {
    fn xdg_shell_state_mut(&mut self) -> &mut XdgShellState {
        self.smithay_runtime
            .xdg_shell
            .as_mut()
            .expect("smithay xdg shell state must be initialized before dispatch")
    }

    pub(crate) fn xdg_toplevel_key_for_wl_surface(
        &self,
        wl_surface: &WlSurface,
    ) -> Option<(ClientId, u32)> {
        let client_id = wl_surface.client()?.id();
        let surface_id = self
            .protocol_to_internal_surface
            .get(&(client_id.clone(), wl_surface.id().protocol_id()))
            .copied()?;
        self.xdg
            .toplevels
            .iter()
            .find(|(_, tl)| tl.surface_id == surface_id)
            .map(|(key, _)| key.clone())
    }

    pub(crate) fn xdg_toplevel_key_for_surface(
        &self,
        surface: &ToplevelSurface,
    ) -> Option<(ClientId, u32)> {
        self.xdg_toplevel_key_for_wl_surface(surface.wl_surface())
    }

    pub(crate) fn xdg_popup_key_for_surface(
        &self,
        surface: &PopupSurface,
    ) -> Option<(ClientId, u32)> {
        let client_id = surface.wl_surface().client()?.id();
        let popup_id = surface.xdg_popup().id().protocol_id();
        self.xdg.popups.get(&(client_id, popup_id)).map(|_| {
            (
                surface.wl_surface().client().unwrap().id(),
                popup_id,
            )
        })
    }

    fn ensure_xdg_surface_entry(
        &mut self,
        client_id: ClientId,
        wl_surface: &WlSurface,
        surface_id: u32,
        window_id: Option<u32>,
    ) -> u32 {
        let xdg_surface_key = wl_surface.id().protocol_id();
        let key = (client_id.clone(), xdg_surface_key);
        self.xdg
            .surfaces
            .entry(key.clone())
            .or_insert_with(|| {
                let mut data = XdgSurfaceData::new(surface_id);
                data.window_id = window_id;
                data
            });
        if let Some(data) = self.xdg.surfaces.get_mut(&key) {
            if window_id.is_some() {
                data.window_id = window_id;
            }
        }
        xdg_surface_key
    }

    fn popup_target_rect(&self) -> Rectangle<i32, Logical> {
        let output = self.primary_output();
        Rectangle::new(
            (output.x, output.y).into(),
            (output.width as i32, output.height as i32).into(),
        )
    }

    fn parent_window_for_popup(&self, popup: &PopupSurface) -> Option<u32> {
        let parent_wl = popup.get_parent_surface()?;
        let client_id = parent_wl.client()?.id();
        let parent_surface_id = self
            .protocol_to_internal_surface
            .get(&(client_id, parent_wl.id().protocol_id()))
            .copied()?;
        self.surface_to_window.get(&parent_surface_id).copied()
    }

    fn handle_toplevel_ack_configure(&mut self, wl_surface: &WlSurface, serial: u32) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_wl_surface(wl_surface) else {
            return;
        };
        let xdg_surface_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.xdg_surface_id)
            .unwrap_or(0);

        let mut cleared_surface_pending = false;
        if let Some(surface_data) = self
            .xdg
            .surfaces
            .get_mut(&(client_id.clone(), xdg_surface_id))
        {
            if serial > surface_data.last_acked_serial {
                surface_data.last_acked_serial = serial;
            }
            if !surface_data.pending_serials.is_empty() {
                if let Some(pos) = surface_data
                    .pending_serials
                    .iter()
                    .position(|&pending| pending == serial)
                {
                    surface_data.pending_serials.drain(..=pos);
                    surface_data.pending_serial = surface_data.pending_serials.last().copied().unwrap_or(0);
                    surface_data.configured = surface_data.pending_serials.is_empty();
                    cleared_surface_pending = surface_data.pending_serials.is_empty();
                }
            } else if serial == surface_data.pending_serial {
                surface_data.configured = true;
                surface_data.pending_serial = 0;
                cleared_surface_pending = true;
            }
        }

        if let Some(tl_data) = self.xdg.toplevels.get(&(client_id.clone(), toplevel_id)) {
            if tl_data.pending_serial == serial {
                let window_id = tl_data.window_id;
                if let Some(tl_data) = self
                    .xdg
                    .toplevels
                    .get_mut(&(client_id.clone(), toplevel_id))
                {
                    if serial > tl_data.last_acked_serial {
                        tl_data.last_acked_serial = serial;
                    }
                    tl_data.pending_serial = 0;
                    tl_data.maximized = tl_data.pending_maximized;
                    tl_data.fullscreen = tl_data.pending_fullscreen;
                    let maximized = tl_data.maximized;
                    let fullscreen = tl_data.fullscreen;
                    drop(tl_data);
                    if let Some(window) = self.get_window(window_id) {
                        let mut window = window.write().unwrap();
                        window.maximized = maximized;
                        window.fullscreen = fullscreen;
                    }
                }
            }
        }

        if cleared_surface_pending {
            self.flush_deferred_toplevel_configure(client_id, xdg_surface_id);
        }
    }
}

impl XdgShellHandler for CompositorState {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState {
        self.xdg_shell_state_mut()
    }

    fn new_client(&mut self, client: ShellClient) {
        self.xdg.shell_clients.push(client);
    }

    fn client_pong(&mut self, client: ShellClient) {
        if let Some(idx) = self
            .xdg
            .shell_clients
            .iter()
            .position(|stored| stored == &client)
        {
            self.xdg
                .pending_pings
                .retain(|_, (ping_idx, _)| *ping_idx != idx);
        }
    }

    fn client_destroyed(&mut self, client: ShellClient) {
        self.xdg.shell_clients.retain(|stored| stored != &client);
    }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let wl_surface = surface.wl_surface();
        let Some(client_id) = wl_surface.client().map(|c| c.id()) else {
            return;
        };
        let surface_id = self.ensure_internal_surface_mapping(client_id.clone(), wl_surface);
        let xdg_surface_id =
            self.ensure_xdg_surface_entry(client_id.clone(), wl_surface, surface_id, None);
        let toplevel_id = surface.xdg_toplevel().id().protocol_id();

        let window_id = self.next_window_id();
        let mut window = Window::new(window_id, surface_id);
        // OWL / xdg-shell: initial configure is 0x0 ("client decides"). Keep
        // core + toplevel expected size at 0 so host sync does not treat the
        // wl_output size as a configure the client must match (weston-flower /
        // weston-smoke stay 200×200; seeding output size left a giant host
        // window around a small buffer).
        let (initial_width, initial_height) = (0u32, 0u32);
        window.width = 0;
        window.height = 0;
        window.size_authority = crate::core::window::SizeAuthority::AwaitingFirstCommit;

        let mut toplevel_data =
            XdgToplevelData::new(window_id, surface_id, xdg_surface_id);
        toplevel_data.width = initial_width;
        toplevel_data.height = initial_height;
        toplevel_data.resource = Some(surface.xdg_toplevel().clone());
        toplevel_data.toplevel_surface = Some(surface.clone());

        self.xdg
            .toplevels
            .insert((client_id.clone(), toplevel_id), toplevel_data);
        if let Some(data) = self
            .xdg
            .surfaces
            .get_mut(&(client_id.clone(), xdg_surface_id))
        {
            data.window_id = Some(window_id);
        }
        self.add_window(window);

        if let Some(surface_ref) = self.get_surface(surface_id) {
            let mut surface_state = surface_ref.write().unwrap();
            if let Err(e) = surface_state.set_role(SurfaceRole::Toplevel) {
                tracing::error!("Failed to set role for surface {}: {}", surface_id, e);
            }
        }

        // Always defer the initial configure to (0, 0) — per xdg-shell §xdg_toplevel,
        // a zero size means "the client should decide its own size." Sending a
        // real size here (e.g. the primary output's) forces well-behaved clients
        // to render at that size even when it doesn't match what they actually
        // want, and forces fixed-size clients (weston-smoke, etc.) into a
        // host/client size mismatch that misaligns content inside the window on
        // every platform. The client's first commit is trusted unconditionally
        // (see `Window::has_committed_buffer`), so deferring here is safe and
        // lets every window — on every platform — start edge-to-edge with its
        // own content.
        let (configure_w, configure_h) = (0i32, 0i32);

        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Activated);
            state.size = Some((configure_w, configure_h).into());
        });
        let serial = u32::from(surface.send_configure());

        if let Some(surface_data) = self
            .xdg
            .surfaces
            .get_mut(&(client_id.clone(), xdg_surface_id))
        {
            surface_data.pending_serial = serial;
            surface_data.pending_serials.push(serial);
        }
        if let Some(toplevel_data) = self
            .xdg
            .toplevels
            .get_mut(&(client_id.clone(), toplevel_id))
        {
            toplevel_data.pending_serial = serial;
            toplevel_data.activated = true;
        }

        tracing::info!(
            "Created xdg_toplevel: window_id={}, surface_id={}, size={}x{}",
            window_id,
            surface_id,
            initial_width,
            initial_height
        );

        let host_locked = self.is_host_locked_window(window_id);
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "new_toplevel: window_id={} surface_id={} {}x{} configure_serial={} host_locked={}",
            window_id,
            surface_id,
            initial_width,
            initial_height,
            serial,
            host_locked
        );
        self.pending_compositor_events.push(CompositorEvent::WindowCreated {
            client_id: client_id.clone(),
            window_id,
            surface_id,
            title: String::new(),
            width: initial_width,
            height: initial_height,
            decoration_mode: self.decoration_mode_for_new_window(),
            fullscreen_shell: false,
            host_locked,
        });
        crate::core::wayland::wlr::foreign_toplevel_management::notify_toplevel_created(
            self, window_id,
        );
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "new_toplevel: pushed WindowCreated pending (window_id={})",
            window_id
        );
    }

    fn new_popup(&mut self, surface: PopupSurface, positioner: PositionerState) {
        let wl_surface = surface.wl_surface();
        let Some(client_id) = wl_surface.client().map(|c| c.id()) else {
            return;
        };
        let surface_id = self.ensure_internal_surface_mapping(client_id.clone(), wl_surface);
        let xdg_surface_id =
            self.ensure_xdg_surface_entry(client_id.clone(), wl_surface, surface_id, None);
        let popup_id = surface.xdg_popup().id().protocol_id();

        if let Some(surface_ref) = self.get_surface(surface_id) {
            let mut surface_state = surface_ref.write().unwrap();
            if let Err(e) = surface_state.set_role(SurfaceRole::Popup) {
                tracing::error!("Failed to set role for surface {}: {}", surface_id, e);
                return;
            }
        }

        let geo = positioner.get_unconstrained_geometry(self.popup_target_rect());
        let px = geo.loc.x;
        let py = geo.loc.y;
        let popup_w = geo.size.w;
        let popup_h = geo.size.h;
        let parent_window_id = self.parent_window_for_popup(&surface);

        let window_id = self.next_window_id();
        let popup_data = XdgPopupData {
            surface_id,
            xdg_surface_id,
            window_id,
            parent_id: parent_window_id,
            geometry: (px, py, popup_w, popup_h),
            anchor_rect: (
                positioner.anchor_rect.loc.x,
                positioner.anchor_rect.loc.y,
                positioner.anchor_rect.size.w,
                positioner.anchor_rect.size.h,
            ),
            grabbed: false,
            repositioned_token: None,
            resource: Some(surface.xdg_popup().clone()),
            popup_surface: Some(surface.clone()),
        };

        self.xdg
            .popups
            .insert((client_id.clone(), popup_id), popup_data);
        if let Some(data) = self
            .xdg
            .surfaces
            .get_mut(&(client_id.clone(), xdg_surface_id))
        {
            data.window_id = Some(window_id);
        }
        self.surface_to_window.insert(surface_id, window_id);

        if let Some(surface_res) = self.get_surface(surface_id).and_then(|s| s.read().ok().and_then(|s| s.resource.clone())) {
            for output in self.output_resources.values() {
                if surface_res.client() == output.client() {
                    surface_res.enter(output);
                }
            }
        }

        self.pending_compositor_events.push(CompositorEvent::PopupCreated {
            client_id: client_id.clone(),
            window_id,
            surface_id,
            parent_id: parent_window_id.unwrap_or(0),
            x: px,
            y: py,
            width: popup_w.max(1) as u32,
            height: popup_h.max(1) as u32,
        });

        if let Ok(serial) = surface.send_configure() {
            if let Some(surface_data) = self
                .xdg
                .surfaces
                .get_mut(&(client_id.clone(), xdg_surface_id))
            {
                surface_data.pending_serial = u32::from(serial);
                surface_data.pending_serials.push(u32::from(serial));
            }
        }
    }

    fn grab(&mut self, surface: PopupSurface, _seat: WlSeat, _serial: Serial) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        if let Some(data) = self.xdg.popups.get_mut(&(client_id.clone(), popup_id)) {
            data.grabbed = true;
            if !self
                .seat
                .popup_grab_stack
                .contains(&(client_id.clone(), popup_id))
            {
                self.seat
                    .popup_grab_stack
                    .push((client_id.clone(), popup_id));
            }
        }
    }

    fn reposition_request(&mut self, surface: PopupSurface, positioner: PositionerState, token: u32) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        let geo = positioner.get_unconstrained_geometry(self.popup_target_rect());
        let px = geo.loc.x;
        let py = geo.loc.y;

        if let Some(data) = self.xdg.popups.get_mut(&(client_id.clone(), popup_id)) {
            data.geometry = (px, py, geo.size.w, geo.size.h);
            data.anchor_rect = (
                positioner.anchor_rect.loc.x,
                positioner.anchor_rect.loc.y,
                positioner.anchor_rect.size.w,
                positioner.anchor_rect.size.h,
            );
            data.repositioned_token = Some(token);
            self.pending_compositor_events.push(CompositorEvent::PopupRepositioned {
                window_id: data.window_id,
                x: px,
                y: py,
                width: data.geometry.2 as u32,
                height: data.geometry.3 as u32,
            });
        }

        surface.with_pending_state(|state| {
            state.geometry = geo;
            state.positioner = positioner;
        });
        let _ = surface.send_repositioned(token);
    }

    fn ack_configure(&mut self, surface: WlSurface, configure: Configure) {
        match configure {
            Configure::Toplevel(tl_configure) => {
                self.handle_toplevel_ack_configure(&surface, u32::from(tl_configure.serial));
            }
            Configure::Popup(_) => {
                // Popup configure acks do not participate in host resize transactions today.
            }
        }
    }

    fn title_changed(&mut self, surface: ToplevelSurface) {
        let title = smithay::wayland::compositor::with_states(surface.wl_surface(), |states| {
            states
                .data_map
                .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                .and_then(|attrs| attrs.lock().unwrap().title.clone())
        })
        .unwrap_or_default();

        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let window_id = if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id, toplevel_id)) {
            tl.title = title.clone();
            tl.window_id
        } else {
            return;
        };

        if let Some(window) = self.get_window(window_id) {
            window.write().unwrap().title = title.clone();
        }
        self.pending_compositor_events
            .push(CompositorEvent::WindowTitleChanged { window_id, title });
    }

    fn app_id_changed(&mut self, surface: ToplevelSurface) {
        let app_id = smithay::wayland::compositor::with_states(surface.wl_surface(), |states| {
            states
                .data_map
                .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                .and_then(|attrs| attrs.lock().unwrap().app_id.clone())
        })
        .unwrap_or_default();

        let weston_family =
            crate::core::wayland::xdg::decoration::is_weston_family_app_id(&app_id);
        let force_server = matches!(self.decoration_policy, DecorationPolicy::ForceServer);
        // Weston-family needs an explicit host mode (CSD vs SSD). Force SSD must
        // also re-assert ServerSide once app_id arrives — WindowCreated may have
        // raced before the preference was applied to Rust.
        let should_reassert_decoration = weston_family || force_server;

        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let window_id = if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id, toplevel_id)) {
            tl.app_id = app_id.clone();
            tl.window_id
        } else {
            return;
        };

        if let Some(window) = self.get_window(window_id) {
            let mut w = window.write().unwrap();
            w.app_id = app_id.clone();
        }
        if should_reassert_decoration {
            let xdg_mode =
                crate::core::wayland::xdg::decoration::preferred_xdg_decoration_mode(self, window_id);
            let mode =
                crate::core::wayland::xdg::decoration::decoration_mode_from_xdg(xdg_mode);
            let mut changed = false;
            if let Some(window) = self.get_window(window_id) {
                let mut w = window.write().unwrap();
                if w.decoration_mode != mode {
                    w.decoration_mode = mode;
                    changed = true;
                }
            }
            if changed {
                self.pending_compositor_events.push(CompositorEvent::DecorationModeChanged {
                    window_id,
                    mode,
                });
            }
        }
        self.apply_host_lock_for_app_id(window_id, &app_id);
    }

    fn move_request(&mut self, surface: ToplevelSurface, seat: WlSeat, serial: Serial) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.window_id);
        if window_id.map(|wid| self.is_host_locked_window(wid)).unwrap_or(false) {
            return;
        }
        if let Some(window_id) = self
            .xdg
            .toplevels
            .get(&(client_id, toplevel_id))
            .map(|tl| tl.window_id)
        {
            self.pending_compositor_events
                .push(CompositorEvent::WindowMoveRequested {
                    window_id,
                    seat_id: seat.id().protocol_id(),
                    serial: u32::from(serial),
                });
        }
    }

    fn resize_request(
        &mut self,
        surface: ToplevelSurface,
        seat: WlSeat,
        serial: Serial,
        edges: xdg_toplevel::ResizeEdge,
    ) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        if let Some(window_id) = self
            .xdg
            .toplevels
            .get(&(client_id, toplevel_id))
            .map(|tl| tl.window_id)
        {
            if self.is_host_locked_window(window_id) {
                return;
            }
            self.pending_compositor_events
                .push(CompositorEvent::WindowResizeRequested {
                    window_id,
                    seat_id: seat.id().protocol_id(),
                    serial: u32::from(serial),
                    edges: edges.into(),
                });
        }
    }

    fn minimize_request(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id, toplevel_id))
            .map(|tl| tl.window_id);
        if let Some(window_id) = window_id {
            if let Some(window) = self.get_window(window_id) {
                window.write().unwrap().minimized = true;
            }
            self.pending_compositor_events
                .push(CompositorEvent::WindowMinimized {
                    window_id,
                    minimized: true,
                });
        }
    }

    fn maximize_request(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let output_id = {
            let tl = self.xdg.toplevels.get(&(client_id.clone(), toplevel_id));
            tl.and_then(|tl| self.get_window(tl.window_id))
                .map(|window| {
                    let window = window.read().unwrap();
                    window
                        .outputs
                        .first()
                        .copied()
                        .unwrap_or_else(|| self.outputs.get(self.primary_output).map(|o| o.id).unwrap_or(0))
                })
                .unwrap_or_else(|| self.outputs.get(self.primary_output).map(|o| o.id).unwrap_or(0))
        };
        let (width, height) = self
            .get_usable_region(output_id)
            .map(|(_, _, w, h)| (w, h))
            .unwrap_or((0, 0));

        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.window_id);
        if let Some(wid) = window_id {
            if let Some(geo) = self.get_window(wid).map(|window| {
                let window = window.read().unwrap();
                (window.x, window.y, window.width as u32, window.height as u32)
            }) {
                if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    if tl.saved_geometry.is_none() {
                        tl.saved_geometry = Some(geo);
                    }
                }
            }
            if let Some(window) = self.get_window(wid) {
                window.write().unwrap().maximized = true;
            }
        }
        let (clamped_w, clamped_h) = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.clamp_size(width, height))
            .unwrap_or((width, height));
        if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
            tl.pending_maximized = true;
            tl.pending_fullscreen = false;
        }
        let _ = self.send_toplevel_configure(client_id.clone(), toplevel_id, clamped_w, clamped_h);
        if let Some(window_id) = window_id {
            self.pending_compositor_events
                .push(CompositorEvent::WindowMaximized {
                    window_id,
                    maximized: true,
                });
        }
    }

    fn unmaximize_request(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let saved = self
            .xdg
            .toplevels
            .get_mut(&(client_id.clone(), toplevel_id))
            .and_then(|tl| {
                tl.pending_maximized = false;
                tl.saved_geometry.take()
            });
        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.window_id);
        // Restore the saved pre-maximize geometry only when it reflects a size
        // the client actually chose (i.e. it committed a buffer while floating).
        // Otherwise send 0x0 per xdg-shell: the client decides its own size.
        // Falling back to the current window size here is always wrong — the
        // current size IS the maximized size.
        let client_chose_size = window_id
            .and_then(|wid| self.get_window(wid))
            .map(|window| window.read().unwrap().has_committed_buffer)
            .unwrap_or(false);
        let (restore_w, restore_h) = match saved {
            Some((x, y, w, h)) if client_chose_size && w > 0 && h > 0 => {
                if let Some(wid) = window_id {
                    if let Some(window) = self.get_window(wid) {
                        let mut win = window.write().unwrap();
                        win.maximized = false;
                        win.x = x;
                        win.y = y;
                    }
                }
                (w, h)
            }
            _ => {
                if let Some(wid) = window_id {
                    if let Some(window) = self.get_window(wid) {
                        window.write().unwrap().maximized = false;
                    }
                }
                (0, 0)
            }
        };
        self.send_toplevel_configure(client_id.clone(), toplevel_id, restore_w, restore_h);
        if let Some(window_id) = window_id {
            self.pending_compositor_events
                .push(CompositorEvent::WindowMaximized {
                    window_id,
                    maximized: false,
                });
        }
    }

    fn fullscreen_request(&mut self, surface: ToplevelSurface, output: Option<WlOutput>) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let output_id = if let Some(o) = output {
            self.output_id_by_resource
                .get(&o.id())
                .copied()
                .unwrap_or_else(|| o.id().protocol_id())
        } else {
            self.xdg
                .toplevels
                .get(&(client_id.clone(), toplevel_id))
                .and_then(|tl| self.get_window(tl.window_id))
                .map(|window| {
                    let window = window.read().unwrap();
                    window
                        .outputs
                        .first()
                        .copied()
                        .unwrap_or_else(|| self.outputs.get(self.primary_output).map(|o| o.id).unwrap_or(0))
                })
                .unwrap_or_else(|| self.outputs.get(self.primary_output).map(|o| o.id).unwrap_or(0))
        };
        let (width, height) = self
            .get_output_geometry(output_id)
            .map(|(_, _, w, h)| (w, h))
            .unwrap_or((0, 0));

        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.window_id);
        if let Some(wid) = window_id {
            if let Some(geo) = self.get_window(wid).map(|window| {
                let window = window.read().unwrap();
                (window.x, window.y, window.width as u32, window.height as u32)
            }) {
                if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
                    if tl.saved_geometry.is_none() {
                        tl.saved_geometry = Some(geo);
                    }
                }
            }
            if let Some(window) = self.get_window(wid) {
                let mut window = window.write().unwrap();
                window.fullscreen = true;
                window.maximized = false;
            }
        }
        if let Some(tl) = self.xdg.toplevels.get_mut(&(client_id.clone(), toplevel_id)) {
            tl.pending_fullscreen = true;
            tl.pending_maximized = false;
        }
        let _ = self.send_toplevel_configure(client_id, toplevel_id, width, height);
        if let Some(window_id) = window_id {
            self.pending_compositor_events
                .push(CompositorEvent::WindowFullscreen {
                    window_id,
                    fullscreen: true,
                });
        }
    }

    fn unfullscreen_request(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        let saved = self
            .xdg
            .toplevels
            .get_mut(&(client_id.clone(), toplevel_id))
            .and_then(|tl| {
                tl.pending_fullscreen = false;
                tl.saved_geometry.take()
            });
        let window_id = self
            .xdg
            .toplevels
            .get(&(client_id.clone(), toplevel_id))
            .map(|tl| tl.window_id);
        // Same rule as unmaximize: only restore a saved size the client
        // actually chose; otherwise 0x0 lets the client decide. The current
        // window size is the fullscreen size and must not be echoed back.
        let client_chose_size = window_id
            .and_then(|wid| self.get_window(wid))
            .map(|window| window.read().unwrap().has_committed_buffer)
            .unwrap_or(false);
        let (restore_w, restore_h) = match saved {
            Some((x, y, w, h)) if client_chose_size && w > 0 && h > 0 => {
                if let Some(wid) = window_id {
                    if let Some(window) = self.get_window(wid) {
                        let mut win = window.write().unwrap();
                        win.fullscreen = false;
                        win.x = x;
                        win.y = y;
                    }
                }
                (w, h)
            }
            _ => {
                if let Some(wid) = window_id {
                    if let Some(window) = self.get_window(wid) {
                        window.write().unwrap().fullscreen = false;
                    }
                }
                (0, 0)
            }
        };
        self.send_toplevel_configure(client_id, toplevel_id, restore_w, restore_h);
        if let Some(window_id) = window_id {
            self.pending_compositor_events
                .push(CompositorEvent::WindowFullscreen {
                    window_id,
                    fullscreen: false,
                });
        }
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        if let Some(data) = self.xdg.toplevels.remove(&(client_id.clone(), toplevel_id)) {
            self.remove_window(data.window_id);
            self.xdg
                .surfaces
                .remove(&(client_id, data.xdg_surface_id));
        }
    }

    fn popup_destroyed(&mut self, surface: PopupSurface) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        if let Some(data) = self.xdg.popups.remove(&(client_id.clone(), popup_id)) {
            self.surface_to_window.remove(&data.surface_id);
            self.seat
                .popup_grab_stack
                .retain(|(cid, pid)| cid != &client_id || *pid != popup_id);
            self.pending_compositor_events
                .push(CompositorEvent::WindowDestroyed {
                    window_id: data.window_id,
                });
            self.xdg.surfaces.remove(&(client_id, data.xdg_surface_id));
        }
    }
}
