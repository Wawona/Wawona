//! Implementation of the zxdg_shell_v6 protocol.
//!
//! Provides backwards compatibility for clients speaking the unstable v6
//! xdg-shell protocol. Mapped onto Wawona's common window, toplevel and popup
//! state structures.

pub mod protocol;

use std::sync::{Arc, Mutex};
use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_positioner;
use smithay::utils::{Point, Rectangle};
use smithay::wayland::shell::xdg::PositionerState;
use wayland_server::protocol::wl_output::WlOutput;
use wayland_server::protocol::wl_seat::WlSeat;
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use self::protocol::zxdg_popup_v6::{self, ZxdgPopupV6};
use self::protocol::zxdg_positioner_v6::{self, ZxdgPositionerV6};
use self::protocol::zxdg_shell_v6::{self, ZxdgShellV6};
use self::protocol::zxdg_surface_v6::{self, ZxdgSurfaceV6};
use self::protocol::zxdg_toplevel_v6::{self, ZxdgToplevelV6};

use crate::core::compositor::CompositorEvent;
use crate::core::state::{
    CompositorState, XdgPopupData, XdgSurfaceData, XdgToplevelData,
};
use crate::core::surface::BufferType;
use crate::core::surface::SurfaceRole;
use crate::core::window::Window;

const TOP: u32 = 1;
const BOTTOM: u32 = 2;
const LEFT: u32 = 4;
const RIGHT: u32 = 8;

fn has_parallel_edges(mask: u32) -> bool {
    ((mask & (TOP | BOTTOM)) == (TOP | BOTTOM)) || ((mask & (LEFT | RIGHT)) == (LEFT | RIGHT))
}

fn anchor_from_u32(val: u32) -> xdg_positioner::Anchor {
    match val {
        1 => xdg_positioner::Anchor::Top,
        2 => xdg_positioner::Anchor::Bottom,
        4 => xdg_positioner::Anchor::Left,
        8 => xdg_positioner::Anchor::Right,
        5 => xdg_positioner::Anchor::TopLeft,
        6 => xdg_positioner::Anchor::BottomLeft,
        9 => xdg_positioner::Anchor::TopRight,
        10 => xdg_positioner::Anchor::BottomRight,
        _ => xdg_positioner::Anchor::None,
    }
}

fn gravity_from_u32(val: u32) -> xdg_positioner::Gravity {
    match val {
        1 => xdg_positioner::Gravity::Top,
        2 => xdg_positioner::Gravity::Bottom,
        4 => xdg_positioner::Gravity::Left,
        8 => xdg_positioner::Gravity::Right,
        5 => xdg_positioner::Gravity::TopLeft,
        6 => xdg_positioner::Gravity::BottomLeft,
        9 => xdg_positioner::Gravity::TopRight,
        10 => xdg_positioner::Gravity::BottomRight,
        _ => xdg_positioner::Gravity::None,
    }
}

