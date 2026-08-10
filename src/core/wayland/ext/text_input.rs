//! WP Text Input protocol implementation (`zwp_text_input_v3`).
//!
//! Double-buffered client state: `enable`/`disable`/`set_content_type`/
//! surrounding/cursor updates land in pending fields and apply on `commit`.
//! Host soft-OSK code must read committed state only.
//!
//! Terminal clients that never speak text-input-v3 are covered by
//! [`terminal_text_entry_active`] synthesis (keyboard-focused allowlisted
//! app_id), ORed into [`text_entry_wanted`].

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::text_input::zv3::server::{
    zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
    zwp_text_input_v3::{self, ZwpTextInputV3},
};
use wayland_protocols::wp::text_input::zv1::server::{
    zwp_text_input_manager_v1::{self, ZwpTextInputManagerV1},
    zwp_text_input_v1::{self, ZwpTextInputV1},
};

use crate::core::state::CompositorState;
use crate::core::wayland::xdg::decoration::is_weston_terminal_app_id;

// ============================================================================
// Content purpose (zwp_text_input_v3.content_purpose)
// ============================================================================

/// `zwp_text_input_v3.content_purpose` values used by host IME mapping.
pub mod content_purpose {
    pub const NORMAL: u32 = 0;
    pub const ALPHA: u32 = 1;
    pub const DIGITS: u32 = 2;
    pub const NUMBER: u32 = 3;
    pub const PHONE: u32 = 4;
    pub const URL: u32 = 5;
    pub const EMAIL: u32 = 6;
    pub const NAME: u32 = 7;
    pub const PASSWORD: u32 = 8;
    pub const PIN: u32 = 9;
    pub const DATE: u32 = 10;
    pub const TIME: u32 = 11;
    pub const DATETIME: u32 = 12;
    pub const TERMINAL: u32 = 13;
}

// ============================================================================
// Data Types
// ============================================================================

/// Content type hint for the text input field
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ContentType {
    pub hint: u32,
    pub purpose: u32,
}

/// Pending (uncommitted) double-buffered client state.
#[derive(Debug, Clone, Default)]
pub struct PendingTextInputState {
    pub enabled: Option<bool>,
    pub surrounding_text: Option<String>,
    pub surrounding_cursor: Option<i32>,
    pub surrounding_anchor: Option<i32>,
    pub content_type: Option<ContentType>,
    pub cursor_rect: Option<(i32, i32, i32, i32)>,
}

/// Per-text-input state tracked by the compositor
#[derive(Debug, Clone)]
pub struct TextInputInstance {
    pub resource: ZwpTextInputV3,
    pub seat_id: u32,
    /// Committed enabled flag (applied on `commit`).
    pub enabled: bool,
    pub surrounding_text: String,
    pub surrounding_cursor: i32,
    pub surrounding_anchor: i32,
    pub content_type: ContentType,
    pub cursor_rect: (i32, i32, i32, i32),
    pub serial: u32,
    pub pending: PendingTextInputState,
}

/// Committed fields that receive pending state on `commit` (testable without a Resource).
#[derive(Debug, Clone, Default)]
struct CommittedTextInputFields {
    enabled: bool,
    surrounding_text: String,
    surrounding_cursor: i32,
    surrounding_anchor: i32,
    content_type: ContentType,
    cursor_rect: (i32, i32, i32, i32),
    serial: u32,
}

impl CommittedTextInputFields {
    /// Apply pending double-buffered state. Returns `(was_enabled, now_enabled)`.
    fn apply_pending(&mut self, pending: &mut PendingTextInputState) -> (bool, bool) {
        let was_enabled = self.enabled;
        if let Some(enabled) = pending.enabled.take() {
            self.enabled = enabled;
            if !enabled {
                self.surrounding_text.clear();
                self.surrounding_cursor = 0;
                self.surrounding_anchor = 0;
            }
        }
        if let Some(text) = pending.surrounding_text.take() {
            self.surrounding_text = text;
        }
        if let Some(cursor) = pending.surrounding_cursor.take() {
            self.surrounding_cursor = cursor;
        }
        if let Some(anchor) = pending.surrounding_anchor.take() {
            self.surrounding_anchor = anchor;
        }
        if let Some(ct) = pending.content_type.take() {
            self.content_type = ct;
        }
        if let Some(rect) = pending.cursor_rect.take() {
            self.cursor_rect = rect;
        }
        self.serial = self.serial.wrapping_add(1);
        (was_enabled, self.enabled)
    }

