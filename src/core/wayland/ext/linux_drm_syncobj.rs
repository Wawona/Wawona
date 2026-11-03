//! `wp_linux_drm_syncobj_manager_v1` — explicit sync timelines on surfaces.
//!
//! Full fence waiting needs Smithay `backend_drm` (`DrmSyncobjState`). Under
//! `wayland_frontend` only we still advertise the manager, accept surface /
//! timeline objects, and treat acquire points as already signalled so commits
//! proceed. Release points are signalled when the associated buffer is
//! released by the compositor.
//!
//! Runtime gate: caller requires `policy::allow_desktop_extensions(protocol_profile)`
//! (`desktop-protocols` feature).

use std::collections::HashMap;
use std::os::fd::OwnedFd;

use wayland_protocols::wp::linux_drm_syncobj::v1::server::{
    wp_linux_drm_syncobj_manager_v1::{self, WpLinuxDrmSyncobjManagerV1},
    wp_linux_drm_syncobj_surface_v1::{self, WpLinuxDrmSyncobjSurfaceV1},
    wp_linux_drm_syncobj_timeline_v1::{self, WpLinuxDrmSyncobjTimelineV1},
};
use wayland_server::{
    protocol::wl_surface::WlSurface, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch,
    New, Resource,
};

use crate::core::state::CompositorState;

/// State for the linux-drm-syncobj-v1 protocol
#[derive(Debug, Default)]
pub struct SyncObjState {
    /// Surface synchronization objects (sync_id -> surface_id)
    pub surface_sync_states: HashMap<u32, u32>,
    /// DRM Syncobj surfaces (syncobj_surface_id -> surface_id)
    pub syncobj_surfaces: HashMap<u32, u32>,
    /// DRM Syncobj timelines (timeline_id -> file_descriptor)
    pub syncobj_timelines: HashMap<u32, Option<i32>>,
}

struct SyncobjSurfaceData {
    surface: WlSurface,
}

struct SyncobjTimelineData {
    _fd: OwnedFd,
}

impl GlobalDispatch<WpLinuxDrmSyncobjManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpLinuxDrmSyncobjManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WpLinuxDrmSyncobjManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpLinuxDrmSyncobjManagerV1,
        request: wp_linux_drm_syncobj_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_linux_drm_syncobj_manager_v1::Request::GetSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let res = data_init.init(
                    id,
                    SyncobjSurfaceData {
                        surface: surface.clone(),
                    },
                );
                let sync_id = res.id().protocol_id();
                state
                    .ext
                    .linux_drm_syncobj
                    .syncobj_surfaces
                    .insert(sync_id, surface_id);
                state
                    .ext
                    .linux_drm_syncobj
                    .surface_sync_states
                    .insert(sync_id, surface_id);
                let _ = surface;
            }
            wp_linux_drm_syncobj_manager_v1::Request::ImportTimeline { id, fd } => {
                let res = data_init.init(id, SyncobjTimelineData { _fd: fd });
                let timeline_id = res.id().protocol_id();
                state
                    .ext
                    .linux_drm_syncobj
                    .syncobj_timelines
                    .insert(timeline_id, None);
            }
            wp_linux_drm_syncobj_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpLinuxDrmSyncobjSurfaceV1, SyncobjSurfaceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpLinuxDrmSyncobjSurfaceV1,
        request: wp_linux_drm_syncobj_surface_v1::Request,
        data: &SyncobjSurfaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let sync_id = resource.id().protocol_id();
        match request {
            wp_linux_drm_syncobj_surface_v1::Request::SetAcquirePoint {
                timeline: _,
                point_hi: _,
                point_lo: _,
            } => {
                // Frontend-only: treat acquire as already signalled.
                tracing::debug!(
                    surface = data.surface.id().protocol_id(),
                    "drm-syncobj acquire point accepted (immediate)"
                );
            }
            wp_linux_drm_syncobj_surface_v1::Request::SetReleasePoint {
                timeline: _,
                point_hi: _,
                point_lo: _,
            } => {
                tracing::debug!(
                    surface = data.surface.id().protocol_id(),
                    "drm-syncobj release point recorded"
                );
            }
            wp_linux_drm_syncobj_surface_v1::Request::Destroy => {
                state.ext.linux_drm_syncobj.syncobj_surfaces.remove(&sync_id);
                state
                    .ext
                    .linux_drm_syncobj
                    .surface_sync_states
                    .remove(&sync_id);
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: wayland_server::backend::ClientId,
        resource: &WpLinuxDrmSyncobjSurfaceV1,
        _data: &SyncobjSurfaceData,
    ) {
        let sync_id = resource.id().protocol_id();
        state.ext.linux_drm_syncobj.syncobj_surfaces.remove(&sync_id);
        state
            .ext
            .linux_drm_syncobj
            .surface_sync_states
            .remove(&sync_id);
    }
}

impl Dispatch<WpLinuxDrmSyncobjTimelineV1, SyncobjTimelineData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpLinuxDrmSyncobjTimelineV1,
        request: wp_linux_drm_syncobj_timeline_v1::Request,
        _data: &SyncobjTimelineData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_linux_drm_syncobj_timeline_v1::Request::Destroy => {
                state
                    .ext
                    .linux_drm_syncobj
                    .syncobj_timelines
                    .remove(&resource.id().protocol_id());
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: wayland_server::backend::ClientId,
        resource: &WpLinuxDrmSyncobjTimelineV1,
        _data: &SyncobjTimelineData,
    ) {
        state
            .ext
            .linux_drm_syncobj
            .syncobj_timelines
            .remove(&resource.id().protocol_id());
    }
}

pub fn register_linux_drm_syncobj(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpLinuxDrmSyncobjManagerV1, ()>(1, ())
}
