//! External `zwp_input_method_v2` clients (IBus, Fcitx, test harnesses)
//! multiplexed through the in-process host IM stand-in.
//!
//! Smithay 0.7 keeps the first input method on the seat: a later
//! `get_input_method` sends `unavailable` to the existing instance and never
//! installs the new one. The host stand-in binds at startup, so without this
//! relay no external IM could ever be activated.
//!
//! The host stand-in stays Smithay's only instance. The first external IM
//! becomes the seat owner: host IM events are mirrored to it, and its
//! requests replay through Smithay's own handler on the host resource, with
//! `commit` serials translated between the two `done` counters. Later
//! external IMs get `unavailable`, as the protocol requires.

use smithay::reexports::wayland_protocols_misc::zwp_input_method_v2::server::{
    zwp_input_method_manager_v2::{self, ZwpInputMethodManagerV2},
    zwp_input_method_v2::{self, ZwpInputMethodV2},
};
use smithay::wayland::input_method::{InputMethodManagerState, InputMethodUserData};
use smithay::wayland::text_input::{TextInputManagerState, TextInputSeat, TextInputUserData};
use wayland_protocols::wp::text_input::zv3::server::zwp_text_input_v3::{
    self, ChangeCause, ContentHint, ContentPurpose, ZwpTextInputV3,
};
use wayland_server::backend::ClientId;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, Resource};

use crate::core::state::CompositorState;
use crate::core::wayland::host_im::{HostImClientData, HostImMirror};

/// User data of an external client's `zwp_input_method_v2`.
#[derive(Debug, Default)]
pub struct ExternalImData;

/// The external IM that currently owns the seat.
#[derive(Debug)]
pub struct ExternalImLink {
    resource: ZwpInputMethodV2,
    /// Host `done` count when the link was made.
    host_base: u32,
    /// `done` events sent at attach that the host never saw.
    synthesized: u32,
    /// Host `done` events mirrored since attach.
    forwarded: u32,
}

impl ExternalImLink {
    pub fn resource(&self) -> &ZwpInputMethodV2 {
        &self.resource
    }

    /// Host serial an external `commit(serial)` stands for. A serial the
    /// external client could not have seen maps to a stale host serial so
    /// Smithay discards the commit.
    pub fn host_serial(&self, external_serial: u32) -> u32 {
        translate_commit_serial(
            self.host_base,
            self.synthesized,
            self.forwarded,
            external_serial,
        )
    }
}

/// Map an external `commit(serial)` onto the host instance's serial.
///
/// The external client has seen `synthesized + forwarded` `done` events; the
/// host has seen `host_base + forwarded`. Only the current external serial
/// maps to the current host serial; any other value maps to one Smithay
/// rejects (`done(0)` to the text input).
pub fn translate_commit_serial(
    host_base: u32,
    synthesized: u32,
    forwarded: u32,
    external_serial: u32,
) -> u32 {
    let host_current = host_base.wrapping_add(forwarded);
    if external_serial == synthesized.wrapping_add(forwarded) {
        host_current
    } else {
        host_current.wrapping_add(1)
    }
}

/// Host IM event to mirror onto the external owner.
#[derive(Debug, Clone)]
pub enum HostImEvent {
    Activate,
    Deactivate,
    SurroundingText {
        text: String,
        cursor: u32,
        anchor: u32,
    },
    TextChangeCause(u32),
    ContentType {
        hint: u32,
        purpose: u32,
    },
    Done,
}

/// Mirror one host IM event onto the external owner, if any.
pub fn forward_host_event(link: &mut Option<ExternalImLink>, event: HostImEvent) {
    let Some(current) = link.as_mut() else {
        return;
    };
    if !current.resource.is_alive() {
        *link = None;
        return;
    }
    send_event(&current.resource, event.clone());
    if matches!(event, HostImEvent::Done) {
        current.forwarded = current.forwarded.wrapping_add(1);
    }
}

