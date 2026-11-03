//! `zwlr_input_inhibit_manager_v1` — exclusive input grab for lock screens.
//!
//! Deprecated upstream in favor of `ext-session-lock-v1`, but still required by
//! older locker clients. At most one inhibitor may be active compositor-wide.
//!
//! Runtime gate: caller requires `policy::allow_desktop_extensions(protocol_profile)`.

use wayland_protocols_wlr::input_inhibitor::v1::server::{
    zwlr_input_inhibit_manager_v1::{self, ZwlrInputInhibitManagerV1},
    zwlr_input_inhibitor_v1::{self, ZwlrInputInhibitorV1},
};
use wayland_server::{
    backend::ClientId, Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;

/// Runtime state for the input inhibitor global.
#[derive(Debug, Default)]
pub struct InputInhibitState {
    /// Client that currently holds the exclusive inhibitor, if any.
    pub active_client: Option<ClientId>,
}

impl GlobalDispatch<ZwlrInputInhibitManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwlrInputInhibitManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZwlrInputInhibitManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwlrInputInhibitManagerV1,
        request: zwlr_input_inhibit_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwlr_input_inhibit_manager_v1::Request::GetInhibitor { id } => {
                if state.wlr.input_inhibit.active_client.is_some() {
                    resource.post_error(
                        zwlr_input_inhibit_manager_v1::Error::AlreadyInhibited,
                        "an input inhibitor is already active",
                    );
                    return;
                }
                data_init.init(id, ());
                state.wlr.input_inhibit.active_client = Some(client.id());
                // Drop focus from every other client so only the inhibitor
                // owner continues to receive pointer/keyboard events.
                let serial = state.next_serial();
                state.leave_global_pointer_focus(serial);
                state.set_keyboard_focus_surface(None);
                tracing::info!("zwlr_input_inhibitor_v1 active for {:?}", client.id());
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwlrInputInhibitorV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        _resource: &ZwlrInputInhibitorV1,
        request: zwlr_input_inhibitor_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwlr_input_inhibitor_v1::Request::Destroy => {
                if state.wlr.input_inhibit.active_client.as_ref() == Some(&client.id()) {
                    state.wlr.input_inhibit.active_client = None;
                    tracing::info!("zwlr_input_inhibitor_v1 released");
                }
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        _resource: &ZwlrInputInhibitorV1,
        _data: &(),
    ) {
        if state.wlr.input_inhibit.active_client.as_ref() == Some(&client) {
            state.wlr.input_inhibit.active_client = None;
        }
    }
}

impl CompositorState {
    /// True when an input inhibitor blocks delivery to `client`.
    pub fn input_inhibited_for(&self, client: &Client) -> bool {
        match &self.wlr.input_inhibit.active_client {
            Some(owner) => owner != &client.id(),
            None => false,
        }
    }
}

pub fn register_input_inhibitor(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwlrInputInhibitManagerV1, ()>(1, ())
}
