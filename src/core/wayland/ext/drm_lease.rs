//! `wp_drm_lease_device_v1` — lease DRM connectors to clients (VR / exclusive display).
//!
//! Smithay's helper lives behind `backend_drm`, which Wawona deliberately does
//! not enable (`wayland_frontend` only). This is a protocol-complete path that
//! opens a DRM node on Linux, advertises zero leaseable connectors by default,
//! and rejects lease requests until a backend can supply CRTCs/planes.
//!
//! Runtime gate: caller requires `policy::allow_desktop_extensions(protocol_profile)`
//! plus a live DRM node (`register_drm_lease` returns `None` without one).

use std::collections::HashMap;
use std::fs::OpenOptions;
use std::os::fd::{AsFd, OwnedFd};
use std::os::unix::fs::OpenOptionsExt;

use wayland_protocols::wp::drm_lease::v1::server::{
    wp_drm_lease_connector_v1::{self, WpDrmLeaseConnectorV1},
    wp_drm_lease_device_v1::{self, WpDrmLeaseDeviceV1},
    wp_drm_lease_request_v1::{self, WpDrmLeaseRequestV1},
    wp_drm_lease_v1::{self, WpDrmLeaseV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// State for the drm-lease-v1 protocol
#[derive(Debug, Default)]
pub struct DrmLeaseState {
    /// DRM Lease connectors (connector_resource_id -> connector_id)
    pub lease_connectors: HashMap<u32, u32>,
    /// Cached DRM device fd duplicated to each bound client, when available.
    drm_fd: Option<OwnedFd>,
}

impl DrmLeaseState {
    fn ensure_drm_fd(&mut self) -> Option<&OwnedFd> {
        if self.drm_fd.is_none() {
            self.drm_fd = open_drm_device_fd();
        }
        self.drm_fd.as_ref()
    }
}

fn open_drm_device_fd() -> Option<OwnedFd> {
    #[cfg(target_os = "linux")]
    {
        const CANDIDATES: &[&str] = &[
            "/dev/dri/card0",
            "/dev/dri/card1",
            "/dev/dri/renderD128",
            "/dev/dri/renderD129",
        ];
        for path in CANDIDATES {
            if let Ok(file) = OpenOptions::new()
                .read(true)
                .write(true)
                .custom_flags(libc::O_CLOEXEC)
                .open(path)
            {
                tracing::info!("drm-lease: opened DRM node {path}");
                return Some(file.into());
            }
        }
        tracing::warn!("drm-lease: no DRM node available; global not registered");
        None
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

impl GlobalDispatch<WpDrmLeaseDeviceV1, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpDrmLeaseDeviceV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let device = data_init.init(resource, ());
        if let Some(fd) = state.ext.drm_lease.ensure_drm_fd() {
            device.drm_fd(fd.as_fd());
            // No connectors are leaseable without a KMS backend that
            // can withdraw CRTCs. Still finish the bind sequence.
            device.done();
        } else {
            // Should not bind without a node; send released to tear down.
            device.released();
        }
    }
}

impl Dispatch<WpDrmLeaseDeviceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &WpDrmLeaseDeviceV1,
        request: wp_drm_lease_device_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_drm_lease_device_v1::Request::CreateLeaseRequest { id } => {
                data_init.init(id, ());
            }
            wp_drm_lease_device_v1::Request::Release => {
                resource.released();
            }
            _ => {}
        }
    }
}

impl Dispatch<WpDrmLeaseRequestV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &WpDrmLeaseRequestV1,
        request: wp_drm_lease_request_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_drm_lease_request_v1::Request::RequestConnector { connector } => {
                // No connectors are advertised, so any request is a protocol error.
                let _ = connector;
                resource.post_error(
                    wp_drm_lease_request_v1::Error::WrongDevice,
                    "no leaseable connectors are advertised",
                );
            }
            wp_drm_lease_request_v1::Request::Submit { id } => {
                // new_id must be initialized even when raising empty_lease.
                let _lease = data_init.init(id, ());
                resource.post_error(
                    wp_drm_lease_request_v1::Error::EmptyLease,
                    "requested a lease without requesting a connector",
                );
            }
            _ => {}
        }
    }
}

impl Dispatch<WpDrmLeaseV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpDrmLeaseV1,
        request: wp_drm_lease_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_drm_lease_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpDrmLeaseConnectorV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpDrmLeaseConnectorV1,
        request: wp_drm_lease_connector_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_drm_lease_connector_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

/// Register `wp_drm_lease_device_v1` when a DRM node is available (Linux).
pub fn register_drm_lease(display: &DisplayHandle) -> Option<wayland_server::backend::GlobalId> {
    if open_drm_device_fd().is_none() {
        return None;
    }
    Some(display.create_global::<CompositorState, WpDrmLeaseDeviceV1, ()>(1, ()))
}
