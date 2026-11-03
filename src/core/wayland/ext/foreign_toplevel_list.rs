//! Foreign Toplevel List protocol implementation.
//!
//! Provides a list of toplevels to privileged clients (task bars, dock, etc.).
//! On bind, enumerates all current toplevel windows. Later create/destroy
//! notifies keep bound lists in sync.

use crate::core::wayland::protocol::server::ext::foreign_toplevel_list::v1::server::{
    ext_foreign_toplevel_handle_v1::{self, ExtForeignToplevelHandleV1},
    ext_foreign_toplevel_list_v1::{self, ExtForeignToplevelListV1},
};
use std::collections::HashMap;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// User data for a toplevel handle. Links to the compositor window.
#[derive(Debug, Clone, Default)]
pub struct ForeignToplevelHandleData {
    pub window_id: u32,
}

/// Bound lists and live handles for create/destroy notify.
#[derive(Debug, Default)]
pub struct ForeignToplevelListState {
    pub lists: Vec<ExtForeignToplevelListV1>,
    pub handles: HashMap<u32, Vec<ExtForeignToplevelHandleV1>>,
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

        let window_ids: Vec<u32> = state.windows.keys().copied().collect();
        for &window_id in &window_ids {
            if let Some(window) = state.get_window(window_id) {
                let window = window.read().unwrap();
                let data = ForeignToplevelHandleData { window_id };

                if let Ok(handle_res) = client.create_resource::<
                    ExtForeignToplevelHandleV1,
                    ForeignToplevelHandleData,
                    CompositorState,
                >(handle, version, data)
                {
                    list.toplevel(&handle_res);
                    handle_res.title(window.title.clone());
                    handle_res.app_id(window.app_id.clone());
                    handle_res.identifier(format!("wawona-window-{window_id}"));
                    handle_res.done();
                    state
                        .ext
                        .foreign_toplevel_list
                        .handles
                        .entry(window_id)
                        .or_default()
                        .push(handle_res);
                }
            }
        }

        state.ext.foreign_toplevel_list.lists.push(list);
        tracing::debug!(
            "Bound ext_foreign_toplevel_list_v1. Enumerated {} toplevels",
            window_ids.len()
        );
    }
}

impl Dispatch<ExtForeignToplevelListV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtForeignToplevelListV1,
        request: ext_foreign_toplevel_list_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_foreign_toplevel_list_v1::Request::Stop => {
                let id = resource.id();
                state
                    .ext
                    .foreign_toplevel_list
                    .lists
                    .retain(|l| l.id() != id);
                tracing::debug!("Foreign toplevel list stopped by client");
            }
            ext_foreign_toplevel_list_v1::Request::Destroy => {
                let id = resource.id();
                state
                    .ext
                    .foreign_toplevel_list
                    .lists
                    .retain(|l| l.id() != id);
                tracing::debug!("Foreign toplevel list destroyed");
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtForeignToplevelHandleV1, ForeignToplevelHandleData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtForeignToplevelHandleV1,
        request: ext_foreign_toplevel_handle_v1::Request,
        data: &ForeignToplevelHandleData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_foreign_toplevel_handle_v1::Request::Destroy => {
                if let Some(handles) = state
                    .ext
                    .foreign_toplevel_list
                    .handles
                    .get_mut(&data.window_id)
                {
                    handles.retain(|h| h.id() != resource.id());
                }
                tracing::debug!("Foreign toplevel handle destroyed");
            }
            _ => {}
        }
    }
}

/// Advertise a newly mapped toplevel to every bound ext foreign-toplevel list.
pub fn notify_toplevel_created(state: &mut CompositorState, window_id: u32) {
    let Some(dhandle) = state.smithay_runtime.display_handle.clone() else {
        return;
    };
    let Some(window) = state.get_window(window_id) else {
        return;
    };
    let Ok(window) = window.read() else {
        return;
    };
    let title = window.title.clone();
    let app_id = window.app_id.clone();
    drop(window);

    let lists: Vec<_> = state.ext.foreign_toplevel_list.lists.clone();
    for list in lists {
        let Some(client) = list.client() else {
            continue;
        };
        let data = ForeignToplevelHandleData { window_id };
        let Ok(handle_res) = client.create_resource::<
            ExtForeignToplevelHandleV1,
            ForeignToplevelHandleData,
            CompositorState,
        >(&dhandle, list.version(), data) else {
            continue;
        };
        list.toplevel(&handle_res);
        handle_res.title(title.clone());
        handle_res.app_id(app_id.clone());
        handle_res.identifier(format!("wawona-window-{window_id}"));
        handle_res.done();
        state
            .ext
            .foreign_toplevel_list
            .handles
            .entry(window_id)
            .or_default()
            .push(handle_res);
    }
}

/// Notify lists that a toplevel was destroyed.
pub fn notify_toplevel_destroyed(state: &mut CompositorState, window_id: u32) {
    if let Some(handles) = state.ext.foreign_toplevel_list.handles.remove(&window_id) {
        for handle in handles {
            if handle.is_alive() {
                handle.closed();
            }
        }
    }
}

pub fn register_foreign_toplevel_list(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtForeignToplevelListV1, ()>(1, ())
}
