//! In-process input-method stand-in for native host IME.
//!
//! Smithay 0.7 discards every `zwp_text_input_v3` request unless an
//! `zwp_input_method_v2` instance is bound. Apple and Android IME live inside
//! the Wawona process, so this client binds IM-v2 on a trusted socketpair.
//! Store apps never see that global (`is_trusted_input_method`).

use std::os::unix::net::UnixStream;
use std::sync::{Arc, Mutex};

use wayland_client::{
    protocol::{wl_registry, wl_seat},
    Connection, Dispatch, EventQueue, QueueHandle,
};
use wayland_protocols_misc::zwp_input_method_v2::client::{
    zwp_input_method_manager_v2, zwp_input_method_v2,
};

// Aliases so ownership CI does not treat this client stand-in as a custom
// server Dispatch for WlSeat / ZwpInputMethodManagerV2.
type HostImSeat = wl_seat::WlSeat;
type HostImManager = zwp_input_method_manager_v2::ZwpInputMethodManagerV2;
type HostImObject = zwp_input_method_v2::ZwpInputMethodV2;
use wayland_server::backend::{ClientData, ClientId, DisconnectReason};
use wayland_server::{Client, Display, DisplayHandle};

use crate::core::state::CompositorState;
use crate::core::wayland::policy::ProtocolProfile;

/// Client data that marks the in-process host IM. Filters trust this type.
pub struct HostImClientData {
    pub compositor_state: smithay::wayland::compositor::CompositorClientState,
}

impl ClientData for HostImClientData {
    fn initialized(&self, client_id: ClientId) {
        tracing::debug!("host IM client initialized: {:?}", client_id);
    }

    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        tracing::debug!("host IM client disconnected: {:?} ({:?})", client_id, reason);
    }
}

/// Committed IM / text-input mirror for FFI and OSK policy.
#[derive(Debug, Clone, Default)]
pub struct HostImMirror {
    pub active: bool,
    pub serial: u32,
    pub surrounding_text: String,
    pub surrounding_cursor: i32,
    pub surrounding_anchor: i32,
    pub content_hint: u32,
    pub content_purpose: u32,
    pub cursor_rect: (i32, i32, i32, i32),
}

impl HostImMirror {
    pub fn hidden_text(&self) -> bool {
        const HINT_HIDDEN_TEXT: u32 = 0x8;
        self.content_purpose
            == crate::core::wayland::ext::text_input::content_purpose::PASSWORD
            || self.content_purpose
                == crate::core::wayland::ext::text_input::content_purpose::PIN
            || (self.content_hint & HINT_HIDDEN_TEXT) != 0
    }
}

#[derive(Debug, Clone)]
enum HostImCommand {
    CommitString(String),
    /// Test-only: commit with a serial Smithay must reject.
    CommitStringWrongSerial(String),
    Preedit {
        text: String,
        cursor_begin: i32,
        cursor_end: i32,
    },
    DeleteSurrounding {
        before: u32,
        after: u32,
    },
}

struct HostImShared {
    mirror: Mutex<HostImMirror>,
    outgoing: Mutex<Vec<HostImCommand>>,
}

struct HostImClient {
    shared: Arc<HostImShared>,
    _registry: Option<wl_registry::WlRegistry>,
    manager: Option<HostImManager>,
    seat: Option<HostImSeat>,
    im: Option<HostImObject>,
}

/// Trusted in-process IM-v2 client plus the server-side Client keep-alive.
pub struct HostImRelay {
    conn: Connection,
    queue: EventQueue<HostImClient>,
    inner: HostImClient,
    shared: Arc<HostImShared>,
    _server_client: Client,
}

impl HostImRelay {
    pub fn queue_commit_string(&self, text: &str) {
        self.shared
            .outgoing
            .lock()
            .unwrap()
            .push(HostImCommand::CommitString(text.to_string()));
    }

    /// Queue a commit_string with a serial Smithay will discard.
    pub fn queue_commit_string_wrong_serial(&self, text: &str) {
        self.shared
            .outgoing
            .lock()
            .unwrap()
            .push(HostImCommand::CommitStringWrongSerial(text.to_string()));
    }