    fn clear_on_leave(&mut self) {
        self.enabled = false;
        self.surrounding_text.clear();
        self.surrounding_cursor = 0;
        self.surrounding_anchor = 0;
    }
}

impl TextInputInstance {
    fn new(resource: ZwpTextInputV3, seat_id: u32) -> Self {
        Self {
            resource,
            seat_id,
            enabled: false,
            surrounding_text: String::new(),
            surrounding_cursor: 0,
            surrounding_anchor: 0,
            content_type: ContentType::default(),
            cursor_rect: (0, 0, 0, 0),
            serial: 0,
            pending: PendingTextInputState::default(),
        }
    }

    fn apply_commit(&mut self) -> (bool, bool) {
        let mut committed = CommittedTextInputFields {
            enabled: self.enabled,
            surrounding_text: std::mem::take(&mut self.surrounding_text),
            surrounding_cursor: self.surrounding_cursor,
            surrounding_anchor: self.surrounding_anchor,
            content_type: self.content_type.clone(),
            cursor_rect: self.cursor_rect,
            serial: self.serial,
        };
        let result = committed.apply_pending(&mut self.pending);
        self.enabled = committed.enabled;
        self.surrounding_text = committed.surrounding_text;
        self.surrounding_cursor = committed.surrounding_cursor;
        self.surrounding_anchor = committed.surrounding_anchor;
        self.content_type = committed.content_type;
        self.cursor_rect = committed.cursor_rect;
        self.serial = committed.serial;
        result
    }

    fn clear_committed_on_leave(&mut self) {
        let mut committed = CommittedTextInputFields {
            enabled: self.enabled,
            surrounding_text: std::mem::take(&mut self.surrounding_text),
            surrounding_cursor: self.surrounding_cursor,
            surrounding_anchor: self.surrounding_anchor,
            content_type: self.content_type.clone(),
            cursor_rect: self.cursor_rect,
            serial: self.serial,
        };
        committed.clear_on_leave();
        self.enabled = committed.enabled;
        self.surrounding_text = committed.surrounding_text;
        self.surrounding_cursor = committed.surrounding_cursor;
        self.surrounding_anchor = committed.surrounding_anchor;
        self.pending = PendingTextInputState::default();
    }
}

/// Per-`zwp_text_input_v1` state (legacy weston clients: weston-editor).
///
/// v1 is the older unstable protocol weston's own toy-toolkit still speaks. It
/// is not double-buffered like v3: `activate`/`deactivate` are immediate and
/// the compositor echoes the client's `commit_state` serial back on
/// `commit_string`/`preedit_string`.
#[derive(Debug, Clone)]
pub struct TextInputV1Instance {
    pub resource: ZwpTextInputV1,
    /// Set between `activate` and `deactivate`.
    pub active: bool,
    /// Last serial from the client's `commit_state`, echoed on outgoing events.
    pub serial: u32,
    /// Surface passed to the last `activate` (for enter/leave).
    pub surface: Option<wayland_server::protocol::wl_surface::WlSurface>,
}

impl TextInputV1Instance {
    fn new(resource: ZwpTextInputV1) -> Self {
        Self { resource, active: false, serial: 0, surface: None }
    }
}

/// Compositor-wide text input state
#[derive(Debug, Default)]
pub struct TextInputState {
    /// All active text input instances, keyed by resource protocol ID
    pub instances: HashMap<u32, TextInputInstance>,
    /// Currently focused text input (receives enter/leave)
    pub focused: Option<u32>,
    /// Surface that last received text-input enter (keyboard focus surface).
    pub focused_surface_id: Option<u32>,
    /// Legacy v1 text inputs (weston-editor), keyed by resource protocol ID.
    pub v1_instances: HashMap<u32, TextInputV1Instance>,
    /// Currently active v1 text input.
    pub v1_focused: Option<u32>,
}

