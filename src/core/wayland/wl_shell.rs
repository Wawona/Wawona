//! Implementation of the legacy wl_shell protocol.
//!
//! Maps wl_shell and wl_shell_surface onto Wawona's common window and toplevel
//! state machinery.

use std::sync::{Arc, Mutex};
use wayland_server::backend::ClientId;
use wayland_server::protocol::wl_output::WlOutput;
use wayland_server::protocol::wl_seat::WlSeat;
use wayland_server::protocol::wl_shell::{self, WlShell};
use wayland_server::protocol::wl_shell_surface::{self, WlShellSurface};
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::compositor::CompositorEvent;
use crate::core::state::CompositorState;
use crate::core::surface::SurfaceRole;
use crate::core::window::Window;

/// Runtime state for wl_shell
#[derive(Debug, Default)]
pub struct WlShellState {
    pub shells: Vec<WlShell>,
}

pub struct WlShellSurfaceUserData {
    pub window_id: u32,
    pub surface_id: u32,
    pub wl_surface: WlSurface,
    pub client_id: ClientId,
    pub state: Mutex<WlShellSurfaceState>,
}

pub struct WlShellSurfaceState {
    pub role: WlShellRole,
    pub title: String,
    pub class: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WlShellRole {
    Toplevel,
    Transient {
        parent_surface_id: u32,
        x: i32,
        y: i32,
        inactive: bool,
    },
    Popup {
        parent_surface_id: u32,
        x: i32,
        y: i32,
    },
    Fullscreen,
    Maximized,
}

pub fn register(_state: &mut CompositorState, dh: &DisplayHandle) {
    dh.create_global::<CompositorState, WlShell, _>(1, ());
}

impl GlobalDispatch<WlShell, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<WlShell>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let shell = data_init.init(resource, ());
        state.wl_shell.shells.push(shell);
    }
}

impl Dispatch<WlShell, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        resource: &WlShell,
        request: wl_shell::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_shell::Request::GetShellSurface { id, surface } => {
                let client_id = client.id();
                let internal_surface_id =
                    state.ensure_internal_surface_mapping(client_id.clone(), &surface);

                if let Some(surf) = state.get_surface(internal_surface_id) {
                    if let Ok(s) = surf.read() {
                        if s.role != SurfaceRole::None {
                            resource.post_error(
                                wl_shell::Error::Role,
                                "wl_surface already has another role",
                            );
                            return;
                        }
                    }
                }

                if let Some(surf) = state.get_surface(internal_surface_id) {
                    if let Ok(mut s) = surf.write() {
                        let _ = s.set_role(SurfaceRole::Toplevel);
                    }
                }

                let window_id = state.next_window_id();
                let mut window = Window::new(window_id, internal_surface_id);
                window.app_id = "wl_shell_client".to_string();

                if let Some(surf) = state.get_surface(internal_surface_id) {
                    if let Ok(s) = surf.read() {
                        if s.current.width > 0 && s.current.height > 0 {
                            window.width = s.current.width;
                            window.height = s.current.height;
                            window.has_committed_buffer = true;
                        }
                    }
                }

                let has_buffer = window.has_committed_buffer;
                let width = window.width.max(0) as u32;
                let height = window.height.max(0) as u32;
                state.register_window(internal_surface_id, window);
                state.surface_to_window.insert(internal_surface_id, window_id);

                if has_buffer && state.headless_host {
                    state.window_tree.bring_to_front(window_id);
                }

                let host_locked = state.is_host_locked_window(window_id);
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowCreated {
                        client_id: client_id.clone(),
                        window_id,
                        surface_id: internal_surface_id,
                        title: String::new(),
                        width,
                        height,
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

                let user_data = Arc::new(WlShellSurfaceUserData {
                    window_id,
                    surface_id: internal_surface_id,
                    wl_surface: surface,
                    client_id,
                    state: Mutex::new(WlShellSurfaceState {
                        role: WlShellRole::Toplevel,
                        title: String::new(),
                        class: String::new(),
                    }),
                });

                data_init.init(id, user_data);
            }
            _ => {}
        }
    }
}

