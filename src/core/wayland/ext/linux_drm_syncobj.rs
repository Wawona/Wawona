//! linux-drm-syncobj-v1: timeline fences for GPU clients.
//!
//! Registers the global and accepts surface attach of acquire/release
//! timelines. Full DRM syncobj wait/signal on Linux GBM present is follow-on;
//! Apple/Android treat attach as acknowledged (IOSurface/AHB already ordered
//! by Metal/Vulkan). See docs/linux-dmabuf-zero-copy.md.

use std::collections::HashMap;

use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
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

#[cfg(feature = "desktop-protocols")]
mod proto {
    use super::*;
    use wayland_protocols::wp::linux_drm_syncobj::v1::server::{
        wp_linux_drm_syncobj_manager_v1, wp_linux_drm_syncobj_surface_v1,
        wp_linux_drm_syncobj_timeline_v1,
    };

    pub struct SyncobjSurfaceData {
        pub surface_id: u32,
    }

    pub struct SyncobjTimelineData {
        pub fd: Option<i32>,
    }

    impl GlobalDispatch<wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1, ()>
        for CompositorState
    {
        fn bind(
            _state: &mut Self,
            _handle: &DisplayHandle,
            _client: &wayland_server::Client,
            resource: wayland_server::New<
                wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1,
            >,
            _global_data: &(),
            data_init: &mut wayland_server::DataInit<'_, Self>,
        ) {
            let _mgr = data_init.init(resource, ());
            tracing::info!(
                target: "wwn.dmabuf",
                op = "bind",
                protocol = "wp_linux_drm_syncobj_manager_v1",
                "linux-drm-syncobj manager bound"
            );
        }
    }

    impl Dispatch<wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1, ()>
        for CompositorState
    {
        fn request(
            state: &mut Self,
            _client: &wayland_server::Client,
            _resource: &wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1,
            request: wp_linux_drm_syncobj_manager_v1::Request,
            _data: &(),
            _dhandle: &DisplayHandle,
            data_init: &mut wayland_server::DataInit<'_, Self>,
        ) {
            match request {
                wp_linux_drm_syncobj_manager_v1::Request::GetSurface { id, surface } => {
                    let surface_id = surface.id().protocol_id();
                    let sync = data_init.init(
                        id,
                        SyncobjSurfaceData { surface_id },
                    );
                    let sync_id = sync.id().protocol_id();
                    state
                        .ext
                        .linux_drm_syncobj
                        .surface_sync_states
                        .insert(sync_id, surface_id);
                    state
                        .ext
                        .linux_drm_syncobj
                        .syncobj_surfaces
                        .insert(sync_id, surface_id);
                    tracing::debug!(
                        target: "wwn.dmabuf",
                        op = "create",
                        protocol = "wp_linux_drm_syncobj_surface_v1",
                        surface_id,
                        "syncobj surface attached"
                    );
                }
                wp_linux_drm_syncobj_manager_v1::Request::ImportTimeline { id, fd } => {
                    use std::os::fd::IntoRawFd;
                    let raw = fd.into_raw_fd();
                    let timeline = data_init.init(
                        id,
                        SyncobjTimelineData {
                            fd: Some(raw),
                        },
                    );
                    let tid = timeline.id().protocol_id();
                    state
                        .ext
                        .linux_drm_syncobj
                        .syncobj_timelines
                        .insert(tid, Some(raw));
                    tracing::debug!(
                        target: "wwn.dmabuf",
                        op = "create",
                        protocol = "wp_linux_drm_syncobj_timeline_v1",
                        timeline_id = tid,
                        "syncobj timeline imported"
                    );
                }
                wp_linux_drm_syncobj_manager_v1::Request::Destroy => {}
                _ => {}
            }
        }
    }

    impl Dispatch<wp_linux_drm_syncobj_surface_v1::WpLinuxDrmSyncobjSurfaceV1, SyncobjSurfaceData>
        for CompositorState
    {
        fn request(
            _state: &mut Self,
            _client: &wayland_server::Client,
            _resource: &wp_linux_drm_syncobj_surface_v1::WpLinuxDrmSyncobjSurfaceV1,
            request: wp_linux_drm_syncobj_surface_v1::Request,
            data: &SyncobjSurfaceData,
            _dhandle: &DisplayHandle,
            _data_init: &mut wayland_server::DataInit<'_, Self>,
        ) {
            match request {
                wp_linux_drm_syncobj_surface_v1::Request::SetAcquirePoint {
                    timeline: _,
                    point_hi: _,
                    point_lo: _,
                }
                | wp_linux_drm_syncobj_surface_v1::Request::SetReleasePoint {
                    timeline: _,
                    point_hi: _,
                    point_lo: _,
                } => {
                    tracing::trace!(
                        target: "wwn.dmabuf",
                        op = "import",
                        surface_id = data.surface_id,
                        "syncobj acquire/release point set (acknowledged)"
                    );
                }
                wp_linux_drm_syncobj_surface_v1::Request::Destroy => {}
                _ => {}
            }
        }
    }

    impl Dispatch<wp_linux_drm_syncobj_timeline_v1::WpLinuxDrmSyncobjTimelineV1, SyncobjTimelineData>
        for CompositorState
    {
        fn request(
            _state: &mut Self,
            _client: &wayland_server::Client,
            _resource: &wp_linux_drm_syncobj_timeline_v1::WpLinuxDrmSyncobjTimelineV1,
            request: wp_linux_drm_syncobj_timeline_v1::Request,
            data: &SyncobjTimelineData,
            _dhandle: &DisplayHandle,
            _data_init: &mut wayland_server::DataInit<'_, Self>,
        ) {
            match request {
                wp_linux_drm_syncobj_timeline_v1::Request::Destroy => {
                    if let Some(fd) = data.fd {
                        unsafe {
                            libc::close(fd);
                        }
                    }
                }
                _ => {}
            }
        }
    }

    pub fn register(display: &DisplayHandle) {
        display.create_global::<
            CompositorState,
            wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1,
            (),
        >(1, ());
        tracing::info!(
            target: "wwn.dmabuf",
            op = "bind",
            protocol = "wp_linux_drm_syncobj_manager_v1",
            "registered linux-drm-syncobj-v1"
        );
    }
}

pub fn register_linux_drm_syncobj(display: &DisplayHandle) {
    #[cfg(feature = "desktop-protocols")]
    {
        proto::register(display);
    }
    #[cfg(not(feature = "desktop-protocols"))]
    {
        let _ = display;
        tracing::debug!(
            target: "wwn.dmabuf",
            "linux-drm-syncobj skipped (desktop-protocols feature off)"
        );
    }
}