impl TextInputState {
    /// True when any instance has committed `enabled`.
    pub fn committed_enabled(&self) -> bool {
        self.instances.values().any(|i| i.enabled)
    }

    /// True when any legacy v1 text input is active.
    pub fn v1_active(&self) -> bool {
        self.v1_instances.values().any(|i| i.active)
    }

    /// Active v1 instance, preferring `v1_focused`.
    fn v1_active_instance_mut(&mut self) -> Option<&mut TextInputV1Instance> {
        if let Some(id) = self.v1_focused {
            if self.v1_instances.get(&id).map(|i| i.active).unwrap_or(false) {
                return self.v1_instances.get_mut(&id);
            }
        }
        let fallback = self
            .v1_instances
            .iter()
            .find(|(_, i)| i.active)
            .map(|(id, _)| *id);
        fallback.and_then(move |id| self.v1_instances.get_mut(&id))
    }

    /// First committed-enabled instance, preferring `focused` when set.
    pub fn focused_enabled_instance(&self) -> Option<&TextInputInstance> {
        if let Some(id) = self.focused {
            if let Some(inst) = self.instances.get(&id) {
                if inst.enabled {
                    return Some(inst);
                }
            }
        }
        self.instances.values().find(|i| i.enabled)
    }

    pub fn focused_enabled_instance_mut(&mut self) -> Option<&mut TextInputInstance> {
        let id = if let Some(id) = self.focused {
            if self.instances.get(&id).map(|i| i.enabled).unwrap_or(false) {
                Some(id)
            } else {
                None
            }
        } else {
            None
        };
        if let Some(id) = id {
            return self.instances.get_mut(&id);
        }
        let fallback = self
            .instances
            .iter()
            .find(|(_, i)| i.enabled)
            .map(|(id, _)| *id);
        fallback.and_then(|id| self.instances.get_mut(&id))
    }

    /// Send enter event to all text inputs associated with the focused surface
    pub fn enter(
        &mut self,
        surface: &wayland_server::protocol::wl_surface::WlSurface,
        surface_id: Option<u32>,
    ) {
        self.focused_surface_id = surface_id;
        let mut last_alive: Option<u32> = None;
        for (id, instance) in &self.instances {
            if instance.resource.is_alive() {
                instance.resource.enter(surface);
                last_alive = Some(*id);
            }
        }
        self.focused = last_alive;
    }

    /// Send leave event and clear committed text-entry state.
    pub fn leave(&mut self, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        for (_id, instance) in &mut self.instances {
            if instance.resource.is_alive() {
                instance.resource.leave(surface);
            }
            instance.clear_committed_on_leave();
        }
        self.focused = None;
        self.focused_surface_id = None;
    }

    /// Forward a commit string from platform IME to the focused enabled text input.
    pub fn commit_string(&mut self, text: &str) {
        if let Some(instance) = self.focused_enabled_instance_mut() {
            if instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance.resource.commit_string(Some(text.to_string()));
                instance.resource.done(instance.serial);
            }
        }
        if let Some(v1) = self.v1_active_instance_mut() {
            if v1.resource.is_alive() {
                v1.resource.commit_string(v1.serial, text.to_string());
            }
        }
    }

    /// Forward preedit from platform IME
    pub fn preedit_string(&mut self, text: &str, cursor_begin: i32, cursor_end: i32) {
        if let Some(instance) = self.focused_enabled_instance_mut() {
            if instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance
                    .resource
                    .preedit_string(Some(text.to_string()), cursor_begin, cursor_end);
                instance.resource.done(instance.serial);
            }
        }
        if let Some(v1) = self.v1_active_instance_mut() {
            if v1.resource.is_alive() {
                // v1 preedit_string carries the trailing commit text; weston-editor
                // applies the preedit then the commit on the next commit_state.
                v1.resource
                    .preedit_string(v1.serial, text.to_string(), String::new());
            }
        }
    }

    /// Forward delete_surrounding_text from platform IME
    pub fn delete_surrounding_text(&mut self, before_length: u32, after_length: u32) {
        if let Some(instance) = self.focused_enabled_instance_mut() {
            if instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance
                    .resource
                    .delete_surrounding_text(before_length, after_length);
                instance.resource.done(instance.serial);
            }
        }
        if let Some(v1) = self.v1_active_instance_mut() {
            if v1.resource.is_alive() {
                // v1 uses (index, length) relative to cursor, in bytes.
                v1.resource
                    .delete_surrounding_text(-(before_length as i32), before_length + after_length);
            }
        }
    }
}

