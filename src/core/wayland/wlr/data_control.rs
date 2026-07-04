
use std::os::unix::io::AsFd;
use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol::wlroots::wlr_data_control_unstable_v1::{
    zwlr_data_control_manager_v1,
    zwlr_data_control_device_v1,
    zwlr_data_control_source_v1,
    zwlr_data_control_offer_v1,
};

pub struct DataControlManagerData;

use wayland_server::protocol::wl_data_device_manager::DndAction;

#[derive(Debug, Clone)]
pub struct DataControlSourceData {
    pub mime_types: Vec<String>,
    pub dnd_actions: DndAction,
    pub client_id: Option<wayland_server::backend::ClientId>,
}

impl Default for DataControlSourceData {
    fn default() -> Self {
        Self {
            mime_types: Vec::new(),
            dnd_actions: DndAction::empty(),
            client_id: None,
        }
    }
}

use crate::core::traits::ProtocolState;

#[derive(Debug, Default)]
pub struct DataControlState {
    pub selection_source: Option<zwlr_data_control_source_v1::ZwlrDataControlSourceV1>,
    pub primary_selection_source: Option<zwlr_data_control_source_v1::ZwlrDataControlSourceV1>,
    pub sources: std::collections::HashMap<u32, DataControlSourceData>,
}

impl ProtocolState for DataControlState {
    fn client_disconnected(&mut self, client_id: wayland_server::backend::ClientId) {
        self.sources.retain(|_, data| {
            if let Some(owner) = &data.client_id {
                *owner != client_id
            } else {
                true
            }
        });
        
        if let Some(src) = &self.selection_source {
            if let Some(c) = src.client() {
                if c.id() == client_id {
                    self.selection_source = None;
                }
            }
        }
        
        if let Some(src) = &self.primary_selection_source {
            if let Some(c) = src.client() {
                if c.id() == client_id {
                    self.primary_selection_source = None;
                }
            }
        }
    }
}


impl GlobalDispatch<zwlr_data_control_manager_v1::ZwlrDataControlManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_data_control_manager_v1::ZwlrDataControlManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_data_control_manager_v1::ZwlrDataControlManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_data_control_manager_v1::ZwlrDataControlManagerV1,
        request: zwlr_data_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_data_control_manager_v1::Request::CreateDataSource { id } => {
                let source = data_init.init(id, ());
                let mut data = DataControlSourceData::default();
                if let Some(client) = source.client() {
                    data.client_id = Some(client.id());
                }
                state.wlr.data_control.sources.insert(source.id().protocol_id(), data);
            }
            zwlr_data_control_manager_v1::Request::GetDataDevice { id, seat: _ } => {
                let device = data_init.init(id, ());
                
                // Send initial selection events if available
                // Note: In a real implementation we would clone the current selection offer
                // and send it. For now we acknowledge no selection if none exists.
                if state.wlr.data_control.selection_source.is_none() {
                    device.selection(None);

                }
                
                if device.version() >= 2 {
                    if state.wlr.data_control.primary_selection_source.is_none() {
                         device.primary_selection(None);

                    }
                }
            }
            zwlr_data_control_manager_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_data_control_device_v1::ZwlrDataControlDeviceV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_data_control_device_v1::ZwlrDataControlDeviceV1,
        request: zwlr_data_control_device_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_data_control_device_v1::Request::SetSelection { source } => {
                tracing::debug!("Global selection source updated by data_control client");
                let selection_source = source.as_ref().map(|s| crate::core::state::SelectionSource::Wlr(s.clone()));
                state.set_clipboard_source(selection_source);
            }
            zwlr_data_control_device_v1::Request::SetPrimarySelection { source: _ } => {
                tracing::debug!("Global primary selection source updated by data_control client");
            }
            zwlr_data_control_device_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_data_control_source_v1::ZwlrDataControlSourceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_data_control_source_v1::ZwlrDataControlSourceV1,
        request: zwlr_data_control_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let source_id = _resource.id().protocol_id();
        match request {
            zwlr_data_control_source_v1::Request::Offer { mime_type } => {
                tracing::debug!("data_control offer mime_type: {}", mime_type);
                if let Some(data) = _state.wlr.data_control.sources.get_mut(&source_id) {
                    data.mime_types.push(mime_type);
                }
            }
            zwlr_data_control_source_v1::Request::Destroy => {
                _state.wlr.data_control.sources.remove(&source_id);
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_data_control_offer_v1::ZwlrDataControlOfferV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_data_control_offer_v1::ZwlrDataControlOfferV1,
        request: zwlr_data_control_offer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_data_control_offer_v1::Request::Receive { mime_type, fd } => {
                tracing::debug!("data_control receive request for {}", mime_type);
                // Forward the receive request to the current selection source
                if let Some(selection) = &_state.seat.current_selection {
                    match selection {
                        crate::core::state::SelectionSource::Wayland(src) => {
                            src.send(mime_type, fd.as_fd());
                            tracing::debug!("Forwarded data_control receive to wl_data_source");
                        }
                        crate::core::state::SelectionSource::Wlr(src) => {
                            src.send(mime_type, fd.as_fd());
                            tracing::debug!("Forwarded data_control receive to wlr source");
                        }
                    }
                }
                drop(fd);
            }
            zwlr_data_control_offer_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

/// Register zwlr_data_control_manager_v1 global
pub fn register_data_control(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_data_control_manager_v1::ZwlrDataControlManagerV1, ()>(1, ())
}