/// Runtime state for zxdg_shell_v6
#[derive(Debug, Default)]
pub struct XdgV6State {
    pub shells: Vec<ZxdgShellV6>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct V6PositionerData {
    pub size: Option<(i32, i32)>,
    pub anchor_rect: Option<(i32, i32, i32, i32)>,
    pub anchor: u32,
    pub gravity: u32,
    pub constraint_adjustment: u32,
    pub offset: (i32, i32),
}

impl V6PositionerData {
    pub fn to_positioner_state(&self) -> Option<PositionerState> {
        let (w, h) = self.size?;
        let (ax, ay, aw, ah) = self.anchor_rect?;
        Some(PositionerState {
            rect_size: (w, h).into(),
            anchor_rect: Rectangle::new((ax, ay).into(), (aw, ah).into()),
            anchor_edges: anchor_from_u32(self.anchor),
            gravity: gravity_from_u32(self.gravity),
            constraint_adjustment: xdg_positioner::ConstraintAdjustment::from_bits_truncate(
                self.constraint_adjustment,
            ),
            offset: Point::from((self.offset.0, self.offset.1)),
            reactive: false,
            parent_size: None,
            parent_configure: None,
        })
    }
}

pub struct V6SurfaceUserData {
    pub wl_surface: WlSurface,
    pub internal_surface_id: u32,
    pub state: Mutex<V6SurfaceState>,
}

pub struct V6SurfaceState {
    pub role: V6Role,
    pub pending_geometry: Option<(i32, i32, i32, i32)>,
    pub initial_configure_sent: bool,
    pub first_commit_done: bool,
}

pub enum V6Role {
    Unassigned,
    Toplevel(ZxdgToplevelV6),
    Popup(ZxdgPopupV6),
}

pub struct V6ToplevelUserData {
    pub window_id: u32,
    pub surface_id: u32,
    pub xdg_surface_id: u32,
    pub surface_user_data: Arc<V6SurfaceUserData>,
}

pub struct V6PopupUserData {
    pub window_id: u32,
    pub surface_id: u32,
    pub xdg_surface_id: u32,
    pub surface_user_data: Arc<V6SurfaceUserData>,
}

pub fn register(_state: &mut CompositorState, dh: &DisplayHandle) {
    dh.create_global::<CompositorState, ZxdgShellV6, _>(1, ());
}

// ============================================================================
// zxdg_shell_v6
// ============================================================================

impl GlobalDispatch<ZxdgShellV6, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<ZxdgShellV6>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let shell = data_init.init(resource, ());
        state.xdg_v6.shells.push(shell);
    }
}

impl Dispatch<ZxdgShellV6, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        resource: &ZxdgShellV6,
        request: zxdg_shell_v6::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zxdg_shell_v6::Request::Destroy => {
                let client_id = client.id();
                let has_surfaces = state
                    .xdg
                    .surfaces
                    .iter()
                    .any(|((cid, _), s)| cid == &client_id && s.v6_resource.is_some());
                if has_surfaces {
                    resource.post_error(
                        zxdg_shell_v6::Error::DefunctSurfaces,
                        "xdg_shell destroyed before children",
                    );
                }
                state.xdg_v6.shells.retain(|s| s != resource);
            }
            zxdg_shell_v6::Request::CreatePositioner { id } => {
                data_init.init(id, Arc::new(Mutex::new(V6PositionerData::default())));
            }
            zxdg_shell_v6::Request::GetXdgSurface { id, surface } => {
                let client_id = client.id();
                let internal_surface_id =
                    state.ensure_internal_surface_mapping(client_id.clone(), &surface);

                if let Some(surf) = state.get_surface(internal_surface_id) {
                    if let Ok(s) = surf.read() {
                        if s.role != SurfaceRole::None {
                            resource.post_error(
                                zxdg_shell_v6::Error::Role,
                                "wl_surface already has another role",
                            );
                            return;
                        }
                    }
                }

                let user_data = Arc::new(V6SurfaceUserData {
                    wl_surface: surface.clone(),
                    internal_surface_id,
                    state: Mutex::new(V6SurfaceState {
                        role: V6Role::Unassigned,
                        pending_geometry: None,
                        initial_configure_sent: false,
                        first_commit_done: false,
                    }),
                });
                let xdg_surf_resource = data_init.init(id, user_data);
                let xdg_surf_id = xdg_surf_resource.id().protocol_id();

                let mut data = XdgSurfaceData::new(internal_surface_id);
                data.v6_resource = Some(xdg_surf_resource);
                state.xdg.surfaces.insert((client_id, xdg_surf_id), data);
            }
            zxdg_shell_v6::Request::Pong { serial } => {
                state.xdg.pending_pings.remove(&serial);
            }
        }
    }
}

// ============================================================================
// zxdg_positioner_v6
// ============================================================================