/// App-ids that should synthesize soft-OSK text-entry when focused and TI is off.
pub fn is_terminal_text_entry_app_id(app_id: &str) -> bool {
    if app_id.is_empty() {
        return false;
    }
    if is_weston_terminal_app_id(app_id) {
        return true;
    }
    let lower = app_id.to_ascii_lowercase();
    lower == "foot"
        || lower.starts_with("foot.")
        || lower.contains(".foot")
        || lower.contains("org.codeberg.dnkl.foot")
        || lower.contains("weston-terminal")
        || lower.contains("wayland-terminal")
}

/// Title fallback when weston toy-toolkit omits app_id.
pub fn is_terminal_text_entry_title(title: &str) -> bool {
    let lower = title.to_ascii_lowercase();
    lower.contains("wayland terminal")
        || lower.contains("weston-terminal")
        || lower.contains("weston terminal")
        || lower == "foot"
}

/// Whether keyboard-focused surface is an allowlisted terminal (no TI required).
pub fn terminal_text_entry_active(state: &CompositorState) -> bool {
    let Some(sid) = state.seat.keyboard.focus else {
        return false;
    };
    let Some(window) = state.get_window_by_surface(sid) else {
        return false;
    };
    let Ok(window) = window.read() else {
        return false;
    };
    is_terminal_text_entry_app_id(&window.app_id)
        || (window.app_id.is_empty() && is_terminal_text_entry_title(&window.title))
}

/// Soft OSK should expand: committed TI enable OR terminal synthesis.
/// Real TI always wins when present (synthesis is ignored while TI enabled).
pub fn text_entry_wanted(state: &CompositorState) -> bool {
    if state.ext.text_input.committed_enabled() || state.ext.text_input.v1_active() {
        return true;
    }
    terminal_text_entry_active(state)
}

// ============================================================================
// zwp_text_input_manager_v3
// ============================================================================

impl GlobalDispatch<ZwpTextInputManagerV3, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV3>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_text_input_manager_v3");
    }
}

impl Dispatch<ZwpTextInputManagerV3, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_text_input_manager_v3::Request::GetTextInput { id, seat } => {
                let seat_id = seat.id().protocol_id();
                let text_input = data_init.init(id, seat_id);
                let ti_id = text_input.id().protocol_id();

                state
                    .ext
                    .text_input
                    .instances
                    .insert(ti_id, TextInputInstance::new(text_input, seat_id));

