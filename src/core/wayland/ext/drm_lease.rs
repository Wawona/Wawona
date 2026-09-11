//! DRM Lease protocol implementation.

use std::collections::HashMap;

/// State for the drm-lease-v1 protocol
#[derive(Debug, Default)]
pub struct DrmLeaseState {
    /// DRM Lease connectors (connector_resource_id -> connector_id)
    pub lease_connectors: HashMap<u32, u32>,
}

use wayland_server::DisplayHandle;

pub fn register_drm_lease(_display: &DisplayHandle) {
    // TODO: Register global
}