impl Dispatch<ZxdgPositionerV6, Arc<Mutex<V6PositionerData>>> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        resource: &ZxdgPositionerV6,
        request: zxdg_positioner_v6::Request,
        data: &Arc<Mutex<V6PositionerData>>,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zxdg_positioner_v6::Request::Destroy => {}
            zxdg_positioner_v6::Request::SetSize { width, height } => {
                if width <= 0 || height <= 0 {
                    resource.post_error(
                        zxdg_positioner_v6::Error::InvalidInput,
                        "zero or negative size",
                    );
                    return;
                }
                if let Ok(mut pos) = data.lock() {
                    pos.size = Some((width, height));
                }
            }
            zxdg_positioner_v6::Request::SetAnchorRect {
                x,
                y,
                width,
                height,
            } => {
                if width <= 0 || height <= 0 {
                    resource.post_error(
                        zxdg_positioner_v6::Error::InvalidInput,
                        "zero or negative anchor rect size",
                    );
                    return;
                }
                if let Ok(mut pos) = data.lock() {
                    pos.anchor_rect = Some((x, y, width, height));
                }
            }
            zxdg_positioner_v6::Request::SetAnchor { anchor } => {
                let mask: u32 = match anchor {
                    wayland_server::WEnum::Value(v) => v.into(),
                    wayland_server::WEnum::Unknown(u) => u,
                };
                if has_parallel_edges(mask) {
                    resource.post_error(
                        zxdg_positioner_v6::Error::InvalidInput,
                        "parallel anchor edges",
                    );
                    return;
                }
                if let Ok(mut pos) = data.lock() {
                    pos.anchor = mask;
                }
            }
            zxdg_positioner_v6::Request::SetGravity { gravity } => {
                let mask: u32 = match gravity {
                    wayland_server::WEnum::Value(v) => v.into(),
                    wayland_server::WEnum::Unknown(u) => u,
                };
                if has_parallel_edges(mask) {
                    resource.post_error(
                        zxdg_positioner_v6::Error::InvalidInput,
                        "parallel gravity edges",
                    );
                    return;
                }
                if let Ok(mut pos) = data.lock() {
                    pos.gravity = mask;
                }
            }
            zxdg_positioner_v6::Request::SetConstraintAdjustment {
                constraint_adjustment,
            } => {
                if let Ok(mut pos) = data.lock() {
                    pos.constraint_adjustment = constraint_adjustment;
                }
            }
            zxdg_positioner_v6::Request::SetOffset { x, y } => {
                if let Ok(mut pos) = data.lock() {
                    pos.offset = (x, y);
                }
            }
        }
    }
}

// ============================================================================
// zxdg_surface_v6
// ============================================================================

