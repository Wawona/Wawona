//! KDE Server Decoration protocol implementation.
//!
//! This implements the org_kde_kwin_server_decoration protocol.
//! It allows clients to negotiate decoration mode (CSD vs SSD).

use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};
use crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::{
    org_kde_kwin_server_decoration_manager::{self, OrgKdeKwinServerDecorationManager},
    org_kde_kwin_server_decoration::{self, OrgKdeKwinServerDecoration, Mode},
};

use crate::core::state::{CompositorState, DecorationPolicy};
use crate::core::wayland::xdg::decoration::ToplevelDecorationData;
use crate::core::window::DecorationMode;

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

// ============================================================================
// org_kde_kwin_server_decoration_manager
// ============================================================================

pub struct KdeDecorationManagerGlobal;

impl GlobalDispatch<OrgKdeKwinServerDecorationManager, KdeDecorationManagerGlobal> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinServerDecorationManager>,
        _global_data: &KdeDecorationManagerGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound org_kde_kwin_server_decoration_manager");
    }
}

impl Dispatch<OrgKdeKwinServerDecorationManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinServerDecorationManager,
        request: org_kde_kwin_server_decoration_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_server_decoration_manager::Request::Create { id, surface } => {
                let surface_id = surface.id().protocol_id();
                
                // Initialize the decoration resource
                let decoration = data_init.init(id, surface_id);
                
                // Determine the default mode based on policy
                let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
                    .then_some(false)
                    .unwrap_or_else(|| state.surface_to_window.get(&surface_id).copied().map(|wid| is_weston_family_app(state, wid)).unwrap_or(false));
                let default_mode = if weston_family {
                    Mode::Client
                } else {
                    match state.decoration_policy {
                        DecorationPolicy::PreferClient => Mode::Client,
                        DecorationPolicy::PreferServer => Mode::Server,
                        DecorationPolicy::ForceServer => Mode::Server,
                    }
                };
                
                // Track the decoration in state
                // We need to find the window ID first. Since this protocol uses surface, we look it up.
                let client_id = _client.id();
                if let Some(window_id) = state.surface_to_window.get(&surface_id).copied() {
                    let decoration_data = ToplevelDecorationData::new_kde(window_id, decoration.clone());
                    state.xdg.decoration.decorations.insert((client_id, decoration.id().protocol_id()), decoration_data);
                    tracing::debug!("Registered KDE decoration for window {}", window_id);
                } else {
                    tracing::warn!("Created KDE decoration for surface {} with no window", surface_id);
                }

                crate::wlog!(crate::util::logging::COMPOSITOR, "Created KDE decoration for surface {}: default_mode={:?}", surface_id, default_mode);
                
                // Notify the client of the initial mode
                decoration.mode(default_mode);
            }
            _ => {}
        }
    }
}

// ============================================================================
// org_kde_kwin_server_decoration
// ============================================================================

impl Dispatch<OrgKdeKwinServerDecoration, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &OrgKdeKwinServerDecoration,
        request: org_kde_kwin_server_decoration::Request,
        _data: &u32, // surface_id
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let surface_id = *_data;
        
        match request {
            org_kde_kwin_server_decoration::Request::RequestMode { mode } => {
                let requested_mode = match mode {
                    wayland_server::WEnum::Value(m) => m,
                    wayland_server::WEnum::Unknown(_) => Mode::Client,
                };
                
                tracing::debug!("Client requests KDE decoration mode: {:?}", requested_mode);
                
                // Apply policy
                let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
                    .then_some(false)
                    .unwrap_or_else(|| state.surface_to_window.get(&surface_id).copied().map(|wid| is_weston_family_app(state, wid)).unwrap_or(false));
                let actual_mode = if weston_family {
                    Mode::Client
                } else {
                    match state.decoration_policy {
                        DecorationPolicy::ForceServer => Mode::Server,
                        _ => requested_mode,
                    }
                };
                
                // Update window state if we can find the window for this surface
                let mut window_id_to_configure = None;
                let mut new_decoration_mode = None;
                let client_id = _client.id();
                if let Some(surface_data) = state.xdg.surfaces.get(&(client_id.clone(), surface_id)) {
                    if let Some(window_id) = surface_data.window_id {
                        window_id_to_configure = Some(window_id);
                        let new_mode = if actual_mode == Mode::Server {
                            DecorationMode::ServerSide
                        } else {
                            DecorationMode::ClientSide
                        };
                        new_decoration_mode = Some((window_id, new_mode));
                        if let Some(window) = state.get_window(window_id) {
                            let mut window = window.write().unwrap();
                            window.decoration_mode = new_mode;
                        }
                    }
                }

                if let Some((window_id, mode)) = new_decoration_mode {
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::DecorationModeChanged {
                            window_id,
                            mode,
                        },
                    );
                }

                crate::wlog!(crate::util::logging::COMPOSITOR,
                    "KDE decoration mode for surface {}: {:?} (requested {:?}, policy {:?})",
                    surface_id, actual_mode, requested_mode, state.decoration_policy
                );

                // Confirm the mode to the client
                resource.mode(actual_mode);

                // Trigger a re-configure if we have a window to ensure the client reacts
                if let Some(window_id) = window_id_to_configure {
                    // IMPORTANT: The client needs to receive a full xdg_surface.configure sequence
                    // to know about the new state. reconfigure_window_decorations handles this.
                    state.reconfigure_window_decorations(window_id);
                }
            }
            org_kde_kwin_server_decoration::Request::Release => {
                let dec_id = resource.id().protocol_id();
                let client_id = _client.id();
                let dec_id = resource.id().protocol_id();
                state.xdg.decoration.decorations.remove(&(client_id, dec_id));
                tracing::debug!("KDE decoration released for surface {}", surface_id);
            }
            _ => {}
        }
    }
}