fn send_event(resource: &ZwpInputMethodV2, event: HostImEvent) {
    match event {
        HostImEvent::Activate => resource.activate(),
        HostImEvent::Deactivate => resource.deactivate(),
        HostImEvent::SurroundingText {
            text,
            cursor,
            anchor,
        } => resource.surrounding_text(text, cursor, anchor),
        HostImEvent::TextChangeCause(cause) => {
            if let Ok(cause) = ChangeCause::try_from(cause) {
                resource.text_change_cause(cause);
            }
        }
        HostImEvent::ContentType { hint, purpose } => {
            let purpose = ContentPurpose::try_from(purpose).unwrap_or(ContentPurpose::Normal);
            resource.content_type(ContentHint::from_bits_truncate(hint), purpose);
        }
        HostImEvent::Done => resource.done(),
    }
}

/// Bring a newly attached owner up to the host's committed state.
fn synthesize_state(resource: &ZwpInputMethodV2, mirror: &HostImMirror) -> u32 {
    if !mirror.active {
        return 0;
    }
    send_event(resource, HostImEvent::Activate);
    if !mirror.surrounding_text.is_empty() {
        send_event(
            resource,
            HostImEvent::SurroundingText {
                text: mirror.surrounding_text.clone(),
                cursor: u32::try_from(mirror.surrounding_cursor).unwrap_or(0),
                anchor: u32::try_from(mirror.surrounding_anchor).unwrap_or(0),
            },
        );
    }
    send_event(
        resource,
        HostImEvent::TextChangeCause(mirror.text_change_cause),
    );
    send_event(
        resource,
        HostImEvent::ContentType {
            hint: mirror.content_hint,
            purpose: mirror.content_purpose,
        },
    );
    send_event(resource, HostImEvent::Done);
    1
}

impl CompositorState {
    /// Server-side `zwp_input_method_v2` of the host stand-in.
    fn host_input_method(&self, dh: &DisplayHandle) -> Option<ZwpInputMethodV2> {
        self.host_im.as_ref()?.server_input_method(dh)
    }

    /// Whether an external IM currently owns the seat.
    pub fn external_input_method_attached(&self) -> bool {
        self.host_im
            .as_ref()
            .map(|im| im.with_external(|link| link.is_some()))
            .unwrap_or(false)
    }

    fn attach_external_input_method(&self, resource: &ZwpInputMethodV2) -> bool {
        let Some(host) = self.host_im.as_ref() else {
            return false;
        };
        let mirror = host.mirror();
        host.with_external(|link| {
            if link.as_ref().is_some_and(|l| l.resource.is_alive()) {
                return false;
            }
            let synthesized = synthesize_state(resource, &mirror);
            *link = Some(ExternalImLink {
                resource: resource.clone(),
                host_base: mirror.serial,
                synthesized,
                forwarded: 0,
            });
            true
        })
    }

    fn detach_external_input_method(&self, resource_id: &wayland_server::backend::ObjectId) {
        if let Some(host) = self.host_im.as_ref() {
            host.with_external(|link| {
                if link
                    .as_ref()
                    .is_some_and(|l| l.resource.id() == *resource_id)
                {
                    *link = None;
                }
            });
        }
    }

    fn is_external_owner(&self, resource: &ZwpInputMethodV2) -> bool {
        self.host_im
            .as_ref()
            .map(|im| {
                im.with_external(|link| link.as_ref().is_some_and(|l| l.resource == *resource))
            })
            .unwrap_or(false)
    }

    fn external_owner_serial(&self, resource: &ZwpInputMethodV2, serial: u32) -> Option<u32> {
        self.host_im.as_ref()?.with_external(|link| {
            link.as_ref()
                .filter(|l| l.resource == *resource)
                .map(|l| l.host_serial(serial))
        })
    }
}

impl Dispatch<ZwpInputMethodManagerV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwpInputMethodManagerV2,
        request: zwp_input_method_manager_v2::Request,
        data: &(),
        dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let relayed = client.get_data::<HostImClientData>().is_none()
            && state.host_input_method(dh).is_some();
        let request = match request {
            zwp_input_method_manager_v2::Request::GetInputMethod { input_method, .. }
                if relayed =>
            {
                let im = data_init.init(input_method, ExternalImData);
                if !state.attach_external_input_method(&im) {
                    im.unavailable();
                }
                return;
            }
            other => other,
        };
        <InputMethodManagerState as Dispatch<ZwpInputMethodManagerV2, (), Self>>::request(
            state, client, resource, request, data, dh, data_init,
        );
    }
}