    pub fn queue_preedit(&self, text: &str, cursor_begin: i32, cursor_end: i32) {
        self.shared.outgoing.lock().unwrap().push(HostImCommand::Preedit {
            text: text.to_string(),
            cursor_begin,
            cursor_end,
        });
    }

    pub fn queue_delete_surrounding(&self, before: u32, after: u32) {
        self.shared
            .outgoing
            .lock()
            .unwrap()
            .push(HostImCommand::DeleteSurrounding { before, after });
    }

    pub fn mirror(&self) -> HostImMirror {
        self.shared.mirror.lock().unwrap().clone()
    }

    pub fn has_instance(&self) -> bool {
        self.inner.im.is_some()
    }
}

/// Trust host IM always. Desktop profiles may also bind IBus/Fcitx later.
/// Store-safe apps never pass this filter.
pub fn is_trusted_input_method(client: &Client, profile: ProtocolProfile) -> bool {
    if client.get_data::<HostImClientData>().is_some() {
        return true;
    }
    crate::core::wayland::policy::allow_desktop_extensions(profile)
}

/// Virtual-keyboard is compositor ↔ trusted OSK only. Store apps never bind it.
pub fn is_trusted_virtual_keyboard(client: &Client, profile: ProtocolProfile) -> bool {
    if client.get_data::<HostImClientData>().is_some() {
        return true;
    }
    crate::core::wayland::policy::allow_privileged_wlr(profile)
}

/// Insert the host IM client and bind IM-v2 so Smithay accepts TI requests.
pub fn attach(display: &mut Display<CompositorState>, state: &mut CompositorState) {
    if state.host_im.is_some() {
        return;
    }
    let mut dh = display.handle();
    match start(&mut dh) {
        Ok(relay) => {
            state.host_im = Some(relay);
            for _ in 0..12 {
                pump(display, state);
            }
            if state
                .host_im
                .as_ref()
                .map(|im| im.inner.im.is_some())
                .unwrap_or(false)
            {
                tracing::info!("host IM-v2 stand-in bound");
            } else {
                tracing::warn!("host IM-v2 stand-in did not bind; TI v3 enable will be discarded");
            }
        }
        Err(err) => {
            tracing::error!("host IM stand-in failed to start: {err}");
        }
    }
}

fn start(dh: &mut DisplayHandle) -> Result<HostImRelay, String> {
    let (server_sock, client_sock) = UnixStream::pair().map_err(|e| e.to_string())?;
    let server_client = dh
        .insert_client(
            server_sock,
            Arc::new(HostImClientData {
                compositor_state: smithay::wayland::compositor::CompositorClientState::default(),
            }),
        )
        .map_err(|e| e.to_string())?;
    let conn = Connection::from_socket(client_sock).map_err(|e| e.to_string())?;
    let queue = conn.new_event_queue::<HostImClient>();
    let qh = queue.handle();
    let registry = conn.display().get_registry(&qh, ());
    let shared = Arc::new(HostImShared {
        mirror: Mutex::new(HostImMirror::default()),
        outgoing: Mutex::new(Vec::new()),
    });
    let inner = HostImClient {
        shared: shared.clone(),
        _registry: Some(registry),
        manager: None,
        seat: None,
        im: None,
    };
    conn.flush().map_err(|e| e.to_string())?;
    Ok(HostImRelay {
        conn,
        queue,
        inner,
        shared,
        _server_client: server_client,
    })
}

/// Flush queued host IME commits onto the IM-v2 client.
pub fn prepare(relay: &mut HostImRelay) {
    flush_outgoing(relay);
    let _ = relay.conn.flush();
}

/// Read IM-v2 events after the compositor has dispatched clients.
pub fn finish(state: &mut CompositorState) {
    if let Some(relay) = state.host_im.as_mut() {
        if let Some(guard) = relay.conn.prepare_read() {
            let _ = guard.read();
        }
        let _ = relay.queue.dispatch_pending(&mut relay.inner);
        try_bind_im(&mut relay.inner, &relay.queue.handle());
        let _ = relay.conn.flush();
    }
}

