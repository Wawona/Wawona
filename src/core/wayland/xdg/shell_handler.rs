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
use crate::core::state::{
    CompositorState, DecorationPolicy, XdgPopupData, XdgSurfaceData, XdgToplevelData,
};
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
        self.xdg
            .popups
            .get(&(client_id, popup_id))
            .map(|_| (surface.wl_surface().client().unwrap().id(), popup_id))
    }

    pub(crate) fn ensure_xdg_surface_entry(
        &mut self,
        client_id: ClientId,
        wl_surface: &WlSurface,
        surface_id: u32,
        window_id: Option<u32>,
    ) -> u32 {
        let xdg_surface_key = wl_surface.id().protocol_id();
        let key = (client_id.clone(), xdg_surface_key);
        self.xdg.surfaces.entry(key.clone()).or_insert_with(|| {
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

    /// Send a popup's configure and record its serial for ack validation.
    pub(crate) fn send_popup_configure(
        &mut self,
        surface: &PopupSurface,
        client_id: ClientId,
        xdg_surface_id: u32,
    ) {
        match surface.send_configure() {
            Ok(serial) => {
                if let Some(data) = self.xdg.surfaces.get_mut(&(client_id, xdg_surface_id)) {
                    data.pending_serial = u32::from(serial);
                    data.pending_serials.push(u32::from(serial));
                }
            }
            Err(err) => tracing::debug!("popup configure not sent: {err:?}"),
        }
    }

    /// Initial commit of a popup that never received a parent: configure it
    /// against the output so the client is not left waiting.
    pub(crate) fn configure_parentless_popup_on_commit(&mut self, wl_surface: &WlSurface) {
        let Some(client_id) = wl_surface.client().map(|c| c.id()) else {
            return;
        };
        let pending = self.xdg.popups.values().find_map(|p| {
            let surface = p.popup_surface.as_ref()?;
            (surface.wl_surface() == wl_surface && !surface.is_initial_configure_sent())
                .then(|| (surface.clone(), p.xdg_surface_id))
        });
        if let Some((surface, xdg_surface_id)) = pending {
            self.send_popup_configure(&surface, client_id, xdg_surface_id);
        }
    }
    pub(crate) fn popup_target_rect(&self) -> Rectangle<i32, Logical> {
        let output = self.primary_output();
        Rectangle::new(
            (output.x, output.y).into(),
            (output.width as i32, output.height as i32).into(),
        )
    }

    /// Popup constraint target in the parent's coordinate space (positioner
    /// geometry is parent-relative).
    pub(crate) fn popup_target_rect_for(&self, parent_window: Option<u32>) -> Rectangle<i32, Logical> {
        let mut rect = self.popup_target_rect();
        if let Some((px, py)) = parent_window.and_then(|wid| self.window_origin(wid)) {
            rect.loc.x -= px;
            rect.loc.y -= py;
        }
        rect
    }

    /// Absolute origin of a toplevel window or of a popup (parent origin plus
    /// popup geometry, up the popup chain).
    pub(crate) fn window_origin(&self, window_id: u32) -> Option<(i32, i32)> {
        let mut id = window_id;
        let (mut ox, mut oy) = (0i32, 0i32);
        // Popup chains are short; the bound stops a malformed parent loop.
        for _ in 0..32 {
            if let Some(window) = self.get_window(id) {
                let w = window.read().unwrap();
                return Some((ox.saturating_add(w.x), oy.saturating_add(w.y)));
            }
            let popup = self.xdg.popups.values().find(|p| p.window_id == id)?;
            ox = ox.saturating_add(popup.geometry.0);
            oy = oy.saturating_add(popup.geometry.1);
            id = popup.parent_id?;
        }
        None
    }

    /// Re-place reactive popups under `moved_window` after it moved
    /// (xdg_positioner.set_reactive). Non-reactive popups keep their
    /// parent-relative geometry and simply move with the parent.
    pub fn reconstrain_reactive_popups(&mut self, moved_window: u32) {
        let children: Vec<_> = self
            .xdg
            .popups
            .iter()
            .filter(|(_, p)| p.parent_id == Some(moved_window))
            .map(|(key, p)| (key.clone(), p.popup_surface.clone(), p.window_id))
            .collect();
        for (key, surface, popup_window) in children {
            let Some(surface) = surface else {
                continue;
            };
            let positioner = surface.with_pending_state(|state| state.positioner);
            if positioner.reactive {
                let geo = positioner
                    .get_unconstrained_geometry(self.popup_target_rect_for(Some(moved_window)));
                let rect = (geo.loc.x, geo.loc.y, geo.size.w, geo.size.h);
                let changed = self
                    .xdg
                    .popups
                    .get_mut(&key)
                    .is_some_and(|p| std::mem::replace(&mut p.geometry, rect) != rect);
                if changed {
                    surface.with_pending_state(|state| state.geometry = geo);
                    if let Err(err) = surface.send_configure() {
                        tracing::debug!("reactive popup configure not sent: {err:?}");
                    }
                }
            }
            self.reconstrain_reactive_popups(popup_window);
        }
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
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_wl_surface(wl_surface)
        else {
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
                    surface_data.pending_serial =
                        surface_data.pending_serials.last().copied().unwrap_or(0);
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

        // Force SSD per-machine (#120): the first toplevel from a client claims
        // the policy the host staged for this machine's launch, and the window
        // pins it so a concurrent machine toggling Force SSD cannot restyle it.
        self.claim_pending_decoration_policy(&client_id);
        self.claim_pending_fills_host(&client_id);
        let client_policy = self.client_decoration_policy.get(&client_id).copied();
        let fill_host_size = self.fill_host_configure_size(&client_id);

        let window_id = self.next_window_id();
        let mut window = Window::new(window_id, surface_id);
        window.decoration_policy = client_policy;
        // OWL / xdg-shell: initial configure is 0x0 ("client decides") for
        // demos. Nested weston/niri copy the first configure into their
        // output mode; 0x0 means no mode and a blank parent window. Those
        // clients are staged fill-host before launch.
        let (initial_width, initial_height) = match fill_host_size {
            Some((w, h)) => (w.max(1) as u32, h.max(1) as u32),
            None => (0u32, 0u32),
        };
        window.width = initial_width as i32;
        window.height = initial_height as i32;
        window.fills_host = fill_host_size.is_some();
        window.size_authority = if window.fills_host {
            crate::core::window::SizeAuthority::Host {
                requested_w: initial_width.max(1),
                requested_h: initial_height.max(1),
                configure_serial: 0,
                generation: self.next_size_generation(),
            }
        } else {
            crate::core::window::SizeAuthority::AwaitingFirstCommit
        };

        let mut toplevel_data = XdgToplevelData::new(window_id, surface_id, xdg_surface_id);
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

        // Demos: configure(0,0) so the client picks (flower/smoke 200x200).
        // Nested compositors: non-zero fill-host size. Weston's wayland
        // backend copies configure into wl_output.mode; a later inject does
        // not recover from a 0x0 first mode.
        let (configure_w, configure_h) = match fill_host_size {
            Some((w, h)) => (w.max(1), h.max(1)),
            None => (0i32, 0i32),
        };
        if fill_host_size.is_some() {
            crate::wlog!(
                crate::util::logging::COMPOSITOR,
                "new_toplevel: fill-host configure {}x{} (nested compositor)",
                configure_w,
                configure_h
            );
        }

        surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Activated);
            state.size = Some((configure_w, configure_h).into());
        });
        let serial = u32::from(surface.send_configure());
        if fill_host_size.is_some() {
            if let Some(window_ref) = self.get_window(window_id) {
                let mut window = window_ref.write().unwrap();
                window.size_authority = window.size_authority.clone().on_configure_sent(serial);
            }
        }

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
        self.pending_compositor_events
            .push(CompositorEvent::WindowCreated {
                client_id: client_id.clone(),
                window_id,
                surface_id,
                title: String::new(),
                width: initial_width,
                height: initial_height,
                decoration_mode: crate::core::state::CompositorState::decoration_mode_for_policy(
                    self.effective_decoration_policy(Some(&client_id)),
                ),
                fullscreen_shell: false,
                host_locked,
                fills_host: fill_host_size.is_some(),
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

        let positioner =
            super::surface_validation::restore_zero_anchor(positioner, self.pending_zero_anchor);
        let parent_window_id = self.parent_window_for_popup(&surface);
        let geo =
            positioner.get_unconstrained_geometry(self.popup_target_rect_for(parent_window_id));
        surface.with_pending_state(|state| {
            state.positioner = positioner;
            state.geometry = geo;
        });
        let px = geo.loc.x;
        let py = geo.loc.y;
        let popup_w = geo.size.w;
        let popup_h = geo.size.h;

        let window_id = self.next_window_id();
        let popup_data = XdgPopupData {
            surface_id,
            xdg_surface_id,
            window_id,
            parent_id: parent_window_id,
            parent_surface_id: None,
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
            v6_resource: None,
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

        self.pending_compositor_events
            .push(CompositorEvent::PopupCreated {
                client_id: client_id.clone(),
                window_id,
                surface_id,
                parent_id: parent_window_id.unwrap_or(0),
                x: px,
                y: py,
                width: popup_w.max(1) as u32,
                height: popup_h.max(1) as u32,
            });

        // A parentless popup gets its parent from another protocol
        // (zwlr_layer_surface_v1.get_popup) before its initial commit, and a
        // non-reactive popup accepts exactly one configure. Configure it once
        // the parent is known, or at its initial commit if none ever is.
        if surface.get_parent_surface().is_some() {
            self.send_popup_configure(&surface, client_id, xdg_surface_id);
        }
    }

    fn grab(&mut self, surface: PopupSurface, _seat: WlSeat, _serial: Serial) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        self.begin_popup_grab((client_id, popup_id));
    }

    fn reposition_request(
        &mut self,
        surface: PopupSurface,
        positioner: PositionerState,
        token: u32,
    ) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        let positioner =
            super::surface_validation::restore_zero_anchor(positioner, self.pending_zero_anchor);
        let parent_window_id = self
            .xdg
            .popups
            .get(&(client_id.clone(), popup_id))
            .and_then(|p| p.parent_id);
        let geo =
            positioner.get_unconstrained_geometry(self.popup_target_rect_for(parent_window_id));
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
            self.pending_compositor_events
                .push(CompositorEvent::PopupRepositioned {
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
        surface.send_repositioned(token);
        // xdg_popup.reposition: `repositioned` is followed by a fresh
        // xdg_popup.configure + xdg_surface.configure.
        if let Err(err) = surface.send_configure() {
            tracing::debug!("reposition configure not sent: {err:?}");
        }
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

        if let Some(Ok(mut window)) = self.get_window(window_id).as_ref().map(|w| w.write()) {
            window.title = title.clone();
        }
        self.refresh_foreign_toplevel(window_id);
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

        let weston_family = crate::core::wayland::xdg::decoration::is_weston_family_app_id(&app_id);

        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        // Force SSD per-machine (#120): resolve against this client's override,
        // not the global policy, so re-asserting SSD after app_id arrives does
        // not leak a concurrent machine's Force SSD onto this client.
        let force_server = matches!(
            self.effective_decoration_policy(Some(&client_id)),
            DecorationPolicy::ForceServer
        );
        // Weston-family needs an explicit host mode (CSD vs SSD). Force SSD must
        // also re-assert ServerSide once app_id arrives. WindowCreated may have
        // raced before the preference was applied to Rust.
        let should_reassert_decoration = weston_family || force_server;

        let window_id = if let Some(tl) = self
            .xdg
            .toplevels
            .get_mut(&(client_id.clone(), toplevel_id))
        {
            tl.app_id = app_id.clone();
            tl.window_id
        } else {
            return;
        };

        if let Some(Ok(mut window)) = self.get_window(window_id).as_ref().map(|w| w.write()) {
            window.app_id = app_id.clone();
        }
        self.refresh_foreign_toplevel(window_id);
        if should_reassert_decoration {
            let xdg_mode = crate::core::wayland::xdg::decoration::preferred_xdg_decoration_mode(
                self, window_id,
            );
            let mode = crate::core::wayland::xdg::decoration::decoration_mode_from_xdg(xdg_mode);
            let mut changed = false;
            if let Some(window) = self.get_window(window_id) {
                let mut w = window.write().unwrap();
                if w.decoration_mode != mode {
                    w.decoration_mode = mode;
                    changed = true;
                }
            }
            if changed {
                self.pending_compositor_events
                    .push(CompositorEvent::DecorationModeChanged { window_id, mode });
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
        if window_id
            .map(|wid| self.is_host_locked_window(wid))
            .unwrap_or(false)
        {
            return;
        }
        if let Some(window_id) = self
            .xdg
            .toplevels
            .get(&(client_id, toplevel_id))
            .map(|tl| tl.window_id)
        {
            if self.start_interactive_grab(window_id, None) {
                return;
            }
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
            let grab_edges =
                crate::core::input::interactive_grab::GrabEdges::from_xdg(edges.into());
            if self.start_interactive_grab(window_id, Some(grab_edges)) {
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
        if let Some(key) = self.xdg_toplevel_key_for_surface(&surface) {
            self.minimize_toplevel(key);
        }
    }

    fn maximize_request(&mut self, surface: ToplevelSurface) {
        if let Some(key) = self.xdg_toplevel_key_for_surface(&surface) {
            self.maximize_toplevel(key);
        }
    }

    fn unmaximize_request(&mut self, surface: ToplevelSurface) {
        if let Some(key) = self.xdg_toplevel_key_for_surface(&surface) {
            self.unmaximize_toplevel(key);
        }
    }

    fn fullscreen_request(&mut self, surface: ToplevelSurface, output: Option<WlOutput>) {
        if let Some(key) = self.xdg_toplevel_key_for_surface(&surface) {
            self.fullscreen_toplevel(key, output);
        }
    }

    fn unfullscreen_request(&mut self, surface: ToplevelSurface) {
        if let Some(key) = self.xdg_toplevel_key_for_surface(&surface) {
            self.unfullscreen_toplevel(key);
        }
    }

    fn toplevel_destroyed(&mut self, surface: ToplevelSurface) {
        let Some((client_id, toplevel_id)) = self.xdg_toplevel_key_for_surface(&surface) else {
            return;
        };
        if let Some(data) = self.xdg.toplevels.remove(&(client_id.clone(), toplevel_id)) {
            self.remove_window(data.window_id);
            self.xdg.surfaces.remove(&(client_id, data.xdg_surface_id));
        }
    }

    fn popup_destroyed(&mut self, surface: PopupSurface) {
        let Some(client_id) = surface.wl_surface().client().map(|c| c.id()) else {
            return;
        };
        let popup_id = surface.xdg_popup().id().protocol_id();
        if let Some(data) = self.xdg.popups.remove(&(client_id.clone(), popup_id)) {
            self.surface_to_window.remove(&data.surface_id);
            self.end_popup_grab_for(&(client_id.clone(), popup_id), data.surface_id);
            self.pending_compositor_events
                .push(CompositorEvent::WindowDestroyed {
                    window_id: data.window_id,
                });
            self.xdg.surfaces.remove(&(client_id, data.xdg_surface_id));
            // Leave the popup while its wl_surface still exists.
            self.repick_headless_global_pointer();
        }
    }
}
