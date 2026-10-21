//! Text input v2 (`zwp_text_input_manager_v2` / `zwp_text_input_v2`).
//!
//! Smithay 0.7 has no implementation of the plasma text input v2 protocol, so
//! the global is served by Wawona. The protocol is the client half of the
//! text input / input method pair: the application owns a
//! `zwp_text_input_v2` per seat, the compositor owns a `zwp_input_method_v1`
//! that an input method client binds, and the two are bridged through an
//! input method context.
//!
//! Enter and leave follow the seat's keyboard focus, exactly like text input
//! v3 does, and are delivered to every text input object of the focused
//! client. Enable and disable control whether the text input takes part in
//! the input method session.
//!
//! The bridge to `zwp_input_method_v1` lives in
//! [`crate::core::wayland::ext::input_method_v1`].

use std::collections::HashMap;

use wayland_protocols_plasma::text_input::v2::server::{
    zwp_text_input_manager_v2::{self, ZwpTextInputManagerV2},
    zwp_text_input_v2::{self, ZwpTextInputV2},
};
use wayland_server::backend::{ClientId, ObjectId};
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Client state of one `zwp_text_input_v2` object.
#[derive(Debug, Clone)]
pub struct TextInputV2Instance {
    /// The protocol object.
    pub resource: ZwpTextInputV2,
    /// Client that created the object.
    pub client: ClientId,
    /// Surface the client enabled text input on.
    pub surface: Option<WlSurface>,
    /// Whether the client called `enable`.
    pub enabled: bool,
    /// Serial of the last `enter` or `leave` event sent to this object.
    pub serial: u32,
    /// Surrounding text the client announced, forwarded to the input method.
    pub surrounding_text: Option<(String, u32, u32)>,
    /// Content hint and purpose the client announced.
    pub content_type: Option<(u32, u32)>,
    /// Preferred language the client announced.
    pub preferred_language: Option<String>,
}

impl TextInputV2Instance {
    fn new(resource: ZwpTextInputV2, client: ClientId) -> Self {
        Self {
            resource,
            client,
            surface: None,
            enabled: false,
            serial: 0,
            surrounding_text: None,
            content_type: None,
            preferred_language: None,
        }
    }
}

/// Compositor-wide text input v2 state.
///
/// Text input objects are grouped per client, because enter and leave are
/// delivered to every text input object of the client that owns the focused
/// surface.
#[derive(Debug, Default)]
pub struct TextInputV2State {
    /// Text input objects of every client, keyed by client id.
    pub clients: HashMap<ClientId, Vec<TextInputV2Instance>>,
}

impl TextInputV2State {
    /// All text input objects of `client`.
    pub fn instances_of(&self, client: &ClientId) -> &[TextInputV2Instance] {
        self.clients
            .get(client)
            .map(|instances| instances.as_slice())
            .unwrap_or(&[])
    }

    /// The text input object of `client` with the given object id.
    pub fn instance_of(&self, client: &ClientId, id: &ObjectId) -> Option<&TextInputV2Instance> {
        self.clients
            .get(client)?
            .iter()
            .find(|instance| instance.resource.id() == *id)
    }

    /// The text input object of `client` with the given object id.
    pub fn instance_mut(
        &mut self,
        client: &ClientId,
        id: &ObjectId,
    ) -> Option<&mut TextInputV2Instance> {
        self.clients
            .get_mut(client)?
            .iter_mut()
            .find(|instance| instance.resource.id() == *id)
    }
}

// ============================================================================
// zwp_text_input_manager_v2 (factory)
// ============================================================================

impl GlobalDispatch<ZwpTextInputManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_text_input_manager_v2");
    }
}