impl Dispatch<ZxdgSurfaceV6, Arc<V6SurfaceUserData>> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        resource: &ZxdgSurfaceV6,
        request: zxdg_surface_v6::Request,
        data: &Arc<V6SurfaceUserData>,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zxdg_surface_v6::Request::Destroy => {
                let client_id = client.id();
                let xdg_surf_id = resource.id().protocol_id();
                state.xdg.surfaces.remove(&(client_id, xdg_surf_id));
            }
            zxdg_surface_v6::Request::GetToplevel { id } => {
                let mut surf_state = match data.state.lock() {
                    Ok(guard) => guard,
                    Err(poisoned) => poisoned.into_inner(),
                };
                if !matches!(surf_state.role, V6Role::Unassigned) {
                    resource.post_error(
                        zxdg_surface_v6::Error::AlreadyConstructed,
                        "surface role already assigned",
                    );
                    return;
                }
                if let Some(surf) = state.get_surface(data.internal_surface_id) {
                    if let Ok(s) = surf.read() {
                        if s.current.buffer != BufferType::None {
                            resource.post_error(
                                zxdg_shell_v6::Error::InvalidSurfaceState,
                                "buffer already attached or committed",
                            );
                            return;
                        }
                    }
                }

                let client_id = client.id();
                let xdg_surf_id = resource.id().protocol_id();
                let window_id = state.next_window_id();
                let mut window = Window::new(window_id, data.internal_surface_id);
                window.decoration_policy =
                    state.client_decoration_policy.get(&client_id).copied();
                window.width = 0;
                window.height = 0;
                window.size_authority =
                    crate::core::window::SizeAuthority::AwaitingFirstCommit;

                let tl_user_data = Arc::new(V6ToplevelUserData {
                    window_id,
                    surface_id: data.internal_surface_id,
                    xdg_surface_id: xdg_surf_id,
                    surface_user_data: data.clone(),
                });
                let tl_resource = data_init.init(id, tl_user_data);
                let toplevel_id = tl_resource.id().protocol_id();

                let mut tl_data =
                    XdgToplevelData::new(window_id, data.internal_surface_id, xdg_surf_id);
                tl_data.v6_resource = Some(tl_resource.clone());
                state
                    .xdg
                    .toplevels
                    .insert((client_id.clone(), toplevel_id), tl_data);

                if let Some(s) = state
                    .xdg
                    .surfaces
                    .get_mut(&(client_id.clone(), xdg_surf_id))
                {
                    s.window_id = Some(window_id);
                }
                state
                    .surface_to_window
                    .insert(data.internal_surface_id, window_id);
                state.add_window(window);

                let host_locked = state.is_host_locked_window(window_id);
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowCreated {
                        client_id: client_id.clone(),
                        window_id,
                        surface_id: data.internal_surface_id,
                        title: String::new(),
                        width: 0,
                        height: 0,
                        decoration_mode: crate::core::state::CompositorState::decoration_mode_for_policy(
                            state.effective_decoration_policy(Some(&client_id)),
                        ),
                        fullscreen_shell: false,
                        host_locked,
                        fills_host: false,
                    });
                crate::core::wayland::wlr::foreign_toplevel_management::notify_toplevel_created(
                    state, window_id,
                );

                if let Some(surface_ref) = state.get_surface(data.internal_surface_id) {
                    if let Ok(mut surface_state) = surface_ref.write() {
                        let _ = surface_state.set_role(SurfaceRole::Toplevel);
                    }
                }
                surf_state.role = V6Role::Toplevel(tl_resource.clone());

                let serial = state.next_serial();
                tl_resource.configure(0, 0, Vec::new());
                resource.configure(serial);

                if let Some(s) = state
                    .xdg
                    .surfaces
                    .get_mut(&(client_id.clone(), xdg_surf_id))
                {
                    s.pending_serial = serial;
                    s.pending_serials.push(serial);
                    s.configured = false;
                }
                if let Some(tl) = state.xdg.toplevels.get_mut(&(client_id, toplevel_id)) {
                    tl.pending_serial = serial;
                }
                surf_state.initial_configure_sent = true;
            }
            zxdg_surface_v6::Request::GetPopup {
                id,
                parent,
                positioner,
            } => {
                let mut surf_state = match data.state.lock() {
                    Ok(guard) => guard,
                    Err(poisoned) => poisoned.into_inner(),
                };
                if !matches!(surf_state.role, V6Role::Unassigned) {
                    resource.post_error(
                        zxdg_surface_v6::Error::AlreadyConstructed,
                        "surface role already assigned",
                    );
                    return;
                }

                let pos_user_data = positioner.data::<Arc<Mutex<V6PositionerData>>>();
                let pos_data = pos_user_data.and_then(|u| u.lock().ok().map(|p| *p));
                let pos_data = match pos_data {
                    Some(p) if p.size.is_some() && p.anchor_rect.is_some() => p,
                    _ => {
                        resource.post_error(
                            zxdg_shell_v6::Error::InvalidPositioner,
                            "incomplete positioner",
                        );
                        return;
                    }
                };

                let parent_id = parent.id().protocol_id();
                let client_id = client.id();
                let parent_surface = state
                    .xdg
                    .surfaces
                    .get(&(client_id.clone(), parent_id));
                let parent_window_id = parent_surface.and_then(|s| s.window_id);

                let pos_state = match pos_data.to_positioner_state() {
                    Some(ps) => ps,
                    None => return,
                };
                let geo = pos_state
                    .get_unconstrained_geometry(state.popup_target_rect_for(parent_window_id));
                let px = geo.loc.x;
                let py = geo.loc.y;
                let popup_w = geo.size.w;
                let popup_h = geo.size.h;

                let window_id = state.next_window_id();
                let popup_user_data = Arc::new(V6PopupUserData {
                    window_id,
                    surface_id: data.internal_surface_id,
                    xdg_surface_id: resource.id().protocol_id(),
                    surface_user_data: data.clone(),
                });
                let popup_resource = data_init.init(id, popup_user_data);
                let popup_id = popup_resource.id().protocol_id();
                let xdg_surf_id = resource.id().protocol_id();

                let anchor_rect = pos_data.anchor_rect.unwrap_or((0, 0, 0, 0));
                let popup_data = XdgPopupData {
                    surface_id: data.internal_surface_id,
                    xdg_surface_id: xdg_surf_id,
                    window_id,
                    parent_id: parent_window_id,
                    parent_surface_id: None,
                    geometry: (px, py, popup_w, popup_h),
                    anchor_rect,
                    grabbed: false,
                    repositioned_token: None,
                    resource: None,
                    popup_surface: None,
                    v6_resource: Some(popup_resource.clone()),
                };
                state
                    .xdg
                    .popups
                    .insert((client_id.clone(), popup_id), popup_data);
                state
                    .surface_to_window
                    .insert(data.internal_surface_id, window_id);
                state
                    .pending_compositor_events
                    .push(CompositorEvent::PopupCreated {
                        client_id: client_id.clone(),
                        window_id,
                        surface_id: data.internal_surface_id,
                        parent_id: parent_window_id.unwrap_or(0),
                        x: px,
                        y: py,
                        width: popup_w.max(1) as u32,
                        height: popup_h.max(1) as u32,
                    });

                if let Some(s) = state
                    .xdg
                    .surfaces
                    .get_mut(&(client_id.clone(), xdg_surf_id))
                {
                    s.window_id = Some(window_id);
                }
                if let Some(surface_ref) = state.get_surface(data.internal_surface_id) {
                    if let Ok(mut surface_state) = surface_ref.write() {
                        let _ = surface_state.set_role(SurfaceRole::Popup);
                    }
                }
                surf_state.role = V6Role::Popup(popup_resource.clone());

                let serial = state.next_serial();
                popup_resource.configure(px, py, popup_w, popup_h);
                resource.configure(serial);

                if let Some(s) = state.xdg.surfaces.get_mut(&(client_id, xdg_surf_id)) {
                    s.pending_serial = serial;
                    s.pending_serials.push(serial);
                    s.configured = false;
                }
                surf_state.initial_configure_sent = true;
            }
            zxdg_surface_v6::Request::SetWindowGeometry {
                x,
                y,
                width,
                height,
            } => {
                let mut surf_state = match data.state.lock() {
                    Ok(guard) => guard,
                    Err(poisoned) => poisoned.into_inner(),
                };
                if matches!(surf_state.role, V6Role::Unassigned) {
                    resource.post_error(
                        zxdg_surface_v6::Error::NotConstructed,
                        "role not assigned",
                    );
                    return;
                }
                if width <= 0 || height <= 0 {
                    return;
                }
                surf_state.pending_geometry = Some((x, y, width, height));
            }
            zxdg_surface_v6::Request::AckConfigure { serial } => {
                let client_id = client.id();
                let xdg_surf_id = resource.id().protocol_id();

                if let Some(surface_data) =
                    state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surf_id))
                {
                    if serial > surface_data.last_acked_serial {
                        surface_data.last_acked_serial = serial;
                    }
                    if !surface_data.pending_serials.is_empty() {
                        if let Some(pos) = surface_data
                            .pending_serials
                            .iter()
                            .position(|&p| p == serial)
                        {
                            surface_data.pending_serials.drain(..=pos);
                            surface_data.pending_serial =
                                surface_data.pending_serials.last().copied().unwrap_or(0);
                            surface_data.configured = surface_data.pending_serials.is_empty();
                        }
                    } else if serial == surface_data.pending_serial {
                        surface_data.configured = true;
                        surface_data.pending_serial = 0;
                    }
                }

                if let Some((_, tl_data)) = state
                    .xdg
                    .toplevels
                    .iter_mut()
                    .find(|((cid, _), tl)| *cid == client_id && tl.xdg_surface_id == xdg_surf_id)
                {
                    if tl_data.pending_serial == serial {
                        if serial > tl_data.last_acked_serial {
                            tl_data.last_acked_serial = serial;
                        }
                        tl_data.pending_serial = 0;
                        tl_data.maximized = tl_data.pending_maximized;
                        tl_data.fullscreen = tl_data.pending_fullscreen;
                        let window_id = tl_data.window_id;
                        let max = tl_data.maximized;
                        let fs = tl_data.fullscreen;
                        if let Some(window) = state.get_window(window_id) {
                            if let Ok(mut win) = window.write() {
                                win.maximized = max;
                                win.fullscreen = fs;
                            }
                        }
                    }
                }
            }
        }
    }
}

