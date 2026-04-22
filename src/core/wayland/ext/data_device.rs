//! wl_data_device_manager and related protocols implementation
//!
//! The data device manager handles clipboard operations and drag-and-drop.
//! This is essential for:
//! - Copy/paste operations
//! - Drag-and-drop between applications
//! - MIME type negotiation


use std::os::unix::io::AsFd;
use wayland_server::{
    protocol::{
        wl_data_device::{self, WlDataDevice},
        wl_data_device_manager::{self, WlDataDeviceManager},
        wl_data_offer::{self, WlDataOffer},
        wl_data_source::{self, WlDataSource},

    },
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;
use crate::core::surface::SurfaceRole;

use std::collections::HashMap;

use wayland_server::protocol::wl_data_device_manager::DndAction;

/// Data stored with data source
#[derive(Debug, Clone)]
pub struct DataSourceData {
    pub resource: Option<WlDataSource>,
    pub mime_types: Vec<String>,
    pub dnd_actions: DndAction,
    pub used: bool,
}

impl Default for DataSourceData {
    fn default() -> Self {
        Self {
            resource: None,
            mime_types: Vec::new(),
            dnd_actions: DndAction::empty(),
            used: false,
        }
    }
}

impl DataSourceData {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Debug, Clone)]
pub struct DataOfferData {
    pub resource: Option<WlDataOffer>,
    pub device_id: u32,
    pub source_id: Option<u32>,
    pub mime_types: Vec<String>,
    /// Source's advertised DnD actions (from wl_data_source::SetActions)
    pub source_dnd_actions: DndAction,
    /// Destination's preferred action (from wl_data_offer::SetActions)
    pub preferred_action: Option<DndAction>,
}

#[derive(Debug, Clone)]
pub struct DataDeviceData {
    pub seat_id: u32,
    pub resource: wayland_server::protocol::wl_data_device::WlDataDevice,
}

/// Active drag-and-drop operation state
#[derive(Debug, Clone)]
pub struct DragState {
    /// The data source for this drag (if any — drags without source are icon-only)
    pub source_id: Option<u32>,
    /// The surface where the drag originated
    pub origin_surface_id: u32,
    /// The icon surface (displayed under the cursor during drag)
    pub icon_surface_id: Option<u32>,
    /// The surface currently under the drag pointer (for enter/leave tracking)
    pub focus_surface_id: Option<u32>,
    /// The data offer created for the current focus surface
    pub current_offer_id: Option<u32>,
    /// Pre-created offers keyed by wl_data_device protocol id.
    pub offer_by_device: HashMap<u32, u32>,
    /// Serial of the grab that started this drag
    pub serial: u32,
}

/// Data device protocol state — clipboard, drag-and-drop,
/// data sources, offers, and devices.
pub struct DataDeviceState {
    /// Data sources (source_id -> data)
    pub sources: HashMap<u32, DataSourceData>,
    /// Data offers (offer_id -> data)
    pub offers: HashMap<u32, DataOfferData>,
    /// Data devices (device_id -> data)
    pub devices: HashMap<u32, DataDeviceData>,
    /// Active drag-and-drop operation (None when no drag is in progress)
    pub drag: Option<DragState>,
}

impl Default for DataDeviceState {
    fn default() -> Self {
        Self {
            sources: HashMap::new(),
            offers: HashMap::new(),
            devices: HashMap::new(),
            drag: None,
        }
    }
}


