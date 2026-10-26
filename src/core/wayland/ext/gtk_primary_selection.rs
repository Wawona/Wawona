//! Implementation of `gtk_primary_selection_device_manager`.
//!
//! Provides GTK primary selection emulation for Wayland clients, allowing
//! middle-click paste and primary selection data transfers.

use std::collections::HashMap;
use std::os::fd::{AsFd, OwnedFd};
use std::sync::Arc;

use wayland_protocols_misc::gtk_primary_selection::server::{
    gtk_primary_selection_device::{self, GtkPrimarySelectionDevice},
    gtk_primary_selection_device_manager::{self, GtkPrimarySelectionDeviceManager},
    gtk_primary_selection_offer::{self, GtkPrimarySelectionOffer},
    gtk_primary_selection_source::{self, GtkPrimarySelectionSource},
};
use wayland_server::backend::protocol::Message;
use wayland_server::backend::{ClientId, Handle, ObjectData, ObjectId};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;

/// State for gtk_primary_selection
#[derive(Debug, Default)]
pub struct GtkPrimarySelectionState {
    /// Active devices
    pub devices: Vec<GtkPrimarySelectionDevice>,
    /// Registered sources and their offered MIME types
    pub source_mimes: HashMap<ObjectId, Vec<String>>,
    /// Active source resource
    pub current_source: Option<GtkPrimarySelectionSource>,
}

#[derive(Debug)]
pub struct GtkOfferUserData {
    pub source: GtkPrimarySelectionSource,
}

impl ObjectData<CompositorState> for GtkOfferUserData {
    fn request(
        self: Arc<Self>,
        handle: &Handle,
        _state: &mut CompositorState,
        _client_id: ClientId,
        msg: Message<ObjectId, OwnedFd>,
    ) -> Option<Arc<dyn ObjectData<CompositorState>>> {
        let dh = DisplayHandle::from(handle.clone());
        if let Ok((_offer, gtk_primary_selection_offer::Request::Receive { mime_type, fd })) =
            GtkPrimarySelectionOffer::parse_request(&dh, msg)
        {
            if self.source.is_alive() {
                self.source.send(mime_type, fd.as_fd());
            }
        }
        None
    }

    fn destroyed(
        self: Arc<Self>,
        _handle: &Handle,
        _state: &mut CompositorState,
        _client_id: ClientId,
        _object_id: ObjectId,
    ) {
    }
}

pub fn register_gtk_primary_selection(dh: &DisplayHandle) {
    dh.create_global::<CompositorState, GtkPrimarySelectionDeviceManager, _>(1, ());
}

// ============================================================================
// GtkPrimarySelectionDeviceManager
// ============================================================================

impl GlobalDispatch<GtkPrimarySelectionDeviceManager, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: wayland_server::New<GtkPrimarySelectionDeviceManager>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<GtkPrimarySelectionDeviceManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        _resource: &GtkPrimarySelectionDeviceManager,
        request: gtk_primary_selection_device_manager::Request,
        _data: &(),
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            gtk_primary_selection_device_manager::Request::CreateSource { id } => {
                let source = data_init.init(id, ());
                state
                    .gtk_primary_selection
                    .source_mimes
                    .insert(source.id(), Vec::new());
            }
            gtk_primary_selection_device_manager::Request::GetDevice { id, seat: _ } => {
                let device = data_init.init(id, ());
                if let Some(src) = &state.gtk_primary_selection.current_source {
                    if src.is_alive() {
                        if let Some(mimes) = state
                            .gtk_primary_selection
                            .source_mimes
                            .get(&src.id())
                            .cloned()
                        {
                            let client_id = client.id();
                            let backend = dhandle.backend_handle();
                            let user_data = Arc::new(GtkOfferUserData {
                                source: src.clone(),
                            });
                            if let Ok(obj_id) = backend.create_object::<Self>(
                                client_id,
                                GtkPrimarySelectionOffer::interface(),
                                device.version(),
                                user_data,
                            ) {
                                if let Ok(offer) =
                                    GtkPrimarySelectionOffer::from_id(dhandle, obj_id)
                                {
                                    device.data_offer(&offer);
                                    for mime in mimes {
                                        offer.offer(mime);
                                    }
                                    device.selection(Some(&offer));
                                }
                            }
                        }
                    }
                }
                state.gtk_primary_selection.devices.push(device);
            }
            gtk_primary_selection_device_manager::Request::Destroy => {}
            _ => {}
        }
    }
}

