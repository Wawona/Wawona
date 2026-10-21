//! Clipboard and primary selections set by clients without keyboard focus.
//!
//! Smithay only accepts `set_selection` from the keyboard-focused client.
//! Wawona also accepts it from unfocused clients: the selection becomes
//! compositor-owned (offered with the source's MIME types) and every data
//! request is forwarded to the client's source. Focused clients keep
//! Smithay's native path.

use std::os::fd::{AsFd, OwnedFd};

use smithay::reexports::wayland_protocols::wp::primary_selection::zv1::server::{
    zwp_primary_selection_device_v1::{self, ZwpPrimarySelectionDeviceV1},
    zwp_primary_selection_source_v1::{self, ZwpPrimarySelectionSourceV1},
};
use smithay::reexports::wayland_server::{
    backend::ClientId,
    protocol::{
        wl_data_device::{self, WlDataDevice},
        wl_data_source::{self, WlDataSource},
    },
    Client, DataInit, Dispatch, DisplayHandle, Resource,
};
use smithay::wayland::selection::data_device::{
    clear_data_device_selection, current_data_device_selection_userdata, set_data_device_selection,
    with_source_metadata, DataDeviceState, DataDeviceUserData, DataSourceUserData,
};
use smithay::wayland::selection::primary_selection::{
    clear_primary_selection, current_primary_selection_userdata, set_primary_selection,
    PrimaryDeviceUserData, PrimarySelectionState, PrimarySourceUserData,
};
use smithay::wayland::selection::SelectionTarget;

use crate::core::state::CompositorState;

/// Owner of a compositor-owned selection (Smithay `SelectionUserData`).
#[derive(Debug, Clone, Default)]
pub enum SelectionOwner {
    /// Native pasteboard text pushed by the host.
    #[default]
    Host,
    /// Clipboard set by an unfocused client; data comes from its source.
    ClientData(WlDataSource),
    /// Primary selection set by an unfocused client.
    ClientPrimary(ZwpPrimarySelectionSourceV1),
}

impl SelectionOwner {
    /// Forward a data request to the owning client's source. Returns
    /// `false` for [`SelectionOwner::Host`], which the caller serves.
    pub fn forward_request(&self, mime_type: String, fd: &OwnedFd) -> bool {
        match self {
            Self::Host => false,
            Self::ClientData(source) => {
                if source.is_alive() {
                    source.send(mime_type, fd.as_fd());
                }
                true
            }
            Self::ClientPrimary(source) => {
                if source.is_alive() {
                    source.send(mime_type, fd.as_fd());
                }
                true
            }
        }
    }

    fn cancel(&self) {
        match self {
            Self::Host => {}
            Self::ClientData(source) => {
                if source.is_alive() {
                    source.cancelled();
                }
            }
            Self::ClientPrimary(source) => {
                if source.is_alive() {
                    source.cancelled();
                }
            }
        }
    }
}

impl CompositorState {
    fn client_has_keyboard_focus(&self, object: &impl Resource) -> bool {
        self.smithay_runtime
            .seat
            .as_ref()
            .and_then(|seat| seat.get_keyboard())
            .is_some_and(|keyboard| keyboard.client_of_object_has_focus(&object.id()))
    }

    /// Send `cancelled` to an unfocused client's source that currently owns
    /// the `target` selection. Call before the selection is replaced.
    pub fn cancel_proxied_selection(&self, target: SelectionTarget) {
        let Some(seat) = self.smithay_runtime.seat.as_ref() else {
            return;
        };
        let owner = match target {
            SelectionTarget::Clipboard => {
                current_data_device_selection_userdata(seat).map(|o| o.clone())
            }
            SelectionTarget::Primary => current_primary_selection_userdata(seat).map(|o| o.clone()),
        };
        if let Some(owner) = owner {
            owner.cancel();
        }
    }

    fn proxy_clipboard_selection(&mut self, dh: &DisplayHandle, source: Option<WlDataSource>) {
        let Some(seat) = self.smithay_runtime.seat.clone() else {
            return;
        };
        self.cancel_proxied_selection(SelectionTarget::Clipboard);
        match source {
            Some(source) => {
                let mime_types = with_source_metadata(&source, |meta| meta.mime_types.clone())
                    .unwrap_or_default();
                set_data_device_selection(
                    dh,
                    &seat,
                    mime_types,
                    SelectionOwner::ClientData(source),
                );
            }
            None => clear_data_device_selection(dh, &seat),
        }
    }