// ============================================================================
// zxdg_toplevel_v6
// ============================================================================

impl Dispatch<ZxdgToplevelV6, Arc<V6ToplevelUserData>> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        resource: &ZxdgToplevelV6,
        request: zxdg_toplevel_v6::Request,
        data: &Arc<V6ToplevelUserData>,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let client_id = client.id();
        let toplevel_id = resource.id().protocol_id();

        match request {
            zxdg_toplevel_v6::Request::Destroy => {
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .remove(&(client_id.clone(), toplevel_id))
                {
                    state.surface_to_window.remove(&tl_data.surface_id);
                    state.remove_window(tl_data.window_id);
                    state
                        .xdg
                        .surfaces
                        .remove(&(client_id, tl_data.xdg_surface_id));
                    state
                        .pending_compositor_events
                        .push(CompositorEvent::WindowDestroyed {
                            window_id: tl_data.window_id,
                        });
                    state.repick_headless_global_pointer();
                }
                if let Ok(mut st) = data.surface_user_data.state.lock() {
                    st.role = V6Role::Unassigned;
                }
            }
            zxdg_toplevel_v6::Request::SetParent { parent } => {
                let parent_window_id = parent.as_ref().and_then(|p| {
                    p.data::<Arc<V6ToplevelUserData>>().map(|u| u.window_id)
                });
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .get_mut(&(client_id, toplevel_id))
                {
                    tl_data.parent = parent_window_id;
                }
            }
            zxdg_toplevel_v6::Request::SetTitle { title } => {
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .get_mut(&(client_id, toplevel_id))
                {
                    tl_data.title = title.clone();
                }
                state.update_window(data.window_id, |w| {
                    w.title = title;
                });
            }
            zxdg_toplevel_v6::Request::SetAppId { app_id } => {
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .get_mut(&(client_id, toplevel_id))
                {
                    tl_data.app_id = app_id.clone();
                }
                state.update_window(data.window_id, |w| {
                    w.app_id = app_id;
                });
            }
            zxdg_toplevel_v6::Request::ShowWindowMenu { .. } => {}
            zxdg_toplevel_v6::Request::Move { seat, serial } => {
                let serial_u32: u32 = serial;
                if state.start_interactive_grab(data.window_id, None) {
                    return;
                }
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowMoveRequested {
                        window_id: data.window_id,
                        seat_id: seat.id().protocol_id(),
                        serial: serial_u32,
                    });
            }
            zxdg_toplevel_v6::Request::Resize {
                seat,
                serial,
                edges,
            } => {
                let grab_edges = crate::core::input::interactive_grab::GrabEdges::from_xdg(edges);
                if state.start_interactive_grab(data.window_id, Some(grab_edges)) {
                    return;
                }
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowResizeRequested {
                        window_id: data.window_id,
                        seat_id: seat.id().protocol_id(),
                        serial,
                        edges,
                    });
            }
            zxdg_toplevel_v6::Request::SetMaxSize { width, height } => {
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .get_mut(&(client_id, toplevel_id))
                {
                    tl_data.max_width = width;
                    tl_data.max_height = height;
                }
            }
            zxdg_toplevel_v6::Request::SetMinSize { width, height } => {
                if let Some(tl_data) = state
                    .xdg
                    .toplevels
                    .get_mut(&(client_id, toplevel_id))
                {
                    tl_data.min_width = width;
                    tl_data.min_height = height;
                }
            }
            zxdg_toplevel_v6::Request::SetMaximized => {
                state.maximize_toplevel((client_id, toplevel_id));
            }
            zxdg_toplevel_v6::Request::UnsetMaximized => {
                state.unmaximize_toplevel((client_id, toplevel_id));
            }
            zxdg_toplevel_v6::Request::SetFullscreen { output } => {
                state.fullscreen_toplevel((client_id, toplevel_id), output);
            }
            zxdg_toplevel_v6::Request::UnsetFullscreen => {
                state.unfullscreen_toplevel((client_id, toplevel_id));
            }
            zxdg_toplevel_v6::Request::SetMinimized => {
                state.minimize_toplevel((client_id, toplevel_id));
            }
        }
    }
}

