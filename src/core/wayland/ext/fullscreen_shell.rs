//! Fullscreen Shell protocol implementation.
//!
//! A simple shell for fullscreen kiosk-mode applications.  `PresentSurface`
//! maps a surface directly to an output at full coverage.
//!
//! On iOS there is no window-management chrome. The compositor view is a
//! single full-screen surface, so **all** Wayland clients are expected to
//! use this protocol instead of xdg_shell.
//!
//! When a surface is presented we create a synthetic Window (the same struct
//! used by xdg_toplevel) and wire it into the normal `surface_to_window`
//! mapping so the existing buffer-processing and scene-graph pipelines work
//! without any special cases.

use std::sync::{Arc, RwLock};

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::fullscreen_shell::zv1::server::{
    zwp_fullscreen_shell_v1::{self, ZwpFullscreenShellV1},
    zwp_fullscreen_shell_mode_feedback_v1::{self, ZwpFullscreenShellModeFeedbackV1},
};

use crate::core::state::CompositorState;
use crate::core::window::window::Window;
use crate::core::window::DecorationMode;

/// Compositor-wide fullscreen shell state
#[derive(Debug, Default)]
pub struct FullscreenShellState {
    /// Currently presented surface (only one at a time in this simple shell)
    pub presented_surface: Option<u32>,
    /// Synthetic window ID created for the presented surface
    pub presented_window_id: Option<u32>,
    /// Pending mode feedback objects waiting for safe destructor dispatch
    pub pending_mode_feedbacks: Vec<ZwpFullscreenShellModeFeedbackV1>,
    /// Clients that have bound zwp_fullscreen_shell_v1.  Used to identify
    /// nested compositors: if a client owns both an xdg_toplevel AND a
    /// fullscreen-shell binding, its toplevel resize must propagate as a
    /// wl_output mode change.
    pub bound_clients: std::collections::HashSet<wayland_server::backend::ClientId>,
}

impl FullscreenShellState {
    pub fn flush_pending_mode_feedbacks(&mut self) {
        for fb in self.pending_mode_feedbacks.drain(..) {
            fb.mode_successful();
        }
    }
}

impl GlobalDispatch<ZwpFullscreenShellV1, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpFullscreenShellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let shell = data_init.init(resource, ());
        shell.capability(zwp_fullscreen_shell_v1::Capability::ArbitraryModes);
        state.ext.fullscreen_shell.bound_clients.insert(_client.id());
        tracing::debug!("Bound zwp_fullscreen_shell_v1 for client {:?}", _client.id());
    }
}

