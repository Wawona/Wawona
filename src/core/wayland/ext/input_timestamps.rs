//! Input Timestamps protocol implementation.
//!
//! Provides high-resolution timestamps for input events.
//! The `timestamp` event is sent before each input event to provide
//! nanosecond-precision timing. The `tv_sec_hi` and `tv_sec_lo` fields
//! represent seconds, and `tv_nsec` represents nanoseconds.

use wayland_protocols::wp::input_timestamps::zv1::server::{
    zwp_input_timestamps_manager_v1::{self, ZwpInputTimestampsManagerV1},
    zwp_input_timestamps_v1::{self, ZwpInputTimestampsV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// Types of input device for which timestamps are tracked
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputTimestampKind {
    Keyboard,
    Pointer,
    Touch,
}

/// Tracks active input timestamp subscriptions
#[derive(Debug, Default)]
pub struct InputTimestampsState {
    /// All active timestamp resources with their kind
    pub resources: Vec<(ZwpInputTimestampsV1, InputTimestampKind)>,
}

impl InputTimestampsState {
    /// Broadcast a high-resolution timestamp to all subscribers of the given kind.
    /// Call this before sending the corresponding input event.
    pub fn broadcast_timestamp(&self, kind: InputTimestampKind, time_ns: u64) {
        let secs = time_ns / 1_000_000_000;
        let nsec = (time_ns % 1_000_000_000) as u32;
        let tv_sec_hi = (secs >> 32) as u32;
        let tv_sec_lo = secs as u32;

        for (res, res_kind) in &self.resources {
            if *res_kind == kind && res.is_alive() {
                res.timestamp(tv_sec_hi, tv_sec_lo, nsec);
            }
        }
    }

    /// Remove dead resources
    pub fn cleanup(&mut self) {
        self.resources.retain(|(res, _)| res.is_alive());
    }
}

impl GlobalDispatch<ZwpInputTimestampsManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpInputTimestampsManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_input_timestamps_manager_v1");
    }
}

impl Dispatch<ZwpInputTimestampsManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpInputTimestampsManagerV1,
        request: zwp_input_timestamps_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_timestamps_manager_v1::Request::GetKeyboardTimestamps { id, keyboard: _ } => {
                let ts = data_init.init(id, ());
                state
                    .ext
                    .input_timestamps
                    .resources
                    .push((ts, InputTimestampKind::Keyboard));
                tracing::debug!("Created keyboard timestamps subscription");
            }
            zwp_input_timestamps_manager_v1::Request::GetPointerTimestamps { id, pointer: _ } => {
                let ts = data_init.init(id, ());
                state
                    .ext
                    .input_timestamps
                    .resources
                    .push((ts, InputTimestampKind::Pointer));
                tracing::debug!("Created pointer timestamps subscription");
            }
            zwp_input_timestamps_manager_v1::Request::GetTouchTimestamps { id, touch: _ } => {
                let ts = data_init.init(id, ());
                state
                    .ext
                    .input_timestamps
                    .resources
                    .push((ts, InputTimestampKind::Touch));
                tracing::debug!("Created touch timestamps subscription");
            }
            zwp_input_timestamps_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZwpInputTimestampsV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpInputTimestampsV1,
        request: zwp_input_timestamps_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_input_timestamps_v1::Request::Destroy => {
                let res_id = resource.id();
                state
                    .ext
                    .input_timestamps
                    .resources
                    .retain(|(r, _)| r.id() != res_id);
                tracing::debug!("Input timestamps subscription destroyed");
            }
            _ => {}
        }
    }
}

pub fn register_input_timestamps(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpInputTimestampsManagerV1, ()>(1, ())
}