                tracing::debug!("Created text input {} for seat {}", ti_id, seat_id);
            }
            zwp_text_input_manager_v3::Request::Destroy => {
                tracing::debug!("zwp_text_input_manager_v3 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_text_input_v3 — user data is seat_id: u32
// ============================================================================

impl Dispatch<ZwpTextInputV3, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        _seat_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ti_id = resource.id().protocol_id();
        match request {
            zwp_text_input_v3::Request::Enable => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.pending.enabled = Some(true);
                    tracing::debug!("Text input {} pending enable", ti_id);
                }
            }
            zwp_text_input_v3::Request::Disable => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.pending.enabled = Some(false);
                    tracing::debug!("Text input {} pending disable", ti_id);
                }
            }
            zwp_text_input_v3::Request::SetSurroundingText { text, cursor, anchor } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.pending.surrounding_text = Some(text);
                    instance.pending.surrounding_cursor = Some(cursor);
                    instance.pending.surrounding_anchor = Some(anchor);
                }
            }
            zwp_text_input_v3::Request::SetTextChangeCause { cause: _ } => {
                // Applies with the next commit; no discrete storage needed.
            }
            zwp_text_input_v3::Request::SetContentType { hint, purpose } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.pending.content_type = Some(ContentType {
                        hint: hint.into(),
                        purpose: purpose.into(),
                    });
                }
            }
            zwp_text_input_v3::Request::SetCursorRectangle { x, y, width, height } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.pending.cursor_rect = Some((x, y, width, height));
                }
            }
            zwp_text_input_v3::Request::Commit => {
                let im_data = state.ext.text_input.instances.get_mut(&ti_id).map(|instance| {
                    let (was, now) = instance.apply_commit();
                    tracing::debug!(
                        "Text input {} commit (serial {}, enabled {} -> {})",
                        ti_id,
                        instance.serial,
                        was,
                        now
                    );
                    (
                        now,
                        instance.surrounding_text.clone(),
                        instance.surrounding_cursor as u32,
                        instance.surrounding_anchor as u32,
                        instance.content_type.hint,
                        instance.content_type.purpose,
                    )
                });
                if im_data.is_some() {
                    state.ext.text_input.focused = Some(ti_id);
                }

                #[cfg(feature = "desktop-protocols")]
                if let Some((enabled, text, cursor, anchor, hint, purpose)) = im_data {
                    if enabled {
                        state.ext.input_method.activate();
                        let im = &mut state.ext.input_method;
                        if im.active {
                            im.surrounding_text(&text, cursor, anchor);
                            im.content_type(hint, purpose);
                            im.done();
                        }
                    } else {
                        state.ext.input_method.deactivate();
                    }
                }
                #[cfg(not(feature = "desktop-protocols"))]
                {
                    let _ = im_data;
                }
            }
            zwp_text_input_v3::Request::Destroy => {
                state.ext.text_input.instances.remove(&ti_id);
                if state.ext.text_input.focused == Some(ti_id) {
                    state.ext.text_input.focused = None;
                }
                tracing::debug!("Text input {} destroyed", ti_id);
            }
            _ => {}
        }
    }
}

/// Register zwp_text_input_manager_v3 global
pub fn register_text_input_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpTextInputManagerV3, ()>(1, ())
}

// ============================================================================
// zwp_text_input_manager_v1 (legacy — weston-editor / weston toy-toolkit)
// ============================================================================
//
// weston's own clients still bind the unstable v1 manager and exit with
// "No text input manager global" when it is absent. Advertise it so those
// clients start, and bridge activate/deactivate + IME output onto the same
// soft-OSK path as v3.

impl GlobalDispatch<ZwpTextInputManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_text_input_manager_v1");
    }
}

impl Dispatch<ZwpTextInputManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpTextInputManagerV1,
        request: zwp_text_input_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_text_input_manager_v1::Request::CreateTextInput { id } => {
                let text_input = data_init.init(id, ());
                let ti_id = text_input.id().protocol_id();
                state
                    .ext
                    .text_input
                    .v1_instances
                    .insert(ti_id, TextInputV1Instance::new(text_input));
                tracing::debug!("Created v1 text input {}", ti_id);
            }
            _ => {}
        }
    }
}

