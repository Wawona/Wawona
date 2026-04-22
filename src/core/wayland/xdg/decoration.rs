//! XDG Decoration protocol implementation.
//!
//! This protocol allows clients and compositors to negotiate whether
//! window decorations should be drawn client-side (CSD) or server-side (SSD).

use wayland_server::{
    Dispatch, Resource, DisplayHandle, GlobalDispatch,
};
use wayland_protocols::xdg::decoration::zv1::server::{
    zxdg_decoration_manager_v1::{self, ZxdgDecorationManagerV1},
    zxdg_toplevel_decoration_v1::{self, ZxdgToplevelDecorationV1, Mode},
};


use crate::core::state::{CompositorState, DecorationPolicy};
use crate::core::window::DecorationMode;
use std::collections::HashMap;

fn is_weston_family_app(state: &CompositorState, window_id: u32) -> bool {
    state
        .get_window(window_id)
        .and_then(|w| w.read().ok().map(|w| w.app_id.clone()))
        .map(|app_id| {
            app_id == "weston"
                || app_id.starts_with("weston-")
                || app_id.contains("weston")
        })
        .unwrap_or(false)
}

/// Data stored with each toplevel decoration
#[derive(Debug, Clone)]
pub struct ToplevelDecorationData {
    pub window_id: u32,
    pub mode: wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode,
    pub resource: Option<ZxdgToplevelDecorationV1>,
    pub kde_resource: Option<crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration::OrgKdeKwinServerDecoration>,
}

impl ToplevelDecorationData {
    pub fn new(window_id: u32, resource: Option<ZxdgToplevelDecorationV1>) -> Self {
        Self {
            window_id,
            mode: wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode::ClientSide,
            resource,
            kde_resource: None,
        }
    }

    pub fn new_kde(window_id: u32, resource: crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration::OrgKdeKwinServerDecoration) -> Self {
        Self {
            window_id,
            mode: wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode::ClientSide,
            resource: None,
            kde_resource: Some(resource),
        }
    }
}

unsafe impl Send for ToplevelDecorationData {}
unsafe impl Sync for ToplevelDecorationData {}

#[derive(Debug, Default)]
pub struct DecorationState {
    pub decorations: HashMap<(wayland_server::backend::ClientId, u32), ToplevelDecorationData>,
}


// ============================================================================
// zxdg_decoration_manager_v1
// ============================================================================

pub struct DecorationManagerGlobal;

impl GlobalDispatch<ZxdgDecorationManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<ZxdgDecorationManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zxdg_decoration_manager_v1");
    }
}