impl Dispatch<WlShellSurface, Arc<WlShellSurfaceUserData>> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &WlShellSurface,
        request: wl_shell_surface::Request,
        data: &Arc<WlShellSurfaceUserData>,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_shell_surface::Request::Pong { .. } => {}
            wl_shell_surface::Request::Move { seat, serial } => {
                if state.start_interactive_grab(data.window_id, None) {
                    return;
                }
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowMoveRequested {
                        window_id: data.window_id,
                        seat_id: seat.id().protocol_id(),
                        serial,
                    });
            }
            wl_shell_surface::Request::Resize {
                seat,
                serial,
                edges,
            } => {
                let edges_val: u32 = match edges {
                    wayland_server::WEnum::Value(v) => v.into(),
                    wayland_server::WEnum::Unknown(v) => v,
                };
                let grab_edges =
                    crate::core::input::interactive_grab::GrabEdges::from_xdg(edges_val);
                if state.start_interactive_grab(data.window_id, Some(grab_edges)) {
                    return;
                }
                state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowResizeRequested {
                        window_id: data.window_id,
                        seat_id: seat.id().protocol_id(),
                        serial,
                        edges: edges_val,
                    });
            }
            wl_shell_surface::Request::SetToplevel => {
                if let Ok(mut st) = data.state.lock() {
                    st.role = WlShellRole::Toplevel;
                }
                if let Some(surf) = state.get_surface(data.surface_id) {
                    if let Ok(mut s) = surf.write() {
                        let _ = s.set_role(SurfaceRole::Toplevel);
                    }
                }
            }
            wl_shell_surface::Request::SetTransient {
                parent,
                x,
                y,
                flags,
            } => {
                let parent_internal_id =
                    state.ensure_internal_surface_mapping(data.client_id.clone(), &parent);
                let (parent_x, parent_y) = state
                    .get_window_by_surface(parent_internal_id)
                    .and_then(|w| {
                        let win = w.read().ok()?;
                        Some((win.x, win.y))
                    })
                    .unwrap_or((0, 0));

                let inactive = match flags {
                    wayland_server::WEnum::Value(f) => {
                        f.contains(wl_shell_surface::Transient::Inactive)
                    }
                    wayland_server::WEnum::Unknown(v) => (v & 0x1) != 0,
                };

                if let Ok(mut st) = data.state.lock() {
                    st.role = WlShellRole::Transient {
                        parent_surface_id: parent_internal_id,
                        x,
                        y,
                        inactive,
                    };
                }

                if let Some(w) = state.get_window(data.window_id) {
                    if let Ok(mut win) = w.write() {
                        win.x = parent_x + x;
                        win.y = parent_y + y;
                    }
                }
            }
            wl_shell_surface::Request::SetFullscreen {
                method: _,
                framerate: _,
                output,
            } => {
                if let Ok(mut st) = data.state.lock() {
                    st.role = WlShellRole::Fullscreen;
                }
                let (ow, oh) = if let Some(out) = output {
                    state
                        .output_id_by_resource
                        .get(&out.id())
                        .and_then(|&oid| state.outputs.get(oid as usize))
                        .map(|o| (o.width as i32, o.height as i32))
                        .unwrap_or((1920, 1080))
                } else {
                    state
                        .outputs
                        .get(state.primary_output)
                        .map(|o| (o.width as i32, o.height as i32))
                        .unwrap_or((1920, 1080))
                };

                if let Some(w) = state.get_window(data.window_id) {
                    if let Ok(mut win) = w.write() {
                        win.fullscreen = true;
                    }
                }
                resource.configure(wl_shell_surface::Resize::None, ow, oh);
            }
            wl_shell_surface::Request::SetPopup {
                seat: _,
                serial: _,
                parent,
                x,
                y,
                flags: _,
            } => {
                let parent_internal_id =
                    state.ensure_internal_surface_mapping(data.client_id.clone(), &parent);
                let (parent_x, parent_y) = state
                    .get_window_by_surface(parent_internal_id)
                    .and_then(|w| {
                        let win = w.read().ok()?;
                        Some((win.x, win.y))
                    })
                    .unwrap_or((0, 0));

                if let Ok(mut st) = data.state.lock() {
                    st.role = WlShellRole::Popup {
                        parent_surface_id: parent_internal_id,
                        x,
                        y,
                    };
                }

                if let Some(surf) = state.get_surface(data.surface_id) {
                    if let Ok(mut s) = surf.write() {
                        let _ = s.set_role(SurfaceRole::Popup);
                    }
                }

                if let Some(w) = state.get_window(data.window_id) {
                    if let Ok(mut win) = w.write() {
                        win.x = parent_x + x;
                        win.y = parent_y + y;
                    }
                }
                state.set_keyboard_focus_surface(Some(data.surface_id));
            }
            wl_shell_surface::Request::SetMaximized { output } => {
                if let Ok(mut st) = data.state.lock() {
                    st.role = WlShellRole::Maximized;
                }
                let (ow, oh) = if let Some(out) = output {
                    state
                        .output_id_by_resource
                        .get(&out.id())
                        .and_then(|&oid| state.outputs.get(oid as usize))
                        .map(|o| (o.width as i32, o.height as i32))
                        .unwrap_or((1920, 1080))
                } else {
                    state
                        .outputs
                        .get(state.primary_output)
                        .map(|o| (o.width as i32, o.height as i32))
                        .unwrap_or((1920, 1080))
                };

                if let Some(w) = state.get_window(data.window_id) {
                    if let Ok(mut win) = w.write() {
                        win.maximized = true;
                    }
                }
                resource.configure(wl_shell_surface::Resize::None, ow, oh);
            }
            wl_shell_surface::Request::SetTitle { title } => {
                if let Ok(mut st) = data.state.lock() {
                    st.title = title.clone();
                }
                state.update_window(data.window_id, |w| {
                    w.title = title;
                });
            }
            wl_shell_surface::Request::SetClass { class_ } => {
                if let Ok(mut st) = data.state.lock() {
                    st.class = class_.clone();
                }
                state.update_window(data.window_id, |w| {
                    w.app_id = class_;
                });
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: ClientId,
        _resource: &WlShellSurface,
        data: &Arc<WlShellSurfaceUserData>,
    ) {
        state.surface_to_window.remove(&data.surface_id);
        state.destroy_window(data.window_id);
        if state.headless_host {
            state.repick_headless_global_pointer();
        }
    }
}
