//! Foreign Toplevel List protocol implementation.
//!
//! Provides a list of toplevels to privileged clients (task bars, dock, etc.).
//! On bind, enumerates all current toplevel windows. The handle resources
//! receive title, app_id, and done events, plus closed when a window is removed.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::wayland::protocol::server::ext::foreign_toplevel_list::v1::server::{
    ext_foreign_toplevel_list_v1::{self, ExtForeignToplevelListV1},
    ext_foreign_toplevel_handle_v1::{self, ExtForeignToplevelHandleV1},
};

use crate::core::state::CompositorState;

/// User data for a toplevel handle. Links to the compositor window
#[derive(Debug, Clone, Default)]
pub struct ForeignToplevelHandleData {
    pub window_id: u32,
}

impl GlobalDispatch<ExtForeignToplevelListV1, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        handle: &DisplayHandle,
        client: &Client,
        resource: New<ExtForeignToplevelListV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let list = data_init.init(resource, ());
        let version = list.version();

        // Enumerate all current toplevel windows
        let window_ids: Vec<u32> = state.windows.keys().copied().collect();
        for &window_id in &window_ids {
            if let Some(window) = state.get_window(window_id) {
                let window = window.read().unwrap();
                let data = ForeignToplevelHandleData { window_id };

                if let Ok(handle_res) = client.create_resource::<ExtForeignToplevelHandleV1, ForeignToplevelHandleData, CompositorState>(
                    handle,
                    version,
                    data,
                ) {
                    // Announce the toplevel
                    list.toplevel(&handle_res);

                    // Send metadata
                    handle_res.title(window.title.clone());
                    handle_res.app_id(window.app_id.clone());

                    // Identifier is the window id as string
                    handle_res.identifier(format!("wawona-window-{}", window_id));

                    handle_res.done();
                }
            }
        }

        tracing::debug!("Bound ext_foreign_toplevel_list_v1. Enumerated {} toplevels", window_ids.len());
    }
}

impl Dispatch<ExtForeignToplevelListV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtForeignToplevelListV1,
        request: ext_foreign_toplevel_list_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_foreign_toplevel_list_v1::Request::Stop => {
                tracing::debug!("Foreign toplevel list stopped by client");
            }
            ext_foreign_toplevel_list_v1::Request::Destroy => {
                tracing::debug!("Foreign toplevel list destroyed");
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtForeignToplevelHandleV1, ForeignToplevelHandleData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtForeignToplevelHandleV1,
        request: ext_foreign_toplevel_handle_v1::Request,
        _data: &ForeignToplevelHandleData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_foreign_toplevel_handle_v1::Request::Destroy => {
                tracing::debug!("Foreign toplevel handle destroyed");
            }
            _ => {}
        }
    }
}

pub fn register_foreign_toplevel_list(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtForeignToplevelListV1, ()>(1, ())
}