impl Dispatch<ZwpTextInputManagerV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        _resource: &ZwpTextInputManagerV2,
        request: zwp_text_input_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_text_input_manager_v2::Request::GetTextInput { id, seat: _ } => {
                let text_input = data_init.init(id, ());
                let instance = TextInputV2Instance::new(text_input, client.id());
                tracing::debug!("Created v2 text input for client {:?}", instance.client);
                state
                    .ext
                    .text_input_v2
                    .clients
                    .entry(instance.client.clone())
                    .or_default()
                    .push(instance);
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_text_input_v2
// ============================================================================

impl Dispatch<ZwpTextInputV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpTextInputV2,
        request: zwp_text_input_v2::Request,
        _data: &(),
        dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let Some(client_id) = resource.client().map(|client| client.id()) else {
            return;
        };
        let id = resource.id();
        match request {
            zwp_text_input_v2::Request::Enable { surface } => {
                let serial = state.next_serial();
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.enabled = true;
                instance.surface = Some(surface.clone());
                instance.serial = serial;
                tracing::debug!(
                    "v2 text input enabled on surface {}",
                    surface.id().protocol_id()
                );
                crate::core::wayland::ext::input_method_v1::activate_text_input(
                    state,
                    dhandle,
                    &client_id,
                );
            }
            zwp_text_input_v2::Request::Disable { .. } => {
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.enabled = false;
                instance.surface = None;
                instance.surrounding_text = None;
                instance.content_type = None;
                instance.preferred_language = None;
                tracing::debug!("v2 text input disabled");
                crate::core::wayland::ext::input_method_v1::deactivate_text_input(state, &client_id);
            }
            zwp_text_input_v2::Request::SetSurroundingText { text, cursor, anchor } => {
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.surrounding_text = Some((
                    text,
                    u32::try_from(cursor).unwrap_or(0),
                    u32::try_from(anchor).unwrap_or(0),
                ));
            }
            zwp_text_input_v2::Request::SetContentType { hint, purpose } => {
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.content_type = Some((hint.into(), purpose.into()));
            }
            zwp_text_input_v2::Request::SetPreferredLanguage { language } => {
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.preferred_language = Some(language);
            }
            zwp_text_input_v2::Request::SetCursorRectangle { .. } => {}
            zwp_text_input_v2::Request::UpdateState { serial, reason } => {
                let Some(instance) = state.ext.text_input_v2.instance_mut(&client_id, &id) else {
                    return;
                };
                instance.serial = serial;
                tracing::debug!("v2 text input update_state serial={} reason={:?}", serial, reason);
                crate::core::wayland::ext::input_method_v1::commit_text_input_state(
                    state,
                    &client_id,
                );
            }
            _ => {}
        }
    }
}

// ============================================================================
// Focus tracking
// ============================================================================

/// Notify the v2 text inputs that the seat focus moved.
///
/// The focus move is reported as leave on the old focus and enter on the new
/// one, in that order, and only to the text input objects of the client that
/// owns the surface.
pub fn notify_focus_changed(
    state: &mut CompositorState,
    old_surface: Option<u32>,
    new_surface: Option<u32>,
) {
    if old_surface == new_surface {
        return;
    }
    let old_client = old_surface.and_then(|sid| surface_client(state, sid));
    let new_client = new_surface.and_then(|sid| surface_client(state, sid));

    if let Some(client) = old_client {
        leave_client(state, &client, old_surface);
    }
    if let Some(client) = new_client {
        enter_client(state, &client, new_surface);
    }
}

/// Client that owns the internal surface `surface_id`.
fn surface_client(state: &CompositorState, surface_id: u32) -> Option<ClientId> {
    let surface = state.surfaces.get(&surface_id)?;
    let resource = surface.read().ok()?.resource.clone()?;
    resource.client().map(|client| client.id())
}

/// Surface resource of the internal surface `surface_id`.
fn surface_resource(state: &CompositorState, surface_id: u32) -> Option<WlSurface> {
    let surface = state.surfaces.get(&surface_id)?;
    surface.read().ok()?.resource.clone()
}

/// Send `leave` to every text input object of `client`.
fn leave_client(state: &mut CompositorState, client: &ClientId, surface_id: Option<u32>) {
    let Some(surface) = surface_id.and_then(|sid| surface_resource(state, sid)) else {
        return;
    };
    let serial = state.next_serial();
    let Some(instances) = state.ext.text_input_v2.clients.get_mut(client) else {
        return;
    };
    for instance in instances.iter_mut() {
        if !instance.resource.is_alive() {
            continue;
        }
        instance.serial = serial;
        instance.resource.leave(serial, &surface);
    }
    tracing::debug!(
        "v2 text input leave on surface {}",
        surface.id().protocol_id()
    );
}

/// Send `enter` to every text input object of `client`.
fn enter_client(state: &mut CompositorState, client: &ClientId, surface_id: Option<u32>) {
    let Some(surface) = surface_id.and_then(|sid| surface_resource(state, sid)) else {
        return;
    };
    let serial = state.next_serial();
    let Some(instances) = state.ext.text_input_v2.clients.get_mut(client) else {
        return;
    };
    for instance in instances.iter_mut() {
        if !instance.resource.is_alive() {
            continue;
        }
        instance.serial = serial;
        instance.resource.enter(serial, &surface);
    }
    tracing::debug!(
        "v2 text input enter on surface {}",
        surface.id().protocol_id()
    );
}

// ============================================================================
// Registration
// ============================================================================

/// Register the `zwp_text_input_manager_v2` global.
pub fn register_text_input_manager_v2(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpTextInputManagerV2, ()>(1, ())
}

// ============================================================================
// Tests
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_starts_empty() {
        let state = TextInputV2State::default();
        assert!(state.clients.is_empty());
    }
}

