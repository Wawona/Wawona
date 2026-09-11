//! Data Control protocol implementation.
//!
//! Allows clipboard managers to access and manage clipboard contents.

use crate::core::wayland::protocol::server::ext::data_control::v1::server::{
    ext_data_control_device_v1::{self, ExtDataControlDeviceV1},
    ext_data_control_manager_v1::{self, ExtDataControlManagerV1},
    ext_data_control_offer_v1::{self, ExtDataControlOfferV1},
    ext_data_control_source_v1::{self, ExtDataControlSourceV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct DataControlDeviceData {
    pub seat_id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct DataControlSourceData;

#[derive(Debug, Clone, Default)]
pub struct DataControlOfferData;

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
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlManagerV1,
        request: ext_data_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_manager_v1::Request::CreateDataSource { id } => {
                let _s: ExtDataControlSourceV1 = data_init.init(id, ());
            }
            ext_data_control_manager_v1::Request::GetDataDevice { id, seat } => {
                let _seat_id = seat.id().protocol_id();
                let _d: ExtDataControlDeviceV1 = data_init.init(id, ());
            }
            ext_data_control_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlDeviceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlDeviceV1,
        request: ext_data_control_device_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_device_v1::Request::SetSelection { .. } => {}
            ext_data_control_device_v1::Request::SetPrimarySelection { .. } => {}
            ext_data_control_device_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlSourceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlSourceV1,
        request: ext_data_control_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_source_v1::Request::Offer { .. } => {}
            ext_data_control_source_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlOfferV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtDataControlOfferV1,
        request: ext_data_control_offer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_data_control_offer_v1::Request::Receive { .. } => {}
            ext_data_control_offer_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_data_control(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtDataControlManagerV1, ()>(1, ())
}