// ============================================================================
// GtkPrimarySelectionSource
// ============================================================================

impl Dispatch<GtkPrimarySelectionSource, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &GtkPrimarySelectionSource,
        request: gtk_primary_selection_source::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            gtk_primary_selection_source::Request::Offer { mime_type } => {
                if let Some(mimes) = state
                    .gtk_primary_selection
                    .source_mimes
                    .get_mut(&resource.id())
                {
                    mimes.push(mime_type);
                }
            }
            gtk_primary_selection_source::Request::Destroy => {
                if state
                    .gtk_primary_selection
                    .current_source
                    .as_ref()
                    .map(|s| s.id())
                    == Some(resource.id())
                {
                    state.gtk_primary_selection.current_source = None;
                    for dev in &state.gtk_primary_selection.devices {
                        if dev.is_alive() {
                            dev.selection(None);
                        }
                    }
                }
                state
                    .gtk_primary_selection
                    .source_mimes
                    .remove(&resource.id());
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: ClientId,
        resource: &GtkPrimarySelectionSource,
        _data: &(),
    ) {
        if state
            .gtk_primary_selection
            .current_source
            .as_ref()
            .map(|s| s.id())
            == Some(resource.id())
        {
            state.gtk_primary_selection.current_source = None;
            for dev in &state.gtk_primary_selection.devices {
                if dev.is_alive() {
                    dev.selection(None);
                }
            }
        }
        state
            .gtk_primary_selection
            .source_mimes
            .remove(&resource.id());
    }
}

// ============================================================================
// GtkPrimarySelectionDevice
// ============================================================================

impl Dispatch<GtkPrimarySelectionDevice, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &GtkPrimarySelectionDevice,
        request: gtk_primary_selection_device::Request,
        _data: &(),
        dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            gtk_primary_selection_device::Request::SetSelection { source, serial: _ } => {
                let old_source = state.gtk_primary_selection.current_source.take();
                if let Some(ref old) = old_source {
                    if old.is_alive() && source.as_ref().map(|s| s.id()) != Some(old.id()) {
                        old.cancelled();
                    }
                }
                state.gtk_primary_selection.current_source = source.clone();
                state.gtk_primary_selection.devices.retain(|d| d.is_alive());

                match source {
                    Some(src) => {
                        let mimes = state
                            .gtk_primary_selection
                            .source_mimes
                            .get(&src.id())
                            .cloned()
                            .unwrap_or_default();
                        let devices = state.gtk_primary_selection.devices.clone();
                        let backend = dhandle.backend_handle();
                        for dev in devices {
                            if !dev.is_alive() {
                                continue;
                            }
                            let dev_client = match dhandle.get_client(dev.id()) {
                                Ok(c) => c.id(),
                                Err(_) => continue,
                            };
                            let user_data = Arc::new(GtkOfferUserData {
                                source: src.clone(),
                            });
                            if let Ok(obj_id) = backend.create_object::<Self>(
                                dev_client,
                                GtkPrimarySelectionOffer::interface(),
                                dev.version(),
                                user_data,
                            ) {
                                if let Ok(offer) =
                                    GtkPrimarySelectionOffer::from_id(dhandle, obj_id)
                                {
                                    dev.data_offer(&offer);
                                    for mime in &mimes {
                                        offer.offer(mime.clone());
                                    }
                                    dev.selection(Some(&offer));
                                }
                            }
                        }
                    }
                    None => {
                        for dev in &state.gtk_primary_selection.devices {
                            if dev.is_alive() {
                                dev.selection(None);
                            }
                        }
                    }
                }
            }
            gtk_primary_selection_device::Request::Destroy => {
                state
                    .gtk_primary_selection
                    .devices
                    .retain(|d| d.id() != resource.id());
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: ClientId,
        resource: &GtkPrimarySelectionDevice,
        _data: &(),
    ) {
        state
            .gtk_primary_selection
            .devices
            .retain(|d| d.id() != resource.id());
    }
}
