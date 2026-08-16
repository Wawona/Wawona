//! Input Method protocol implementation.
//!
//! This module provides:
//! - `zwp_input_panel_v1` (always available). Allows IME to position popup
//!   surfaces near the text cursor.
//! - `zwp_input_method_manager_v2` / `zwp_input_method_v2` (desktop-only,
//!   behind `desktop-protocols` feature). Full IME engine integration for
//!   external engines like IBus and Fcitx.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::input_method::zv1::server::{
    zwp_input_panel_v1::{self, ZwpInputPanelV1},
    zwp_input_panel_surface_v1::{self, ZwpInputPanelSurfaceV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// zwp_input_panel_v1 (always available)
// ============================================================================

#[derive(Debug, Clone, Default)]
pub struct InputPanelSurfaceData {
    pub surface_id: u32,
}

impl GlobalDispatch<ZwpInputPanelV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpInputPanelV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_input_panel_v1");
    }
}

impl Dispatch<ZwpInputPanelV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputPanelV1,
        request: zwp_input_panel_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_panel_v1::Request::GetInputPanelSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _s = data_init.init(id, ());
                tracing::debug!("Created input panel surface for {}", surface_id);
            }
            _ => {}
        }
    }
}

impl Dispatch<ZwpInputPanelSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputPanelSurfaceV1,
        request: zwp_input_panel_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_panel_surface_v1::Request::SetToplevel { .. } => {}
            zwp_input_panel_surface_v1::Request::SetOverlayPanel => {}
            _ => {}
        }
    }
}

pub fn register_input_panel(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpInputPanelV1, ()>(1, ())
}

// ============================================================================
// zwp_input_method_manager_v2 / zwp_input_method_v2  (desktop-only)
// ============================================================================

#[cfg(feature = "desktop-protocols")]
mod input_method_v2 {
    use super::*;
    use crate::core::wayland::protocol::server::zwp_input_method_v2::{
        zwp_input_method_manager_v2::{self, ZwpInputMethodManagerV2},
        zwp_input_method_v2::{self, ZwpInputMethodV2},
        zwp_input_popup_surface_v2::{self, ZwpInputPopupSurfaceV2},
        zwp_input_method_keyboard_grab_v2::{self, ZwpInputMethodKeyboardGrabV2},
    };

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------

    /// Per-seat input method state.
    #[derive(Debug, Default)]
    pub struct InputMethodState {
        /// The currently bound input method resource (one per seat).
        pub resource: Option<ZwpInputMethodV2>,
        /// Whether the input method is currently in the active state
        /// (a text input has focus).
        pub active: bool,
        /// Number of `done` events sent (used for commit serial validation).
        pub done_count: u32,
        /// Pending commit string from the IME (applied on `commit`).
        pub pending_commit: Option<String>,
        /// Pending preedit from the IME.
        pub pending_preedit: Option<(String, i32, i32)>,
        /// Pending delete_surrounding from the IME.
        pub pending_delete: Option<(u32, u32)>,
    }

    impl InputMethodState {
        /// Activate the input method. Called when a text-input is enabled.
        pub fn activate(&mut self) {
            if let Some(ref res) = self.resource {
                if res.is_alive() {
                    res.activate();
                    self.active = true;
                }
            }
        }

        /// Deactivate the input method. Called when text-input is disabled.
        pub fn deactivate(&mut self) {
            if let Some(ref res) = self.resource {
                if res.is_alive() {
                    res.deactivate();
                    self.active = false;
                }
            }
        }

        /// Send surrounding text to the IME.
        pub fn surrounding_text(&self, text: &str, cursor: u32, anchor: u32) {
            if let Some(ref res) = self.resource {
                if res.is_alive() && self.active {
                    res.surrounding_text(text.to_string(), cursor, anchor);
                }
            }
        }

        /// Send content type to the IME.
        pub fn content_type(&self, hint: u32, purpose: u32) {
            use wayland_protocols::wp::text_input::zv3::server::zwp_text_input_v3::{
                ContentHint, ContentPurpose,
            };
            if let Some(ref res) = self.resource {
                if res.is_alive() && self.active {
                    let h = ContentHint::from_bits_truncate(hint);
                    let p = ContentPurpose::try_from(purpose).unwrap_or(ContentPurpose::Normal);
                    res.content_type(h, p);
                }
            }
        }

