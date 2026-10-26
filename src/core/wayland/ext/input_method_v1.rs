//! Input method v1 (`zwp_input_method_v1` / `zwp_input_method_context_v1`).
//!
//! Smithay 0.7 has no implementation of the input method v1 protocol, so the
//! global is served by Wawona. An input method client binds
//! `zwp_input_method_v1`; the compositor then hands it a
//! `zwp_input_method_context_v1` when a text input of the
//! [`crate::core::wayland::ext::text_input_v2`] family becomes active.
//!
//! The context is the bridge between the two halves of the protocol:
//!
//! - text input to input method: surrounding text, content type and the
//!   preferred language travel to the context as events.
//! - input method to text input: committed text, preedit, cursor moves,
//!   deletions, key symbols, the modifier map and the text direction travel
//!   to the text input as events.
//!
//! Text input v3 and input method v2 are owned by Smithay and are not touched
//! here.

use std::os::fd::OwnedFd;
use std::sync::Arc;

use wayland_protocols::wp::input_method::zv1::server::{
    zwp_input_method_context_v1::{self, ZwpInputMethodContextV1},
    zwp_input_method_v1::{self, ZwpInputMethodV1},
};
use wayland_server::backend::protocol::Message;
use wayland_server::backend::{ClientId, Handle, ObjectData, ObjectId};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use crate::core::wayland::ext::text_input_v2::TextInputV2Instance;

// ============================================================================
// Data Types
// ============================================================================

/// User data of a server side `zwp_input_method_context_v1`.
///
/// The context belongs to one text input object, so the requests it carries
/// are forwarded to that text input.
#[derive(Debug, Clone)]
pub struct InputMethodContextV1Data {
    /// The text input object this context drives.
    pub text_input: TextInputV2Instance,
}

impl ObjectData<CompositorState> for InputMethodContextV1Data {
    fn request(
        self: Arc<Self>,
        handle: &Handle,
        state: &mut CompositorState,
        _client_id: ClientId,
        msg: Message<ObjectId, OwnedFd>,
    ) -> Option<Arc<dyn ObjectData<CompositorState>>> {
        let dh = DisplayHandle::from(handle.clone());
        if let Ok((_context, req)) = ZwpInputMethodContextV1::parse_request(&dh, msg) {
            let text_input = &self.text_input;
            if text_input.resource.is_alive() {
                match req {
                    zwp_input_method_context_v1::Request::CommitString { serial: _, text } => {
                        text_input.resource.commit_string(text);
                    }
                    zwp_input_method_context_v1::Request::PreeditString {
                        serial: _,
                        text,
                        commit,
                    } => {
                        text_input.resource.preedit_string(text, commit);
                    }
                    zwp_input_method_context_v1::Request::PreeditStyling {
                        index,
                        length,
                        style,
                    } => {
                        use wayland_protocols_plasma::text_input::v2::server::zwp_text_input_v2::PreeditStyle;
                        let st = match style {
                            0 => PreeditStyle::Default,
                            1 => PreeditStyle::None,
                            2 => PreeditStyle::Active,
                            3 => PreeditStyle::Inactive,
                            4 => PreeditStyle::Highlight,
                            5 => PreeditStyle::Underline,
                            6 => PreeditStyle::Selection,
                            7 => PreeditStyle::Incorrect,
                            _ => PreeditStyle::Default,
                        };
                        text_input.resource.preedit_styling(index, length, st);
                    }
                    zwp_input_method_context_v1::Request::PreeditCursor { index } => {
                        text_input.resource.preedit_cursor(index);
                    }
                    zwp_input_method_context_v1::Request::DeleteSurroundingText {
                        index,
                        length,
                    } => {
                        let (before, after) = split_surrounding_deletion(index, length);
                        text_input.resource.cursor_position(index, 0);
                        text_input.resource.delete_surrounding_text(before, after);
                    }
                    zwp_input_method_context_v1::Request::CursorPosition { index, anchor } => {
                        text_input.resource.cursor_position(index, anchor);
                    }
                    zwp_input_method_context_v1::Request::ModifiersMap { map } => {
                        text_input.resource.modifiers_map(map);
                    }
                    zwp_input_method_context_v1::Request::Keysym {
                        serial: _,
                        time,
                        sym,
                        state: kstate,
                        modifiers,
                    } => {
                        text_input.resource.keysym(time, sym, kstate, modifiers);
                    }
                    zwp_input_method_context_v1::Request::Language {
                        serial: _,
                        language,
                    } => {
                        text_input.resource.language(language);
                    }
                    zwp_input_method_context_v1::Request::TextDirection {
                        serial: _,
                        direction,
                    } => {
                        let dir = match direction {
                            1 => wayland_protocols_plasma::text_input::v2::server::zwp_text_input_v2::TextDirection::Ltr,
                            2 => wayland_protocols_plasma::text_input::v2::server::zwp_text_input_v2::TextDirection::Rtl,
                            _ => wayland_protocols_plasma::text_input::v2::server::zwp_text_input_v2::TextDirection::Auto,
                        };
                        text_input.resource.text_direction(dir);
                    }
                    zwp_input_method_context_v1::Request::GrabKeyboard { .. } => {}
                    zwp_input_method_context_v1::Request::Key { .. } => {}
                    zwp_input_method_context_v1::Request::Modifiers { .. } => {}
                    zwp_input_method_context_v1::Request::Destroy => {
                        state.ext.input_method_v1.context = None;
                        state.ext.input_method_v1.active_text_input = None;
                    }
                    _ => {}
                }
            }
        }
        None
    }

