//! XDG WM Base protocol implementation.
//!
//! This implements the xdg_wm_base global protocol from the xdg-shell extension.
//! It provides the entry point for clients to create xdg_surface objects.

use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_wm_base;

use crate::core::state::{CompositorState, XdgSurfaceData};

pub struct XdgShellGlobal;

impl GlobalDispatch<xdg_wm_base::XdgWmBase, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<xdg_wm_base::XdgWmBase>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let xdg_wm_base = data_init.init(resource, ());
        let client_id = _client.id();
        state.xdg.shell_resources.insert((client_id, xdg_wm_base.id().protocol_id()), xdg_wm_base.clone());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Bound xdg_wm_base version {}", xdg_wm_base.version());
        tracing::debug!("Bound xdg_wm_base");
    }
}

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &xdg_wm_base::XdgWmBase,
        request: xdg_wm_base::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            xdg_wm_base::Request::GetXdgSurface { id, surface } => {
                let client_id = _client.id();
                let surface_id = state.ensure_internal_surface_mapping(client_id.clone(), &surface);
                let mut xdg_surface_data = XdgSurfaceData::new(surface_id);
                // Store the surface ID (u32) as user data for the resource
                let xdg_surface: crate::core::wayland::protocol::server::xdg::shell::server::xdg_surface::XdgSurface = data_init.init(id, surface_id);
                xdg_surface_data.resource = Some(xdg_surface.clone());
                
                state.xdg.surfaces.insert((client_id, xdg_surface.id().protocol_id()), xdg_surface_data);
                
                crate::wlog!(crate::util::logging::COMPOSITOR, "Created xdg_surface version {} for wl_surface {}", xdg_surface.version(), surface_id);
            }
            xdg_wm_base::Request::CreatePositioner { id } => {
                data_init.init(id, ());
                tracing::trace!("Created xdg_positioner");
            }
            xdg_wm_base::Request::Pong { serial } => {
                crate::wlog!(crate::util::logging::COMPOSITOR, "Received xdg_wm_base.pong for serial {}", serial);
                // Clear the pending ping record — client is responsive
                if let Some((pending_client_id, shell_id, ts)) = state.xdg.pending_pings.remove(&serial) {
                    let latency_ms = ts.elapsed().as_millis();
                    tracing::trace!(
                        "xdg_wm_base pong: serial={}, client={:?}, shell={}, latency={}ms",
                        serial,
                        pending_client_id,
                        shell_id,
                        latency_ms
                    );
                } else {
                    tracing::warn!(
                        "Received xdg_wm_base.pong for unknown serial {} (client={:?}, shell={})",
                        serial,
                        _client.id(),
                        _resource.id().protocol_id()
                    );
                }
            }
            xdg_wm_base::Request::Destroy => {
                let client_id = _client.id();
                state.xdg.shell_resources.remove(&(client_id, _resource.id().protocol_id()));
                tracing::debug!("xdg_wm_base destroyed");
            }
            _ => {}
        }
    }
}
