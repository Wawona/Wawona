//! ext_data_control_v1. Clipboard manager access (staging successor to wlr-data-control).

use std::os::unix::io::AsFd;

use crate::core::traits::ProtocolState;
use crate::core::wayland::protocol::server::ext::data_control::v1::server::{
    ext_data_control_device_v1::{self, ExtDataControlDeviceV1},
    ext_data_control_manager_v1::{self, ExtDataControlManagerV1},
    ext_data_control_offer_v1::{self, ExtDataControlOfferV1},
    ext_data_control_source_v1::{self, ExtDataControlSourceV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct ExtDataControlSourceData {
    pub mime_types: Vec<String>,
    pub client_id: Option<wayland_server::backend::ClientId>,
}

#[derive(Debug, Default)]
pub struct ExtDataControlState {
    pub selection_source: Option<ExtDataControlSourceV1>,
    pub primary_selection_source: Option<ExtDataControlSourceV1>,
    pub sources: std::collections::HashMap<u32, ExtDataControlSourceData>,
}

impl ProtocolState for ExtDataControlState {
    fn client_disconnected(&mut self, client_id: wayland_server::backend::ClientId) {
        self.sources.retain(|_, data| match data.client_id.as_ref() {
            Some(owner) => *owner != client_id,
            None => true,
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

impl GlobalDispatch<ExtDataControlManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtDataControlManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_data_control_manager_v1");
    }
}

impl Dispatch<ExtDataControlManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlManagerV1,
        request: ext_data_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_manager_v1::Request::CreateDataSource { id } => {
                let source = data_init.init(id, ());
                let mut data = ExtDataControlSourceData::default();
                if let Some(client) = source.client() {
                    data.client_id = Some(client.id());
                }
                state
                    .ext
                    .data_control
                    .sources
                    .insert(source.id().protocol_id(), data);
            }
            ext_data_control_manager_v1::Request::GetDataDevice { id, seat: _ } => {
                let device = data_init.init(id, ());
                if state.ext.data_control.selection_source.is_none() {
                    device.selection(None);
                }
                if device.version() >= 2 && state.ext.data_control.primary_selection_source.is_none()
                {
                    device.primary_selection(None);
                }
            }
            ext_data_control_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlDeviceV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlDeviceV1,
        request: ext_data_control_device_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_device_v1::Request::SetSelection { source } => {
                state.ext.data_control.selection_source = source.clone();
                let selection_source = source
                    .as_ref()
                    .map(|s| crate::core::state::SelectionSource::Ext(s.clone()));
                state.set_clipboard_source(selection_source);
            }
            ext_data_control_device_v1::Request::SetPrimarySelection { source } => {
                state.ext.data_control.primary_selection_source = source;
            }
            ext_data_control_device_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlSourceV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtDataControlSourceV1,
        request: ext_data_control_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let source_id = resource.id().protocol_id();
        match request {
            ext_data_control_source_v1::Request::Offer { mime_type } => {
                if let Some(data) = state.ext.data_control.sources.get_mut(&source_id) {
                    data.mime_types.push(mime_type);
                }
            }
            ext_data_control_source_v1::Request::Destroy => {
                state.ext.data_control.sources.remove(&source_id);
                if state
                    .ext
                    .data_control
                    .selection_source
                    .as_ref()
                    .map(|s| s.id().protocol_id() == source_id)
                    .unwrap_or(false)
                {
                    state.ext.data_control.selection_source = None;
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlOfferV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlOfferV1,
        request: ext_data_control_offer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_offer_v1::Request::Receive { mime_type, fd } => {
                if let Some(selection) = &state.seat.current_selection {
                    match selection {
                        crate::core::state::SelectionSource::Wayland(src) => {
                            src.send(mime_type, fd.as_fd());
                        }
                        crate::core::state::SelectionSource::Wlr(src) => {
                            src.send(mime_type, fd.as_fd());
                        }
                        crate::core::state::SelectionSource::Ext(src) => {
                            src.send(mime_type, fd.as_fd());
                        }
                    }
                }
                drop(fd);
            }
            ext_data_control_offer_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_data_control(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtDataControlManagerV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn source_data_defaults_empty() {
        let d = ExtDataControlSourceData::default();
        assert!(d.mime_types.is_empty());
        assert!(d.client_id.is_none());
    }
}
