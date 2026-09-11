//! Idle Notify protocol implementation.
//!
//! This protocol allows clients to be notified when the user becomes idle
//! (no input events for a configurable timeout). When the user resumes
//! activity, a `resumed` event is sent.

use crate::core::wayland::protocol::server::ext::idle_notify::v1::server::{
    ext_idle_notification_v1::{self, ExtIdleNotificationV1},
    ext_idle_notifier_v1::{self, ExtIdleNotifierV1},
};
use std::time::Instant;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Tracks an individual idle notification subscription
#[derive(Debug, Clone)]
pub struct IdleNotification {
    pub resource: ExtIdleNotificationV1,
    pub timeout_ms: u32,
    /// Whether the `idled` event has been sent
    pub is_idle: bool,
}

/// Tracks all idle notification subscriptions and user activity
#[derive(Debug)]
pub struct IdleNotifyState {
    pub notifications: Vec<IdleNotification>,
    /// Time of last user input
    pub last_activity: Instant,
}

impl Default for IdleNotifyState {
    fn default() -> Self {
        Self {
            notifications: Vec::new(),
            last_activity: Instant::now(),
        }
    }
}

impl IdleNotifyState {
    /// Record user activity (call on any input event)
    pub fn record_activity(&mut self) {
        let was_idle = self.notifications.iter().any(|n| n.is_idle);
        self.last_activity = Instant::now();

        // Send resumed to any notifications that were idle
        if was_idle {
            for notif in &mut self.notifications {
                if notif.is_idle && notif.resource.is_alive() {
                    notif.resource.resumed();
                    notif.is_idle = false;
                }
            }
        }
    }

    /// Check for idle timeouts and send `idled` events.
    /// Call this periodically (e.g., once per second from the event loop).
    pub fn check_idle(&mut self) {
        let elapsed = self.last_activity.elapsed();
        let elapsed_ms = elapsed.as_millis() as u32;

        for notif in &mut self.notifications {
            if !notif.is_idle && elapsed_ms >= notif.timeout_ms && notif.resource.is_alive() {
                notif.resource.idled();
                notif.is_idle = true;
                tracing::debug!(
                    "User idle for {}ms (timeout={}ms)",
                    elapsed_ms,
                    notif.timeout_ms
                );
            }
        }
    }

    /// Remove dead resources
    pub fn cleanup(&mut self) {
        self.notifications.retain(|n| n.resource.is_alive());
    }
}

// ============================================================================
// ext_idle_notifier_v1
// ============================================================================

impl GlobalDispatch<ExtIdleNotifierV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtIdleNotifierV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_idle_notifier_v1");
    }
}

impl Dispatch<ExtIdleNotifierV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtIdleNotifierV1,
        request: ext_idle_notifier_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_idle_notifier_v1::Request::GetIdleNotification { id, timeout, seat } => {
                let _seat_id = seat.id().protocol_id();
                let notification_res = data_init.init(id, ());
                state.ext.idle_notify.notifications.push(IdleNotification {
                    resource: notification_res,
                    timeout_ms: timeout,
                    is_idle: false,
                });
                tracing::debug!("Created idle notification: timeout={}ms", timeout);
            }
            ext_idle_notifier_v1::Request::Destroy => {
                tracing::debug!("ext_idle_notifier_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// ext_idle_notification_v1
// ============================================================================

impl Dispatch<ExtIdleNotificationV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtIdleNotificationV1,
        request: ext_idle_notification_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_idle_notification_v1::Request::Destroy => {
                let res_id = resource.id();
                state
                    .ext
                    .idle_notify
                    .notifications
                    .retain(|n| n.resource.id() != res_id);
                tracing::debug!("ext_idle_notification_v1 destroyed");
            }
            _ => {}
        }
    }
}

/// Register ext_idle_notifier_v1 global
pub fn register_idle_notify(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtIdleNotifierV1, ()>(1, ())
}
