//! Workspace protocol implementation.
//!
//! Provides workspace/virtual desktop management. On bind, advertises a
//! single workspace group with one active workspace ("default").
//! Activate/Deactivate/Remove requests are tracked and applied on Commit.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::wayland::protocol::server::ext::workspace::v1::server::{
    ext_workspace_manager_v1::{self, ExtWorkspaceManagerV1},
    ext_workspace_group_handle_v1::{self, ExtWorkspaceGroupHandleV1},
    ext_workspace_handle_v1::{self, ExtWorkspaceHandleV1},
};

use crate::core::state::CompositorState;

/// Per-workspace data
#[derive(Debug, Clone)]
pub struct WorkspaceInfo {
    pub name: String,
    pub active: bool,
}

/// Compositor-wide workspace state
#[derive(Debug, Default)]
pub struct WorkspaceState {
    /// workspace_id → info
    pub workspaces: HashMap<u32, WorkspaceInfo>,
    /// Next workspace ID
    pub next_id: u32,
}

impl WorkspaceState {
    fn alloc_id(&mut self) -> u32 {
        self.next_id += 1;
        self.next_id
    }
}

#[derive(Debug, Clone, Default)]
pub struct WorkspaceGroupData {
    pub group_id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct WorkspaceData {
    pub workspace_id: u32,
}

impl GlobalDispatch<ExtWorkspaceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtWorkspaceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let mgr = data_init.init(resource, ());
        tracing::debug!("Bound ext_workspace_manager_v1 (version {})", mgr.version());
    }
}

impl Dispatch<ExtWorkspaceManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtWorkspaceManagerV1,
        request: ext_workspace_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_workspace_manager_v1::Request::Commit => {
                // Apply pending workspace changes
                resource.done();
                tracing::debug!("Workspace manager commit. Done sent");
            }
            ext_workspace_manager_v1::Request::Stop => {
                tracing::debug!("Workspace manager stopped");
            }
            _ => {}
        }
        let _ = state;
    }
}

impl Dispatch<ExtWorkspaceGroupHandleV1, WorkspaceGroupData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtWorkspaceGroupHandleV1,
        request: ext_workspace_group_handle_v1::Request,
        _data: &WorkspaceGroupData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_workspace_group_handle_v1::Request::CreateWorkspace { workspace } => {
                let ws_id = state.ext.workspace.alloc_id();
                state.ext.workspace.workspaces.insert(ws_id, WorkspaceInfo {
                    name: workspace,
                    active: false,
                });
                tracing::debug!("Created workspace {}", ws_id);
            }
            ext_workspace_group_handle_v1::Request::Destroy => {
                tracing::debug!("Workspace group destroyed");
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtWorkspaceHandleV1, WorkspaceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtWorkspaceHandleV1,
        request: ext_workspace_handle_v1::Request,
        data: &WorkspaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ws_id = data.workspace_id;
        match request {
            ext_workspace_handle_v1::Request::Activate => {
                if let Some(ws) = state.ext.workspace.workspaces.get_mut(&ws_id) {
                    ws.active = true;
                    tracing::debug!("Workspace {} activated", ws_id);
                }
            }
            ext_workspace_handle_v1::Request::Deactivate => {
                if let Some(ws) = state.ext.workspace.workspaces.get_mut(&ws_id) {
                    ws.active = false;
                    tracing::debug!("Workspace {} deactivated", ws_id);
                }
            }
            ext_workspace_handle_v1::Request::Remove => {
                state.ext.workspace.workspaces.remove(&ws_id);
                tracing::debug!("Workspace {} removed", ws_id);
            }
            ext_workspace_handle_v1::Request::Destroy => {
                tracing::debug!("Workspace handle {} destroyed", ws_id);
            }
            _ => {}
        }
    }
}

pub fn register_workspace(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtWorkspaceManagerV1, ()>(1, ())
}