impl Dispatch<ZwpFullscreenShellV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpFullscreenShellV1,
        request: zwp_fullscreen_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_fullscreen_shell_v1::Request::PresentSurface { surface, method: _, output: _ } => {
                let new_surface_id = surface.as_ref().map(|s| s.id().protocol_id());

                // Tear down the old presented window (if any)
                if let Some(old_wid) = state.ext.fullscreen_shell.presented_window_id.take() {
                    if let Some(old_sid) = state.ext.fullscreen_shell.presented_surface.take() {
                        state.surface_to_window.remove(&old_sid);
                    }
                    state.windows.remove(&old_wid);
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowDestroyed { window_id: old_wid }
                    );
                    tracing::debug!("Fullscreen shell: destroyed old window {}", old_wid);
                }

                state.ext.fullscreen_shell.presented_surface = new_surface_id;

                // Create a synthetic window for the new surface
                if let Some(sid) = new_surface_id {
                    // Tear down any existing window (e.g. xdg_toplevel fallback) mapped to this surface
                    if let Some(existing_wid) = state.surface_to_window.remove(&sid) {
                        state.windows.remove(&existing_wid);
                        state.pending_compositor_events.push(
                            crate::core::compositor::CompositorEvent::WindowDestroyed { window_id: existing_wid }
                        );
                        tracing::debug!("Fullscreen shell: destroyed pre-existing window {} for surface {}", existing_wid, sid);
                    }

                    let (width, height) = if let Some(output) = state.outputs.get(state.primary_output) {
                        (output.width, output.height)
                    } else {
                        (800, 600)
                    };

                    let window_id = state.next_window_id();
                    let mut window = Window::new(window_id, sid);
                    window.width = width as i32;
                    window.height = height as i32;
                    window.fullscreen = true;
                    window.activated = true;
                    window.host_locked = true;
                    window.title = "Fullscreen Shell".to_string();
                    window.decoration_mode = DecorationMode::ServerSide;

                    state.windows.insert(window_id, Arc::new(RwLock::new(window)));
                    state.surface_to_window.insert(sid, window_id);
                    state.ext.fullscreen_shell.presented_window_id = Some(window_id);

                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowCreated {
                            client_id: _client.id(),
                            window_id,
                            surface_id: sid,
                            title: "Fullscreen Shell".to_string(),
                            width,
                            height,
                            decoration_mode: DecorationMode::ServerSide,
                            fullscreen_shell: true,
                            host_locked: true,
                            fills_host: false,
                        }
                    );

                    tracing::info!(
                        "Fullscreen shell: presented surface {} as window {} ({}x{})",
                        sid, window_id, width, height
                    );
                }
            }
            zwp_fullscreen_shell_v1::Request::PresentSurfaceForMode { surface, output: _, framerate: _, feedback } => {
                let fb = data_init.init(feedback, ());
                
                // DEFER DESTRUCTOR: Do NOT call fb.mode_successful() here synchronously.
                // Doing so will provoke a wayland-backend panic because the resource
                // maps are not yet fully initialized for this object during dispatch.
                state.ext.fullscreen_shell.pending_mode_feedbacks.push(fb);

                // Also create a window for the surface (same as PresentSurface)
                let new_surface_id = Some(surface.id().protocol_id());

                if let Some(old_wid) = state.ext.fullscreen_shell.presented_window_id.take() {
                    if let Some(old_sid) = state.ext.fullscreen_shell.presented_surface.take() {
                        state.surface_to_window.remove(&old_sid);
                    }
                    state.windows.remove(&old_wid);
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowDestroyed { window_id: old_wid }
                    );
                }

                state.ext.fullscreen_shell.presented_surface = new_surface_id;

                if let Some(sid) = new_surface_id {
                    // Tear down any existing window (e.g. xdg_toplevel fallback) mapped to this surface
                    if let Some(existing_wid) = state.surface_to_window.remove(&sid) {
                        state.windows.remove(&existing_wid);
                        state.pending_compositor_events.push(
                            crate::core::compositor::CompositorEvent::WindowDestroyed { window_id: existing_wid }
                        );
                        tracing::debug!("Fullscreen shell: destroyed pre-existing window {} for surface {}", existing_wid, sid);
                    }

                    let (width, height) = if let Some(output) = state.outputs.get(state.primary_output) {
                        (output.width, output.height)
                    } else {
                        (800, 600)
                    };

                    let window_id = state.next_window_id();
                    let mut window = Window::new(window_id, sid);
                    window.width = width as i32;
                    window.height = height as i32;
                    window.fullscreen = true;
                    window.activated = true;
                    window.decoration_mode = DecorationMode::ServerSide;

                    state.windows.insert(window_id, Arc::new(RwLock::new(window)));
                    state.surface_to_window.insert(sid, window_id);
                    state.ext.fullscreen_shell.presented_window_id = Some(window_id);

                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowCreated {
                            client_id: _client.id(),
                            window_id,
                            surface_id: sid,
                            title: String::new(),
                            width,
                            height,
                            decoration_mode: DecorationMode::ServerSide,
                            fullscreen_shell: true,
                            host_locked: true,
                            fills_host: false,
                        }
                    );
                }

                tracing::debug!("Fullscreen shell mode feedback: successful");
            }
            zwp_fullscreen_shell_v1::Request::Release => {
                // Tear down the presented window
                if let Some(old_wid) = state.ext.fullscreen_shell.presented_window_id.take() {
                    if let Some(old_sid) = state.ext.fullscreen_shell.presented_surface.take() {
                        state.surface_to_window.remove(&old_sid);
                    }
                    state.windows.remove(&old_wid);
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowDestroyed { window_id: old_wid }
                    );
                }
                state.ext.fullscreen_shell.presented_surface = None;
                tracing::debug!("Fullscreen shell released");
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpFullscreenShellModeFeedbackV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpFullscreenShellModeFeedbackV1,
        _request: zwp_fullscreen_shell_mode_feedback_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        // No client requests defined for mode feedback. All events are compositor→client
    }
}

pub fn register_fullscreen_shell(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpFullscreenShellV1, ()>(1, ())
}