    fn proxy_primary_selection(
        &mut self,
        dh: &DisplayHandle,
        source: Option<ZwpPrimarySelectionSourceV1>,
    ) {
        let Some(seat) = self.smithay_runtime.seat.clone() else {
            return;
        };
        self.cancel_proxied_selection(SelectionTarget::Primary);
        match source {
            Some(source) => {
                let mime_types = self
                    .primary_source_mime_types
                    .get(&source.id())
                    .cloned()
                    .unwrap_or_default();
                set_primary_selection(dh, &seat, mime_types, SelectionOwner::ClientPrimary(source));
            }
            None => clear_primary_selection(dh, &seat),
        }
    }

    fn proxied_source_destroyed(
        &self,
        dh: &DisplayHandle,
        target: SelectionTarget,
        id: &impl Resource,
    ) {
        let Some(seat) = self.smithay_runtime.seat.as_ref() else {
            return;
        };
        let owned = match target {
            SelectionTarget::Clipboard => current_data_device_selection_userdata(seat)
                .is_some_and(|o| matches!(&*o, SelectionOwner::ClientData(s) if s.id() == id.id())),
            SelectionTarget::Primary => current_primary_selection_userdata(seat).is_some_and(
                |o| matches!(&*o, SelectionOwner::ClientPrimary(s) if s.id() == id.id()),
            ),
        };
        if owned {
            match target {
                SelectionTarget::Clipboard => clear_data_device_selection(dh, seat),
                SelectionTarget::Primary => clear_primary_selection(dh, seat),
            }
        }
    }
}

impl Dispatch<WlDataDevice, DataDeviceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &WlDataDevice,
        request: wl_data_device::Request,
        data: &DataDeviceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let wl_data_device::Request::SetSelection { source, .. } = &request {
            if !state.client_has_keyboard_focus(resource) {
                state.proxy_clipboard_selection(dhandle, source.clone());
                return;
            }
        }
        <DataDeviceState as Dispatch<WlDataDevice, DataDeviceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &WlDataDevice,
        data: &DataDeviceUserData,
    ) {
        <DataDeviceState as Dispatch<WlDataDevice, DataDeviceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<WlDataSource, DataSourceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &WlDataSource,
        request: wl_data_source::Request,
        data: &DataSourceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let destroying = matches!(request, wl_data_source::Request::Destroy);
        <DataDeviceState as Dispatch<WlDataSource, DataSourceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
        if destroying {
            state.proxied_source_destroyed(dhandle, SelectionTarget::Clipboard, resource);
        }
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &WlDataSource,
        data: &DataSourceUserData,
    ) {
        <DataDeviceState as Dispatch<WlDataSource, DataSourceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

impl Dispatch<ZwpPrimarySelectionDeviceV1, PrimaryDeviceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwpPrimarySelectionDeviceV1,
        request: zwp_primary_selection_device_v1::Request,
        data: &PrimaryDeviceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let zwp_primary_selection_device_v1::Request::SetSelection { source, .. } = &request {
            if !state.client_has_keyboard_focus(resource) {
                state.proxy_primary_selection(dhandle, source.clone());
                return;
            }
        }
        <PrimarySelectionState as Dispatch<
            ZwpPrimarySelectionDeviceV1,
            PrimaryDeviceUserData,
            Self,
        >>::request(state, client, resource, request, data, dhandle, data_init);
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &ZwpPrimarySelectionDeviceV1,
        data: &PrimaryDeviceUserData,
    ) {
        <PrimarySelectionState as Dispatch<
            ZwpPrimarySelectionDeviceV1,
            PrimaryDeviceUserData,
            Self,
        >>::destroyed(state, client, resource, data);
    }
}

impl Dispatch<ZwpPrimarySelectionSourceV1, PrimarySourceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwpPrimarySelectionSourceV1,
        request: zwp_primary_selection_source_v1::Request,
        data: &PrimarySourceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let destroying = match &request {
            zwp_primary_selection_source_v1::Request::Offer { mime_type } => {
                state
                    .primary_source_mime_types
                    .entry(resource.id())
                    .or_default()
                    .push(mime_type.clone());
                false
            }
            zwp_primary_selection_source_v1::Request::Destroy => true,
            _ => false,
        };
        <PrimarySelectionState as Dispatch<
            ZwpPrimarySelectionSourceV1,
            PrimarySourceUserData,
            Self,
        >>::request(state, client, resource, request, data, dhandle, data_init);
        if destroying {
            state.proxied_source_destroyed(dhandle, SelectionTarget::Primary, resource);
        }
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &ZwpPrimarySelectionSourceV1,
        data: &PrimarySourceUserData,
    ) {
        state.primary_source_mime_types.remove(&resource.id());
        <PrimarySelectionState as Dispatch<
            ZwpPrimarySelectionSourceV1,
            PrimarySourceUserData,
            Self,
        >>::destroyed(state, client, resource, data);
    }
}