        /// Send the done event to the IME, applying double-buffered state.
        pub fn done(&mut self) {
            if let Some(ref res) = self.resource {
                if res.is_alive() {
                    res.done();
                    self.done_count = self.done_count.wrapping_add(1);
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // zwp_input_method_manager_v2
    // ------------------------------------------------------------------

    impl GlobalDispatch<ZwpInputMethodManagerV2, ()> for CompositorState {
        fn bind(
            _state: &mut Self,
            _handle: &DisplayHandle,
            _client: &Client,
            resource: New<ZwpInputMethodManagerV2>,
            _global_data: &(),
            data_init: &mut DataInit<'_, Self>,
        ) {
            data_init.init(resource, ());
            tracing::debug!("Bound zwp_input_method_manager_v2");
        }
    }

    impl Dispatch<ZwpInputMethodManagerV2, ()> for CompositorState {
        fn request(
            state: &mut Self,
            _client: &Client,
            _resource: &ZwpInputMethodManagerV2,
            request: zwp_input_method_manager_v2::Request,
            _data: &(),
            _dhandle: &DisplayHandle,
            data_init: &mut DataInit<'_, Self>,
        ) {
            match request {
                zwp_input_method_manager_v2::Request::GetInputMethod { seat, input_method } => {
                    let seat_id = seat.id().protocol_id();
                    let im_res = data_init.init(input_method, seat_id);

                    if state.ext.input_method.resource.is_some() {
                        // Only one input method per seat. Send unavailable.
                        im_res.unavailable();
                        tracing::warn!(
                            "Rejected second input method binding for seat {}",
                            seat_id
                        );
                    } else {
                        state.ext.input_method.resource = Some(im_res);
                        tracing::info!("Input method bound for seat {}", seat_id);
                    }
                }
                zwp_input_method_manager_v2::Request::Destroy => {
                    tracing::debug!("zwp_input_method_manager_v2 destroyed");
                }
                _ => {}
            }
        }
    }

    // ------------------------------------------------------------------
    // zwp_input_method_v2. User data is seat_id: u32
    // ------------------------------------------------------------------

    impl Dispatch<ZwpInputMethodV2, u32> for CompositorState {
        fn request(
            state: &mut Self,
            _client: &Client,
            resource: &ZwpInputMethodV2,
            request: zwp_input_method_v2::Request,
            _seat_id: &u32,
            _dhandle: &DisplayHandle,
            data_init: &mut DataInit<'_, Self>,
        ) {
            match request {
                zwp_input_method_v2::Request::CommitString { text } => {
                    state.ext.input_method.pending_commit = Some(text);
                }
                zwp_input_method_v2::Request::SetPreeditString {
                    text,
                    cursor_begin,
                    cursor_end,
                } => {
                    state.ext.input_method.pending_preedit =
                        Some((text, cursor_begin, cursor_end));
                }
                zwp_input_method_v2::Request::DeleteSurroundingText {
                    before_length,
                    after_length,
                } => {
                    state.ext.input_method.pending_delete =
                        Some((before_length, after_length));
                }
                zwp_input_method_v2::Request::Commit { serial } => {
                    // Validate serial: must match the number of done events sent.
                    if serial != state.ext.input_method.done_count {
                        tracing::warn!(
                            "Input method commit serial mismatch: got {} expected {}",
                            serial,
                            state.ext.input_method.done_count,
                        );
                        // Per spec: proceed normally but don't change state.
                        state.ext.input_method.pending_commit = None;
                        state.ext.input_method.pending_preedit = None;
                        state.ext.input_method.pending_delete = None;
                        return;
                    }

                    // Apply pending state to the text-input client.
                    // Per spec the client evaluates in order:
                    //   1. Replace preedit with cursor
                    //   2. Delete surrounding text
                    //   3. Insert commit string
                    //   4-6. Insert new preedit
                    // We send each event to the text-input; the final `done`
                    // is sent by each text_input method already.
                    let pending_delete = state.ext.input_method.pending_delete.take();
                    let pending_commit = state.ext.input_method.pending_commit.take();
                    let pending_preedit = state.ext.input_method.pending_preedit.take();

                    if let Some((before, after)) = pending_delete {
                        state.ext.text_input.delete_surrounding_text(before, after);
                    }
                    if let Some(text) = pending_commit {
                        state.ext.text_input.commit_string(&text);
                    }
                    if let Some((text, begin, end)) = pending_preedit {
                        state.ext.text_input.preedit_string(&text, begin, end);
                    }
                }
                zwp_input_method_v2::Request::GetInputPopupSurface { id, surface } => {
                    let _popup = data_init.init(id, ());
                    let sid = surface.id().protocol_id();
                    tracing::debug!(
                        "Input method popup surface created for surface {}",
                        sid
                    );
                }
                zwp_input_method_v2::Request::GrabKeyboard { keyboard } => {
                    let _grab = data_init.init(keyboard, ());
                    tracing::debug!("Input method keyboard grab created");
                }
                zwp_input_method_v2::Request::Destroy => {
                    if state
                        .ext
                        .input_method
                        .resource
                        .as_ref()
                        .map_or(false, |r| r.id() == resource.id())
                    {
                        state.ext.input_method.resource = None;
                        state.ext.input_method.active = false;
                    }
                    tracing::debug!("Input method destroyed");
                }
                _ => {}
            }
        }
    }

    // ------------------------------------------------------------------
    // zwp_input_popup_surface_v2 (stub)
    // ------------------------------------------------------------------

    impl Dispatch<ZwpInputPopupSurfaceV2, ()> for CompositorState {
        fn request(
            _state: &mut Self,
            _client: &Client,
            _resource: &ZwpInputPopupSurfaceV2,
            request: zwp_input_popup_surface_v2::Request,
            _data: &(),
            _dhandle: &DisplayHandle,
            _data_init: &mut DataInit<'_, Self>,
        ) {
            match request {
                zwp_input_popup_surface_v2::Request::Destroy => {}
                _ => {}
            }
        }
    }

    // ------------------------------------------------------------------
    // zwp_input_method_keyboard_grab_v2 (stub)
    // ------------------------------------------------------------------

    impl Dispatch<ZwpInputMethodKeyboardGrabV2, ()> for CompositorState {
        fn request(
            _state: &mut Self,
            _client: &Client,
            _resource: &ZwpInputMethodKeyboardGrabV2,
            request: zwp_input_method_keyboard_grab_v2::Request,
            _data: &(),
            _dhandle: &DisplayHandle,
            _data_init: &mut DataInit<'_, Self>,
        ) {
            match request {
                zwp_input_method_keyboard_grab_v2::Request::Release => {}
                _ => {}
            }
        }
    }

    // ------------------------------------------------------------------
    // Registration
    // ------------------------------------------------------------------

    pub fn register_input_method_manager(
        display: &DisplayHandle,
    ) -> wayland_server::backend::GlobalId {
        display
            .create_global::<CompositorState, ZwpInputMethodManagerV2, ()>(1, ())
    }
}

#[cfg(feature = "desktop-protocols")]
pub use input_method_v2::{InputMethodState, register_input_method_manager};