impl Dispatch<ZwpInputMethodV2, ExternalImData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwpInputMethodV2,
        request: zwp_input_method_v2::Request,
        _data: &ExternalImData,
        dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let zwp_input_method_v2::Request::Destroy = request {
            state.detach_external_input_method(&resource.id());
            return;
        }
        if !state.is_external_owner(resource) {
            // Told `unavailable`: requests are inert, but new objects must
            // still be initialized.
            match request {
                zwp_input_method_v2::Request::GetInputPopupSurface { id, .. } => {
                    data_init.post_error(id, 0u32, "input method is unavailable");
                }
                zwp_input_method_v2::Request::GrabKeyboard { keyboard } => {
                    data_init.post_error(keyboard, 0u32, "input method is unavailable");
                }
                _ => {}
            }
            return;
        }
        let request = match request {
            zwp_input_method_v2::Request::Commit { serial } => {
                let Some(serial) = state.external_owner_serial(resource, serial) else {
                    return;
                };
                zwp_input_method_v2::Request::Commit { serial }
            }
            other => other,
        };
        let Some(host) = state.host_input_method(dh) else {
            return;
        };
        let Some(host_data) = host.data::<InputMethodUserData<Self>>() else {
            return;
        };
        <InputMethodManagerState as Dispatch<
            ZwpInputMethodV2,
            InputMethodUserData<Self>,
            Self,
        >>::request(state, client, &host, request, host_data, dh, data_init);
    }

    fn destroyed(
        state: &mut Self,
        _client: ClientId,
        resource: &ZwpInputMethodV2,
        _data: &ExternalImData,
    ) {
        state.detach_external_input_method(&resource.id());
    }
}

impl CompositorState {
    fn is_active_text_input(&self, resource: &ZwpTextInputV3) -> bool {
        let Some(seat) = self.smithay_runtime.seat.as_ref() else {
            return false;
        };
        let mut active = false;
        seat.text_input()
            .with_active_text_input(|text_input, _| active = text_input == resource);
        active
    }
}

impl Dispatch<ZwpTextInputV3, TextInputUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        data: &TextInputUserData,
        dh: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        // Smithay deactivates the IM on text-input destruction only when the
        // client has no text input left, and never clears the active one: a
        // destroyed enabled text input would keep the IM active and block
        // every other text input from enabling. Disable it first.
        if matches!(request, zwp_text_input_v3::Request::Destroy)
            && state.is_active_text_input(resource)
        {
            for synthetic in [
                zwp_text_input_v3::Request::Disable,
                zwp_text_input_v3::Request::Commit,
            ] {
                <TextInputManagerState as Dispatch<ZwpTextInputV3, TextInputUserData, Self>>::request(
                    state, client, resource, synthetic, data, dh, data_init,
                );
            }
        }
        <TextInputManagerState as Dispatch<ZwpTextInputV3, TextInputUserData, Self>>::request(
            state, client, resource, request, data, dh, data_init,
        );
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &ZwpTextInputV3,
        data: &TextInputUserData,
    ) {
        <TextInputManagerState as Dispatch<ZwpTextInputV3, TextInputUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::translate_commit_serial;

    #[test]
    fn current_external_serial_maps_to_current_host_serial() {
        assert_eq!(translate_commit_serial(5, 1, 0, 1), 5);
        assert_eq!(translate_commit_serial(5, 1, 2, 3), 7);
        assert_eq!(translate_commit_serial(0, 0, 4, 4), 4);
    }

    #[test]
    fn stale_external_serial_maps_to_non_current_host_serial() {
        assert_ne!(translate_commit_serial(5, 1, 2, 2), 7);
        assert_ne!(translate_commit_serial(5, 1, 2, 0), 7);
        assert_ne!(translate_commit_serial(u32::MAX, 0, 1, 0), 0);
    }
}