// zwp_text_input_v1 — user data is () (looked up by protocol id).
impl Dispatch<ZwpTextInputV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpTextInputV1,
        request: zwp_text_input_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ti_id = resource.id().protocol_id();
        match request {
            zwp_text_input_v1::Request::Activate { seat: _, surface } => {
                if let Some(inst) = state.ext.text_input.v1_instances.get_mut(&ti_id) {
                    inst.active = true;
                    inst.surface = Some(surface.clone());
                    if inst.resource.is_alive() {
                        inst.resource.enter(&surface);
                    }
                }
                state.ext.text_input.v1_focused = Some(ti_id);
                #[cfg(feature = "desktop-protocols")]
                state.ext.input_method.activate();
                tracing::debug!("v1 text input {} activate", ti_id);
            }
            zwp_text_input_v1::Request::Deactivate { seat: _ } => {
                if let Some(inst) = state.ext.text_input.v1_instances.get_mut(&ti_id) {
                    inst.active = false;
                    if inst.resource.is_alive() {
                        inst.resource.leave();
                    }
                }
                if state.ext.text_input.v1_focused == Some(ti_id) {
                    state.ext.text_input.v1_focused = None;
                }
                #[cfg(feature = "desktop-protocols")]
                if !state.ext.text_input.v1_active() {
                    state.ext.input_method.deactivate();
                }
                tracing::debug!("v1 text input {} deactivate", ti_id);
            }
            zwp_text_input_v1::Request::CommitState { serial } => {
                if let Some(inst) = state.ext.text_input.v1_instances.get_mut(&ti_id) {
                    inst.serial = serial;
                }
            }
            zwp_text_input_v1::Request::Reset => {}
            zwp_text_input_v1::Request::ShowInputPanel => {}
            zwp_text_input_v1::Request::HideInputPanel => {}
            zwp_text_input_v1::Request::SetSurroundingText { .. } => {}
            zwp_text_input_v1::Request::SetContentType { .. } => {}
            zwp_text_input_v1::Request::SetCursorRectangle { .. } => {}
            zwp_text_input_v1::Request::SetPreferredLanguage { .. } => {}
            zwp_text_input_v1::Request::InvokeAction { .. } => {}
            _ => {}
        }
    }
}

/// Register zwp_text_input_manager_v1 global (legacy weston clients).
pub fn register_text_input_manager_v1(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpTextInputManagerV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enable_without_commit_stays_disabled() {
        let mut committed = CommittedTextInputFields::default();
        let mut pending = PendingTextInputState {
            enabled: Some(true),
            ..Default::default()
        };
        assert!(!committed.enabled);
        // Pending alone does not flip committed.
        assert!(pending.enabled.is_some());
        let (_, now) = committed.apply_pending(&mut pending);
        assert!(now);
        assert!(committed.enabled);
        assert!(pending.enabled.is_none());
    }

    #[test]
    fn disable_commit_clears_enabled() {
        let mut committed = CommittedTextInputFields {
            enabled: true,
            surrounding_text: "hi".into(),
            surrounding_cursor: 2,
            surrounding_anchor: 2,
            ..Default::default()
        };
        let mut pending = PendingTextInputState {
            enabled: Some(false),
            ..Default::default()
        };
        let (was, now) = committed.apply_pending(&mut pending);
        assert!(was);
        assert!(!now);
        assert!(committed.surrounding_text.is_empty());
    }

    #[test]
    fn content_type_pending_until_commit() {
        let mut committed = CommittedTextInputFields::default();
        let mut pending = PendingTextInputState {
            enabled: Some(true),
            content_type: Some(ContentType {
                hint: 0,
                purpose: content_purpose::PASSWORD,
            }),
            ..Default::default()
        };
        assert_eq!(committed.content_type.purpose, content_purpose::NORMAL);
        committed.apply_pending(&mut pending);
        assert_eq!(committed.content_type.purpose, content_purpose::PASSWORD);
        assert!(committed.enabled);
    }

    #[test]
    fn terminal_app_id_allowlist() {
        assert!(is_terminal_text_entry_app_id("weston-terminal"));
        assert!(is_terminal_text_entry_app_id("wayland-terminal"));
        assert!(is_terminal_text_entry_app_id("foot"));
        assert!(!is_terminal_text_entry_app_id(""));
        assert!(!is_terminal_text_entry_app_id("fuzzel"));
        assert!(!is_terminal_text_entry_app_id("weston-flower"));
        // Demos must not synthesize soft OSK.
        assert!(!is_terminal_text_entry_app_id("weston-simple-shm"));
        assert!(!is_terminal_text_entry_app_id("org.freedesktop.weston.wayland-simple-shm"));
        assert!(!is_terminal_text_entry_app_id("weston-smoke"));
        assert!(!is_terminal_text_entry_title("simple-shm"));
        assert!(is_terminal_text_entry_title("Wayland Terminal"));
        assert!(!is_terminal_text_entry_title("Flower"));
    }
}
