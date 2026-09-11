//! Linux DRM Syncobj protocol implementation.

use std::collections::HashMap;

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

use wayland_server::DisplayHandle;

pub fn register_linux_drm_syncobj(_display: &DisplayHandle) {
    // TODO: Register global
}
