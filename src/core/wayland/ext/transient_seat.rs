//! Transient Seat protocol implementation.
//!
//! Allows creating temporary input seats for remote desktop scenarios.
//! On Create, a transient seat is made and the `ready` event is sent
//! with the global seat name so the client can bind the wl_seat.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New,
};
use crate::core::wayland::protocol::server::ext::transient_seat::v1::server::{
    ext_transient_seat_manager_v1::{self, ExtTransientSeatManagerV1},
    ext_transient_seat_v1::{self, ExtTransientSeatV1},
};

use crate::core::state::CompositorState;

impl GlobalDispatch<ExtTransientSeatManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtTransientSeatManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_transient_seat_manager_v1");
    }
}

impl Dispatch<ExtTransientSeatManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtTransientSeatManagerV1,
        request: ext_transient_seat_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_transient_seat_manager_v1::Request::Create { seat } => {
                let ts = data_init.init(seat, ());
                // In a single-seat compositor, the transient seat maps to "default"
                // The `ready` event tells the client which global seat name to bind
                ts.ready(0);
                tracing::debug!("Created transient seat. Ready with global_name=0, name=default");
            }
            ext_transient_seat_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtTransientSeatV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtTransientSeatV1,
        request: ext_transient_seat_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_transient_seat_v1::Request::Destroy => {
                tracing::debug!("Transient seat destroyed");
            }
            _ => {}
        }
    }
}

pub fn register_transient_seat(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtTransientSeatManagerV1, ()>(1, ())
}