// ============================================================================
// zxdg_popup_v6
// ============================================================================

impl Dispatch<ZxdgPopupV6, Arc<V6PopupUserData>> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        resource: &ZxdgPopupV6,
        request: zxdg_popup_v6::Request,
        data: &Arc<V6PopupUserData>,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let client_id = client.id();
        let popup_id = resource.id().protocol_id();
        let key = (client_id, popup_id);

        match request {
            zxdg_popup_v6::Request::Destroy => {
                if let Some(popup_data) = state.xdg.popups.remove(&key) {
                    state.surface_to_window.remove(&popup_data.surface_id);
                    state.remove_window(popup_data.window_id);
                    state.end_popup_grab_for(&key, popup_data.surface_id);
                    state
                        .pending_compositor_events
                        .push(CompositorEvent::WindowDestroyed {
                            window_id: popup_data.window_id,
                        });
                    state.repick_headless_global_pointer();
                }
                if let Ok(mut st) = data.surface_user_data.state.lock() {
                    st.role = V6Role::Unassigned;
                }
            }
            zxdg_popup_v6::Request::Grab { .. } => {
                state.begin_popup_grab(key);
            }
        }
    }
}

// ============================================================================
// CompositorState commit hook
// ============================================================================

impl CompositorState {
    pub(crate) fn apply_v6_commit(&mut self, surface_id: u32, has_buffer: bool) {
        let (cid, xdg_surf_id, v6_res) = match self
            .xdg
            .surfaces
            .iter()
            .find(|(_, s)| s.surface_id == surface_id && s.v6_resource.is_some())
            .and_then(|(k, s)| s.v6_resource.clone().map(|res| (k.0.clone(), k.1, res)))
        {
            Some(v) => v,
            None => return,
        };

        let ud = match v6_res.data::<Arc<V6SurfaceUserData>>() {
            Some(ud) => ud.clone(),
            None => return,
        };

        let (pending_geo, send_initial_configure) = {
            let mut st = match ud.state.lock() {
                Ok(guard) => guard,
                Err(p) => p.into_inner(),
            };
            let pending_geo = st.pending_geometry.take();
            let mut send_initial = false;
            if !st.first_commit_done && has_buffer {
                st.first_commit_done = true;
                if self.headless_host {
                    send_initial = true;
                }
            }
            (pending_geo, send_initial)
        };

        if let Some(geo) = pending_geo {
            if let Some(s) = self.xdg.surfaces.get_mut(&(cid.clone(), xdg_surf_id)) {
                s.geometry = Some(geo);
            }
        }

        if send_initial_configure {
            if let Some(tl_key) = self
                .xdg
                .toplevels
                .iter()
                .find(|((c, _), tl)| *c == cid && tl.xdg_surface_id == xdg_surf_id)
                .map(|(k, _)| k.clone())
            {
                self.send_toplevel_configure(tl_key.0, tl_key.1, 0, 0);
            }
        }
    }
}