impl Dispatch<ZxdgDecorationManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &ZxdgDecorationManagerV1,
        request: zxdg_decoration_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zxdg_decoration_manager_v1::Request::GetToplevelDecoration { id, toplevel } => {
                // Get the toplevel data to find the window ID
                // FIXED: data should be &u32, not XdgToplevelData
                let window_id = match toplevel.data::<u32>() {
                    Some(id) => *id,
                    None => {
                        crate::wlog!(crate::util::logging::COMPOSITOR, "zxdg_decoration_manager: xdg_toplevel resource missing window_id data");
                        // We MUST initialize the resource anyway to avoid a panic in wayland-server
                        data_init.init(id, 0);
                        return;
                    }
                };
                
                // Initialize decoration resource first using the id from the request
                let decoration = data_init.init(id, window_id);
                
                // Create data with the cloned resource

                
                let decoration_data = ToplevelDecorationData::new(window_id, Some(decoration.clone()));
                let client_id = _client.id();
                
                state.xdg.decoration.decorations.insert((client_id, decoration.id().protocol_id()), decoration_data);

                
                // Send the preferred mode based on compositor policy
                let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
                    .then_some(false)
                    .unwrap_or_else(|| is_weston_family_app(state, window_id));
                let preferred_mode = if weston_family {
                    Mode::ClientSide
                } else {
                    match state.decoration_policy {
                    DecorationPolicy::PreferClient => Mode::ClientSide,
                    DecorationPolicy::PreferServer => Mode::ServerSide,
                    DecorationPolicy::ForceServer => Mode::ServerSide,
                    }
                };
                
                crate::wlog!(crate::util::logging::COMPOSITOR, "Sending zxdg_toplevel_decoration.configure for window {}: {:?}", window_id, preferred_mode);
                decoration.configure(preferred_mode);
                
                // Update window decoration mode
                if let Some(window) = state.get_window(window_id) {
                    let mut window = window.write().unwrap();
                    window.decoration_mode = match preferred_mode {
                        Mode::ClientSide => DecorationMode::ClientSide,
                        Mode::ServerSide => DecorationMode::ServerSide,
                        _ => DecorationMode::ClientSide,
                    };
                }
                
                // Trigger reconfiguration
                state.reconfigure_window_decorations(window_id);
                
                tracing::debug!(
                    "Created toplevel decoration for window {}: {:?}",
                    window_id, preferred_mode
                );
            }
            zxdg_decoration_manager_v1::Request::Destroy => {
                tracing::debug!("zxdg_decoration_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zxdg_toplevel_decoration_v1
// ============================================================================

impl Dispatch<ZxdgToplevelDecorationV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &ZxdgToplevelDecorationV1,
        request: zxdg_toplevel_decoration_v1::Request,
        _data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let window_id = *_data;
        
        match request {
            zxdg_toplevel_decoration_v1::Request::SetMode { mode } => {
                tracing::debug!("Client requests decoration mode: {:?}", mode);
                
                // Convert WEnum<Mode> to Mode
                let requested_mode = match mode {
                    wayland_server::WEnum::Value(m) => m,
                    wayland_server::WEnum::Unknown(_) => Mode::ClientSide,
                };
                
                // Determine the actual mode based on policy
                let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
                    .then_some(false)
                    .unwrap_or_else(|| is_weston_family_app(state, window_id));
                let actual_mode = if weston_family {
                    Mode::ClientSide
                } else {
                    match state.decoration_policy {
                        DecorationPolicy::ForceServer => Mode::ServerSide,
                        _ => requested_mode,
                    }
                };
                
                let new_mode = match actual_mode {
                    Mode::ClientSide => DecorationMode::ClientSide,
                    Mode::ServerSide => DecorationMode::ServerSide,
                    _ => DecorationMode::ClientSide,
                };
                if let Some(window) = state.get_window(window_id) {
                    let mut window = window.write().unwrap();
                    window.decoration_mode = new_mode;
                }

                crate::wlog!(crate::util::logging::COMPOSITOR,
                    "Set decoration mode for window {}: {:?} (requested {:?}, policy {:?})",
                    window_id, actual_mode, requested_mode, state.decoration_policy
                );

                state.pending_compositor_events.push(
                    crate::core::compositor::CompositorEvent::DecorationModeChanged {
                        window_id,
                        mode: new_mode,
                    },
                );

                // Send configure with actual mode - ALWAYS, even if it matches requested
                // This acknowledges the client's request and confirms the mode
                resource.configure(actual_mode);

                // IMPORTANT: The client needs to receive a full xdg_surface.configure sequence
                // to know about the new state. reconfigure_window_decorations handles this.
                state.reconfigure_window_decorations(window_id);
            }
            zxdg_toplevel_decoration_v1::Request::UnsetMode => {
                tracing::debug!("Client unsets decoration mode");
                
                // Revert to compositor preference
                let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
                    .then_some(false)
                    .unwrap_or_else(|| is_weston_family_app(state, window_id));
                let preferred_mode = if weston_family {
                    Mode::ClientSide
                } else {
                    match state.decoration_policy {
                        DecorationPolicy::PreferClient => Mode::ClientSide,
                        DecorationPolicy::PreferServer => Mode::ServerSide,
                        DecorationPolicy::ForceServer => Mode::ServerSide,
                    }
                };
                
                let new_mode = match preferred_mode {
                    Mode::ClientSide => DecorationMode::ClientSide,
                    Mode::ServerSide => DecorationMode::ServerSide,
                    _ => DecorationMode::ClientSide,
                };
                let client_id = _client.id();
                let dec_id = resource.id().protocol_id();
                if let Some(data) = state.xdg.decoration.decorations.get(&(client_id, dec_id)) {
                    if let Some(window_arc) = state.get_window(data.window_id) {
                        let mut window = window_arc.write().unwrap();
                        window.decoration_mode = new_mode;
                    }
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::DecorationModeChanged {
                            window_id: data.window_id,
                            mode: new_mode,
                        },
                    );
                }

                resource.configure(preferred_mode);
            }
            zxdg_toplevel_decoration_v1::Request::Destroy => {
                let client_id = _client.id();
                let dec_id = resource.id().protocol_id();
                state.xdg.decoration.decorations.remove(&(client_id, dec_id));
                tracing::debug!("zxdg_toplevel_decoration_v1 destroyed");
            }

            _ => {}
        }
    }
}