    fn destroyed(
        self: Arc<Self>,
        _handle: &Handle,
        state: &mut CompositorState,
        _client_id: ClientId,
        _object_id: ObjectId,
    ) {
        state.ext.input_method_v1.context = None;
        state.ext.input_method_v1.active_text_input = None;
    }
}

/// Compositor-wide input method v1 state.
#[derive(Debug, Default)]
pub struct InputMethodV1State {
    /// The input method object of the client that owns the seat.
    pub input_method: Option<ZwpInputMethodV1>,
    /// Client that owns the input method object.
    pub client: Option<ClientId>,
    /// Context handed to the input method, if one was activated.
    pub context: Option<ZwpInputMethodContextV1>,
    /// Text input object the active context drives.
    pub active_text_input: Option<ObjectId>,
}

// ============================================================================
// zwp_input_method_v1
// ============================================================================

impl GlobalDispatch<ZwpInputMethodV1, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        handle: &DisplayHandle,
        client: &Client,
        resource: New<ZwpInputMethodV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let input_method = data_init.init(resource, ());
        tracing::debug!("Bound zwp_input_method_v1");
        state.ext.input_method_v1.input_method = Some(input_method);
        state.ext.input_method_v1.client = Some(client.id());
        let enabled_client = state
            .ext
            .text_input_v2
            .clients
            .iter()
            .find_map(|(cid, instances)| {
                if instances.iter().any(|inst| inst.enabled) {
                    Some(cid.clone())
                } else {
                    None
                }
            });
        if let Some(ref cid) = enabled_client {
            activate_text_input(state, handle, cid);
        }
    }
}

impl Dispatch<ZwpInputMethodV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputMethodV1,
        _request: zwp_input_method_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }

    fn destroyed(state: &mut Self, _client: ClientId, resource: &ZwpInputMethodV1, _data: &()) {
        if state
            .ext
            .input_method_v1
            .input_method
            .as_ref()
            .is_some_and(|im| im.id() == resource.id())
        {
            state.ext.input_method_v1.input_method = None;
            state.ext.input_method_v1.client = None;
            state.ext.input_method_v1.context = None;
            state.ext.input_method_v1.active_text_input = None;
        }
    }
}

impl Dispatch<ZwpInputMethodContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputMethodContextV1,
        _request: zwp_input_method_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
    }
}

/// Split a surrounding text deletion into the before and after lengths of the
/// text input v2 event.
pub fn split_surrounding_deletion(index: i32, length: u32) -> (u32, u32) {
    let before = index
        .checked_neg()
        .map(|before| u32::try_from(before).unwrap_or(0))
        .unwrap_or(0)
        .min(length);
    (before, length - before)
}