// ============================================================================
// wl_data_device_manager implementation
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ GlobalDispatch<WlDataDeviceManager, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlDataDeviceManager>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<WlDataDeviceManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WlDataDeviceManager,
        request: wl_data_device_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_data_device_manager::Request::CreateDataSource { id } => {
                let source = data_init.init(id, ());
                let mut source_data = DataSourceData::new();
                source_data.resource = Some(source.clone());
                state.data.sources.insert(source.id().protocol_id(), source_data);
                
                tracing::debug!("Created data source");
            }
            wl_data_device_manager::Request::GetDataDevice { id, seat } => {
                let device = data_init.init(id, ());
                let device_data = DataDeviceData { 
                    seat_id: seat.id().protocol_id(),
                    resource: device.clone(),
                };
                state.data.devices.insert(device.id().protocol_id(), device_data);
                
                tracing::debug!("Created data device for seat");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_data_source implementation
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<WlDataSource, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WlDataSource,
        request: wl_data_source::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let source_id = resource.id().protocol_id();
        
        match request {
            wl_data_source::Request::Offer { mime_type } => {
                tracing::debug!("Data source offers MIME type: {}", mime_type);
                if let Some(data) = state.data.sources.get_mut(&source_id) {
                    data.mime_types.push(mime_type);
                }
            }
            wl_data_source::Request::SetActions { dnd_actions } => {
                tracing::debug!("Data source set DnD actions: {:?}", dnd_actions);
                if let Some(data) = state.data.sources.get_mut(&source_id) {
                    data.dnd_actions = dnd_actions.into_result().unwrap_or(wayland_server::protocol::wl_data_device_manager::DndAction::empty());
                }
            }
            wl_data_source::Request::Destroy => {
                state.data.sources.remove(&source_id);
                tracing::debug!("Data source destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_data_device implementation
// ============================================================================

#[cfg(feature = "legacy-custom-runtime")]
impl/*legacy*/ Dispatch<WlDataDevice, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WlDataDevice,
        request: wl_data_device::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_data_device::Request::StartDrag {
                source,
                origin,
                icon,
                serial,
            } => {
                tracing::debug!(
                    "Start drag: serial={}, has_source={}, has_icon={}",
                    serial,
                    source.is_some(),
                    icon.is_some()
                );
                
                let source_id = source.as_ref().map(|s| s.id().protocol_id());

                // start_drag requires the current implicit-grab serial.
                if serial != state.seat.pointer.last_button_serial || state.seat.pointer.button_count == 0 {
                    tracing::debug!(
                        "Ignoring start_drag with invalid serial {} (last button serial: {}, button_count: {})",
                        serial,
                        state.seat.pointer.last_button_serial,
                        state.seat.pointer.button_count
                    );
                    return;
                }

                if let Some(source_id) = source_id {
                    if let Some(source_data) = state.data.sources.get_mut(&source_id) {
                        if source_data.used {
                            resource.post_error(
                                wl_data_device::Error::UsedSource,
                                format!("data source {} already used", source_id),
                            );
                            return;
                        }
                        source_data.used = true;
                    }
                }

                if let Some(icon_surface) = icon.as_ref() {
                    let protocol_id = icon_surface.id().protocol_id();
                    let mapped = state
                        .protocol_to_internal_surface
                        .get(&(_client.id(), protocol_id))
                        .copied()
                        .unwrap_or(protocol_id);
                    if let Some(surface_ref) = state.get_surface(mapped) {
                        let mut surface_state = surface_ref.write().unwrap();
                        if let Err(err) = surface_state.set_role(SurfaceRole::Cursor) {
                            resource.post_error(
                                wl_data_device::Error::Role,
                                format!("drag icon surface role conflict: {}", err),
                            );
                            return;
                        }
                    }
                }

                state.start_drag(
                    _dhandle,
                    source_id,
                    origin.id().protocol_id(),
                    icon.as_ref().map(|i| i.id().protocol_id()),
                    serial,
                );
            }
            wl_data_device::Request::SetSelection { source, serial } => {
                tracing::debug!(
                    "Set selection (clipboard): serial={}, has_source={}",
                    serial,
                    source.is_some()
                );
                
                if let Some(source) = source.as_ref() {
                    let source_id = source.id().protocol_id();
                    if let Some(source_data) = state.data.sources.get_mut(&source_id) {
                        if source_data.used {
                            resource.post_error(
                                wl_data_device::Error::UsedSource,
                                format!("data source {} already used", source_id),
                            );
                            return;
                        }
                        source_data.used = true;
                    }
                }

                let selection_source = source.as_ref().map(|s| crate::core::state::SelectionSource::Wayland(s.clone()));
                state.set_clipboard_source(_dhandle, selection_source);
            }
            wl_data_device::Request::Release => {
                state.data.devices.remove(&resource.id().protocol_id());
                tracing::debug!("Data device released");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_data_offer implementation
// ============================================================================

/// Compute the negotiated DnD action from source and destination preferences.
fn negotiated_dnd_action(source_actions: DndAction, dest_actions: DndAction, preferred: Option<DndAction>) -> DndAction {
    let allowed = source_actions & dest_actions;
    if allowed.is_empty() {
        return DndAction::empty();
    }
    if let Some(p) = preferred {
        if allowed.contains(p) {
            return p;
        }
    }
    if allowed.contains(DndAction::Copy) {
        return DndAction::Copy;
    }
    if allowed.contains(DndAction::Move) {
        return DndAction::Move;
    }
    if allowed.contains(DndAction::Ask) {
        return DndAction::Ask;
    }
    DndAction::empty()
}

impl/*legacy*/ Dispatch<WlDataOffer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WlDataOffer,
        request: wl_data_offer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_data_offer::Request::Accept { serial, mime_type } => {
                tracing::debug!(
                    "Data offer accept: serial={}, mime_type={:?}",
                    serial,
                    mime_type
                );
            }
            wl_data_offer::Request::Receive { mime_type, fd } => {
                tracing::debug!("Data offer receive: mime_type={}", mime_type);
                // Look up the source and ask it to send data
                let offer_id = resource.id().protocol_id();
                if let Some(offer_data) = state.data.offers.get(&offer_id) {
                    if let Some(source_id) = offer_data.source_id {
                        if let Some(source_data) = state.data.sources.get(&source_id) {
                            if let Some(src) = source_data.resource.as_ref() {
                                src.send(mime_type, fd.as_fd());
                                tracing::debug!("Forwarded receive to wl_data_source {}", source_id);
                            }
                        }
                    }
                }
                drop(fd);
            }
            wl_data_offer::Request::Destroy => {
                state.data.offers.remove(&resource.id().protocol_id());
                tracing::debug!("Data offer destroyed");
            }
            wl_data_offer::Request::Finish => {
                let offer_id = resource.id().protocol_id();
                let (source_id, negotiated) = if let Some(offer_data) = state.data.offers.get(&offer_id) {
                    let dest_actions = offer_data.preferred_action.unwrap_or(DndAction::empty());
                    let negotiated = negotiated_dnd_action(
                        offer_data.source_dnd_actions,
                        dest_actions,
                        offer_data.preferred_action,
                    );
                    (offer_data.source_id, negotiated)
                } else {
                    (None, DndAction::empty())
                };
                if let Some(sid) = source_id {
                    if let Some(source_data) = state.data.sources.get(&sid) {
                        if let Some(src) = source_data.resource.as_ref() {
                            if src.is_alive() {
                                src.action(negotiated);
                                src.dnd_finished();
                            }
                        }
                    }
                }
                tracing::debug!("Data offer finished (DnD complete), action={:?}", negotiated);
            }
            wl_data_offer::Request::SetActions {
                dnd_actions,
                preferred_action,
            } => {
                let offer_id = resource.id().protocol_id();
                let dest_actions = dnd_actions.into_result().unwrap_or(DndAction::empty());
                let preferred = preferred_action.into_result().ok();
                if let Some(offer_data) = state.data.offers.get_mut(&offer_id) {
                    offer_data.preferred_action = preferred.or(offer_data.preferred_action);
                    let negotiated = negotiated_dnd_action(
                        offer_data.source_dnd_actions,
                        dest_actions,
                        preferred,
                    );
                    if resource.version() >= 3 && !negotiated.is_empty() {
                        resource.action(negotiated);
                    }
                }
                tracing::debug!(
                    "Data offer set actions: {:?}, preferred: {:?}",
                    dest_actions,
                    preferred
                );
            }
            _ => {}
        }
    }
}

/// Register wl_data_device_manager global
pub fn register_data_device_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WlDataDeviceManager, ()>(3, ())
}