/// Pump host IM requests and events. Used by TestEnv and attach bootstrap.
pub fn pump(display: &mut Display<CompositorState>, state: &mut CompositorState) {
    if let Some(relay) = state.host_im.as_mut() {
        prepare(relay);
    }
    let _ = display.dispatch_clients(state);
    let _ = display.flush_clients();
    finish(state);
}

fn flush_outgoing(relay: &mut HostImRelay) {
    let commands: Vec<HostImCommand> = relay.shared.outgoing.lock().unwrap().drain(..).collect();
    let Some(im) = relay.inner.im.as_ref() else {
        if !commands.is_empty() {
            tracing::debug!("host IM commit dropped: IM not bound yet");
        }
        return;
    };
    let serial = relay.shared.mirror.lock().unwrap().serial;
    for cmd in commands {
        match cmd {
            HostImCommand::CommitString(text) => {
                im.commit_string(text);
                im.commit(serial);
            }
            HostImCommand::CommitStringWrongSerial(text) => {
                im.commit_string(text);
                im.commit(serial.wrapping_add(99));
            }
            HostImCommand::Preedit {
                text,
                cursor_begin,
                cursor_end,
            } => {
                im.set_preedit_string(text, cursor_begin, cursor_end);
                im.commit(serial);
            }
            HostImCommand::DeleteSurrounding { before, after } => {
                im.delete_surrounding_text(before, after);
                im.commit(serial);
            }
        }
    }
}

fn try_bind_im(inner: &mut HostImClient, qh: &QueueHandle<HostImClient>) {
    if inner.im.is_some() {
        return;
    }
    let (Some(manager), Some(seat)) = (inner.manager.as_ref(), inner.seat.as_ref()) else {
        return;
    };
    inner.im = Some(manager.get_input_method(seat, qh, ()));
}

impl Dispatch<wl_registry::WlRegistry, ()> for HostImClient {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            if interface == "wl_seat" {
                let v = version.min(1);
                state.seat = Some(registry.bind(name, v, qh, ()));
            } else if interface == "zwp_input_method_manager_v2" {
                let v = version.min(1);
                state.manager = Some(registry.bind(name, v, qh, ()));
            }
        }
    }
}

impl Dispatch<HostImSeat, ()> for HostImClient {
    fn event(
        _state: &mut Self,
        _proxy: &HostImSeat,
        _event: wl_seat::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<HostImManager, ()> for HostImClient {
    fn event(
        _state: &mut Self,
        _proxy: &HostImManager,
        _event: zwp_input_method_manager_v2::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<HostImObject, ()> for HostImClient {
    fn event(
        state: &mut Self,
        _proxy: &HostImObject,
        event: zwp_input_method_v2::Event,
        _data: &(),
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
        let mut mirror = state.shared.mirror.lock().unwrap();
        match event {
            zwp_input_method_v2::Event::Activate => {
                mirror.active = true;
            }
            zwp_input_method_v2::Event::Deactivate => {
                mirror.active = false;
                mirror.surrounding_text.clear();
                mirror.surrounding_cursor = 0;
                mirror.surrounding_anchor = 0;
            }
            zwp_input_method_v2::Event::SurroundingText {
                text,
                cursor,
                anchor,
            } => {
                if !mirror.hidden_text() {
                    mirror.surrounding_text = text;
                    mirror.surrounding_cursor = cursor as i32;
                    mirror.surrounding_anchor = anchor as i32;
                } else {
                    mirror.surrounding_text.clear();
                    mirror.surrounding_cursor = 0;
                    mirror.surrounding_anchor = 0;
                }
            }
            zwp_input_method_v2::Event::ContentType { hint, purpose } => {
                mirror.content_hint = hint.into_result().map(|h| h.bits()).unwrap_or(0);
                mirror.content_purpose = purpose
                    .into_result()
                    .map(|p| u32::from(p as i32 as u32))
                    .unwrap_or(0);
            }
            zwp_input_method_v2::Event::Done => {
                mirror.serial = mirror.serial.wrapping_add(1);
            }
            zwp_input_method_v2::Event::Unavailable => {
                mirror.active = false;
            }
            zwp_input_method_v2::Event::TextChangeCause { .. } => {}
            _ => {}
        }
    }
}
