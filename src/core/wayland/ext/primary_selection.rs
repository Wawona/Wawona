//! Primary Selection protocol implementation.
//!
//! This protocol provides primary selection (middle-click paste) functionality,
//! commonly used in X11/Wayland applications. It mirrors the wl_data_device
//! clipboard model but for a separate "primary" selection buffer.

use std::collections::HashMap;
use std::os::unix::io::AsFd;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::primary_selection::zv1::server::{
    zwp_primary_selection_device_manager_v1::{self, ZwpPrimarySelectionDeviceManagerV1},
    zwp_primary_selection_device_v1::{self, ZwpPrimarySelectionDeviceV1},
    zwp_primary_selection_source_v1::{self, ZwpPrimarySelectionSourceV1},
    zwp_primary_selection_offer_v1::{self, ZwpPrimarySelectionOfferV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone)]
pub struct PrimarySelectionSourceData {
    pub mime_types: Vec<String>,
}

impl Default for PrimarySelectionSourceData {
    fn default() -> Self {
        Self { mime_types: Vec::new() }
    }
}

#[derive(Debug, Clone)]
pub struct PrimarySelectionOfferData {
    pub source_id: Option<u32>,
    pub mime_types: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PrimarySelectionDeviceInfo {
    pub resource: ZwpPrimarySelectionDeviceV1,
}

/// Tracks the primary selection state
#[derive(Debug, Default)]
pub struct PrimarySelectionState {
    /// Source resource id → source data
    pub sources: HashMap<u32, PrimarySelectionSourceData>,
    /// Device resource id → device info
    pub devices: HashMap<u32, PrimarySelectionDeviceInfo>,
    /// Offer resource id → offer data
    pub offers: HashMap<u32, PrimarySelectionOfferData>,
    /// Currently active primary selection source
    pub current_source: Option<ZwpPrimarySelectionSourceV1>,
}

// ============================================================================
// zwp_primary_selection_device_manager_v1
// ============================================================================

impl GlobalDispatch<ZwpPrimarySelectionDeviceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpPrimarySelectionDeviceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_primary_selection_device_manager_v1");
    }
}

impl Dispatch<ZwpPrimarySelectionDeviceManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpPrimarySelectionDeviceManagerV1,
        request: zwp_primary_selection_device_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_primary_selection_device_manager_v1::Request::CreateSource { id } => {
                let source = data_init.init(id, ());
                let source_id = source.id().protocol_id();
                state.ext.primary_selection.sources.insert(source_id, PrimarySelectionSourceData::default());
                tracing::debug!("Created primary selection source {}", source_id);
            }
            zwp_primary_selection_device_manager_v1::Request::GetDevice { id, seat } => {
                let device = data_init.init(id, ());
                let device_id = device.id().protocol_id();
                let _seat_id = seat.id().protocol_id();
                state.ext.primary_selection.devices.insert(device_id, PrimarySelectionDeviceInfo {
                    resource: device,
                });
                tracing::debug!("Created primary selection device {}", device_id);
            }
            zwp_primary_selection_device_manager_v1::Request::Destroy => {
                tracing::debug!("zwp_primary_selection_device_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_primary_selection_device_v1
// ============================================================================

impl Dispatch<ZwpPrimarySelectionDeviceV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpPrimarySelectionDeviceV1,
        request: zwp_primary_selection_device_v1::Request,
        _data: &(),
        dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_primary_selection_device_v1::Request::SetSelection { source, serial: _ } => {
                // Store the current source
                state.ext.primary_selection.current_source = source.clone();

                if let Some(src) = &source {
                    let source_id = src.id().protocol_id();
                    let mime_types = state.ext.primary_selection.sources
                        .get(&source_id)
                        .map(|d| d.mime_types.clone())
                        .unwrap_or_default();

                    // Notify all devices about the new selection via a data offer
                    let device_ids: Vec<u32> = state.ext.primary_selection.devices.keys().cloned().collect();
                    for dev_id in device_ids {
                        if let Some(device_info) = state.ext.primary_selection.devices.get(&dev_id) {
                            if !device_info.resource.is_alive() {
                                continue;
                            }
                            // Create offer resource
                            if let Some(client) = device_info.resource.client() {
                                if let Ok(offer_res) = client.create_resource::<ZwpPrimarySelectionOfferV1, (), CompositorState>(
                                    dhandle,
                                    device_info.resource.version(),
                                    (),
                                ) {
                                    let offer_id = offer_res.id().protocol_id();
                                    state.ext.primary_selection.offers.insert(offer_id, PrimarySelectionOfferData {
                                        source_id: Some(source_id),
                                        mime_types: mime_types.clone(),
                                    });

                                    device_info.resource.data_offer(&offer_res);
                                    for mime in &mime_types {
                                        offer_res.offer(mime.clone());
                                    }
                                    device_info.resource.selection(Some(&offer_res));
                                }
                            }
                        }
                    }
                    tracing::debug!("Primary selection set from source {} with {} MIME types", source_id, mime_types.len());
                } else {
                    // Clear selection. Send selection(None) to all devices
                    for device_info in state.ext.primary_selection.devices.values() {
                        if device_info.resource.is_alive() {
                            device_info.resource.selection(None);
                        }
                    }
                    tracing::debug!("Primary selection cleared");
                }
            }
            zwp_primary_selection_device_v1::Request::Destroy => {
                tracing::debug!("zwp_primary_selection_device_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_primary_selection_source_v1
// ============================================================================

impl Dispatch<ZwpPrimarySelectionSourceV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpPrimarySelectionSourceV1,
        request: zwp_primary_selection_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let source_id = resource.id().protocol_id();
        match request {
            zwp_primary_selection_source_v1::Request::Offer { mime_type } => {
                if let Some(data) = state.ext.primary_selection.sources.get_mut(&source_id) {
                    data.mime_types.push(mime_type.clone());
                }
                tracing::debug!("Primary selection source {} offer: {}", source_id, mime_type);
            }
            zwp_primary_selection_source_v1::Request::Destroy => {
                state.ext.primary_selection.sources.remove(&source_id);
                // If this was the current source, clear it
                if let Some(current) = &state.ext.primary_selection.current_source {
                    if current.id().protocol_id() == source_id {
                        state.ext.primary_selection.current_source = None;
                    }
                }
                tracing::debug!("Primary selection source {} destroyed", source_id);
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_primary_selection_offer_v1
// ============================================================================

impl Dispatch<ZwpPrimarySelectionOfferV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpPrimarySelectionOfferV1,
        request: zwp_primary_selection_offer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_primary_selection_offer_v1::Request::Receive { mime_type, fd } => {
                let offer_id = resource.id().protocol_id();
                if let Some(offer_data) = state.ext.primary_selection.offers.get(&offer_id) {
                    if let Some(source_id) = offer_data.source_id {
                        // Forward the receive to the source
                        if let Some(current) = &state.ext.primary_selection.current_source {
                            if current.id().protocol_id() == source_id && current.is_alive() {
                                current.send(mime_type.clone(), fd.as_fd());
                                tracing::debug!("Primary selection receive forwarded to source {}: {}", source_id, mime_type);
                            }
                        }
                    }
                }
                drop(fd);
            }
            zwp_primary_selection_offer_v1::Request::Destroy => {
                state.ext.primary_selection.offers.remove(&resource.id().protocol_id());
                tracing::debug!("Primary selection offer destroyed");
            }
            _ => {}
        }
    }
}

/// Register zwp_primary_selection_device_manager_v1 global
pub fn register_primary_selection(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpPrimarySelectionDeviceManagerV1, ()>(1, ())
}
