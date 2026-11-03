//! WP Linux Explicit Synchronization (legacy; prefer wp_linux_drm_syncobj).
//!
//! Stores acquire fence fds per surface sync object. Hosts with an explicit
//! sync capability consume them; Apple hosts may no-op while still accepting
//! the protocol so clients do not error.

use std::collections::HashMap;
use std::os::unix::io::{AsRawFd, OwnedFd};

use crate::core::wayland::protocol::server::wp::linux_explicit_synchronization::zv1::server::{
    zwp_linux_buffer_release_v1::{self, ZwpLinuxBufferReleaseV1},
    zwp_linux_explicit_synchronization_v1::{self, ZwpLinuxExplicitSynchronizationV1},
    zwp_linux_surface_synchronization_v1::{self, ZwpLinuxSurfaceSynchronizationV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug)]
pub struct SurfaceSyncEntry {
    pub surface_id: u32,
    pub acquire_fd: Option<OwnedFd>,
}

#[derive(Debug, Default)]
pub struct LinuxExplicitSyncState {
    /// sync resource protocol id → entry
    pub surface_sync: HashMap<u32, SurfaceSyncEntry>,
}

#[derive(Debug, Clone)]
pub struct SurfaceSynchronizationData {
    pub surface_id: u32,
}

impl GlobalDispatch<ZwpLinuxExplicitSynchronizationV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpLinuxExplicitSynchronizationV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_linux_explicit_synchronization_v1");
    }
}

impl Dispatch<ZwpLinuxExplicitSynchronizationV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpLinuxExplicitSynchronizationV1,
        request: zwp_linux_explicit_synchronization_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_linux_explicit_synchronization_v1::Request::GetSynchronization { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let sync = data_init.init(id, SurfaceSynchronizationData { surface_id });
                let sync_id = sync.id().protocol_id();
                state.ext.linux_explicit_sync.surface_sync.insert(
                    sync_id,
                    SurfaceSyncEntry {
                        surface_id,
                        acquire_fd: None,
                    },
                );
                tracing::debug!("Created surface synchronization for surface {}", surface_id);
            }
            zwp_linux_explicit_synchronization_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZwpLinuxSurfaceSynchronizationV1, SurfaceSynchronizationData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpLinuxSurfaceSynchronizationV1,
        request: zwp_linux_surface_synchronization_v1::Request,
        _data: &SurfaceSynchronizationData,
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let sync_id = resource.id().protocol_id();
        match request {
            zwp_linux_surface_synchronization_v1::Request::SetAcquireFence { fd } => {
                tracing::debug!(
                    "Set acquire fence (fd={}) for sync object {}",
                    fd.as_raw_fd(),
                    sync_id
                );
                if let Some(entry) = state.ext.linux_explicit_sync.surface_sync.get_mut(&sync_id) {
                    entry.acquire_fd = Some(fd);
                } else {
                    drop(fd);
                }
            }
            zwp_linux_surface_synchronization_v1::Request::GetRelease { release } => {
                let _release_obj: ZwpLinuxBufferReleaseV1 = data_init.init(release, ());
            }
            zwp_linux_surface_synchronization_v1::Request::Destroy => {
                state.ext.linux_explicit_sync.surface_sync.remove(&sync_id);
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpLinuxBufferReleaseV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpLinuxBufferReleaseV1,
        request: zwp_linux_buffer_release_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = request;
    }
}

pub fn register_linux_explicit_sync(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpLinuxExplicitSynchronizationV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_state_defaults_empty() {
        let s = LinuxExplicitSyncState::default();
        assert!(s.surface_sync.is_empty());
    }
}
