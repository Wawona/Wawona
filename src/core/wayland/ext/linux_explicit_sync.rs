//! WP Linux Explicit Synchronization protocol implementation.
//!
//! This protocol provides explicit synchronization for buffer operations,
//! allowing better GPU scheduling and reduced latency.

use crate::core::wayland::protocol::server::wp::linux_explicit_synchronization::zv1::server::{
    zwp_linux_buffer_release_v1::{self, ZwpLinuxBufferReleaseV1},
    zwp_linux_explicit_synchronization_v1::{self, ZwpLinuxExplicitSynchronizationV1},
    zwp_linux_surface_synchronization_v1::{self, ZwpLinuxSurfaceSynchronizationV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with surface synchronization
#[derive(Debug, Clone)]
pub struct SurfaceSynchronizationData {
    pub surface_id: u32,
}

// ============================================================================
// zwp_linux_explicit_synchronization_v1
// ============================================================================

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
        #[cfg_attr(not(feature = "desktop-protocols"), allow(unused_variables))] state: &mut Self,
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
                // let data = SurfaceSynchronizationData { surface_id };
                let sync = data_init.init(id, ());
                let sync_id = sync.id().protocol_id();
                #[cfg(feature = "desktop-protocols")]
                {
                    state
                        .ext
                        .linux_drm_syncobj
                        .surface_sync_states
                        .insert(sync_id, surface_id);
                }
                let _ = (sync_id, surface_id);

                tracing::debug!("Created surface synchronization for surface {}", surface_id);
            }
            zwp_linux_explicit_synchronization_v1::Request::Destroy => {
                tracing::debug!("zwp_linux_explicit_synchronization_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_linux_surface_synchronization_v1
// ============================================================================

impl Dispatch<ZwpLinuxSurfaceSynchronizationV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &ZwpLinuxSurfaceSynchronizationV1,
        request: zwp_linux_surface_synchronization_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_linux_surface_synchronization_v1::Request::SetAcquireFence { fd } => {
                use std::os::unix::io::AsRawFd;
                tracing::debug!(
                    "Set acquire fence (fd={}) for sync object {}",
                    fd.as_raw_fd(),
                    resource.id().protocol_id()
                );
                // In a real implementation, store the fence fd for synchronization using state.ext.surface_sync_states to find the surface
                drop(fd);
            }
            zwp_linux_surface_synchronization_v1::Request::GetRelease { release } => {
                tracing::debug!("Get release fence requested");
                // In a real implementation, create a release fence
                let _release_obj: zwp_linux_buffer_release_v1::ZwpLinuxBufferReleaseV1 =
                    _data_init.init(release, ());
            }
            zwp_linux_surface_synchronization_v1::Request::Destroy => {
                // state.ext.surface_sync_states.remove(&resource.id().protocol_id()); // We would need mut state here to cleanup
                tracing::debug!("Surface synchronization destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_linux_buffer_release_v1
// ============================================================================

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
        // ZwpLinuxBufferReleaseV1 has no requests, only events
        let _ = (request, _data_init);
    }
}

/// Register zwp_linux_explicit_synchronization_v1 global
pub fn register_linux_explicit_sync(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpLinuxExplicitSynchronizationV1, ()>(1, ())
}