// ============================================================================
// Text input bridge
// ============================================================================

/// Activate the input method for the enabled text input of `client`.
pub fn activate_text_input(state: &mut CompositorState, handle: &DisplayHandle, client: &ClientId) {
    let Some(input_method) = state.ext.input_method_v1.input_method.clone() else {
        return;
    };
    if !input_method.is_alive() {
        return;
    }
    let Some(text_input) = enabled_text_input(state, client) else {
        return;
    };
    let owner_client = match handle.get_client(input_method.id()) {
        Ok(c) => c.id(),
        Err(_) => return,
    };
    let backend = handle.backend_handle();
    let user_data = Arc::new(InputMethodContextV1Data {
        text_input: text_input.clone(),
    });
    let obj_id = match backend.create_object::<CompositorState>(
        owner_client,
        ZwpInputMethodContextV1::interface(),
        input_method.version(),
        user_data,
    ) {
        Ok(id) => id,
        Err(e) => {
            tracing::warn!("could not create input method v1 context: {:?}", e);
            return;
        }
    };
    let context = match ZwpInputMethodContextV1::from_id(handle, obj_id) {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!("could not wrap input method v1 context: {:?}", e);
            return;
        }
    };
    state.ext.input_method_v1.context = Some(context.clone());
    state.ext.input_method_v1.active_text_input = Some(text_input.resource.id());
    input_method.activate(&context);
}

/// Deactivate the input method session of `client`.
pub fn deactivate_text_input(state: &mut CompositorState, client: &ClientId) {
    let Some(context) = state.ext.input_method_v1.context.clone() else {
        return;
    };
    let Some(input_method) = state.ext.input_method_v1.input_method.clone() else {
        return;
    };
    if !input_method.is_alive() || !context.is_alive() {
        return;
    }
    let active_id = state.ext.input_method_v1.active_text_input.clone();
    let active =
        active_id.is_some_and(|id| state.ext.text_input_v2.instance_of(client, &id).is_some());
    if !active {
        return;
    }
    input_method.deactivate(&context);
    state.ext.input_method_v1.context = None;
    state.ext.input_method_v1.active_text_input = None;
}

/// Forward the announced text input state to the input method context.
pub fn commit_text_input_state(state: &mut CompositorState, client: &ClientId) {
    let Some(context) = state.ext.input_method_v1.context.clone() else {
        return;
    };
    if !context.is_alive() {
        return;
    }
    let Some(text_input) = enabled_text_input(state, client) else {
        return;
    };
    if let Some((text, cursor, anchor)) = &text_input.surrounding_text {
        context.surrounding_text(text.clone(), *cursor, *anchor);
    }
    if let Some((hint, purpose)) = text_input.content_type {
        context.content_type(hint, purpose);
    }
    if let Some(language) = &text_input.preferred_language {
        context.preferred_language(language.clone());
    }
    context.commit_state(text_input.serial);
}

/// The enabled text input object of `client`, if any.
fn enabled_text_input(state: &CompositorState, client: &ClientId) -> Option<TextInputV2Instance> {
    state
        .ext
        .text_input_v2
        .instances_of(client)
        .iter()
        .find(|instance| instance.enabled)
        .cloned()
}

// ============================================================================
// Registration
// ============================================================================

/// Register the `zwp_input_method_v1` global.
pub fn register_input_method_v1(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpInputMethodV1, ()>(1, ())
}

// ============================================================================
// Tests
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deletion_behind_the_cursor_is_all_after() {
        assert_eq!(split_surrounding_deletion(1, 2), (0, 2));
    }

    #[test]
    fn deletion_in_front_of_the_cursor_is_all_before() {
        assert_eq!(split_surrounding_deletion(-1, 1), (1, 0));
        assert_eq!(split_surrounding_deletion(-2, 3), (2, 1));
    }

    #[test]
    fn deletion_cannot_delete_more_before_than_the_length() {
        assert_eq!(split_surrounding_deletion(-5, 2), (2, 0));
    }

    #[test]
    fn deletion_at_the_cursor_keeps_the_length() {
        assert_eq!(split_surrounding_deletion(0, 3), (0, 3));
    }
}
