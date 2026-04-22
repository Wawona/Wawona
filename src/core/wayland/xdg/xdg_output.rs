//! XDG Output protocol implementation.
//!
//! This protocol provides additional output information beyond wl_output,
//! including logical position and size (accounting for scaling and transforms).


use wayland_protocols::xdg::xdg_output::zv1::server::{
    zxdg_output_v1::ZxdgOutputV1,
};
use wayland_server::Resource;


use crate::core::state::{CompositorState, OutputState};
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct XdgOutputData {
    pub output_id: u32,
}

impl XdgOutputData {
    pub fn new(output_id: u32) -> Self {
        Self { output_id }
    }
}

/// Tracks all bound xdg_output resources for update notifications.
#[derive(Debug, Default)]
pub struct XdgOutputState {
    pub outputs: HashMap<(wayland_server::backend::ClientId, u32), XdgOutputData>,
    /// All active xdg_output resources, keyed by client and xdg_output protocol ID.
    /// Used to send updates when output configuration changes.
    pub resources: HashMap<(wayland_server::backend::ClientId, u32), ZxdgOutputV1>,
}



/// Notify all xdg_output resources about output configuration changes.
/// Called when output geometry, mode, or scale changes.
pub fn notify_xdg_output_change(state: &CompositorState) {
    for ((cid, xdg_output_id), xdg_output) in &state.xdg.output.resources {
        if !xdg_output.is_alive() {
            continue;
        }
        let Some(data) = state.xdg.output.outputs.get(&(cid.clone(), *xdg_output_id)) else {
            continue;
        };
        let Some(output_state) = state.outputs.iter().find(|o| o.id == data.output_id) else {
            continue;
        };
        let lw = output_state.width as i32;
        let lh = output_state.height as i32;

        xdg_output.logical_position(output_state.x, output_state.y);
        xdg_output.logical_size(lw, lh);
        if xdg_output.version() >= 2 {
            xdg_output.name(output_state.name.clone());
            xdg_output.description(format!(
                "{} ({}x{} @ {}Hz)",
                output_state.name,
                output_state.width,
                output_state.height,
                output_state.refresh / 1000
            ));
        }

        if xdg_output.version() >= 3 {
            xdg_output.done();
        }
    }

    if !state.xdg.output.resources.is_empty() {
        tracing::debug!(
            "Notified {} xdg_output resources of output changes",
            state.xdg.output.resources.len()
        );
    }
}

/// Notify only a single client's xdg_output resources of a change.
pub fn notify_xdg_output_change_for_client(
    state: &CompositorState,
    client_id: &wayland_server::backend::ClientId,
) {
    for ((cid, xdg_output_id), xdg_output) in &state.xdg.output.resources {
        if cid != client_id || !xdg_output.is_alive() {
            continue;
        }
        let Some(data) = state.xdg.output.outputs.get(&(cid.clone(), *xdg_output_id)) else {
            continue;
        };
        let Some(output_state) = state.outputs.iter().find(|o| o.id == data.output_id) else {
            continue;
        };
        let lw = output_state.width as i32;
        let lh = output_state.height as i32;

        xdg_output.logical_position(output_state.x, output_state.y);
        xdg_output.logical_size(lw, lh);
        if xdg_output.version() >= 2 {
            xdg_output.name(output_state.name.clone());
            xdg_output.description(format!(
                "{} ({}x{} @ {}Hz)",
                output_state.name,
                output_state.width,
                output_state.height,
                output_state.refresh / 1000
            ));
        }
        if xdg_output.version() >= 3 {
            xdg_output.done();
        }
    }
}

/// Send logical size / position from a synthetic [`crate::core::state::OutputState`] view
/// (e.g. per-window override) to one client's `zxdg_output_v1` resources for that output.
pub fn notify_xdg_output_change_for_client_override(
    state: &CompositorState,
    client_id: &wayland_server::backend::ClientId,
    output_view: &OutputState,
) {
    for ((cid, xdg_output_id), xdg_output) in &state.xdg.output.resources {
        if cid != client_id || !xdg_output.is_alive() {
            continue;
        }
        let Some(data) = state.xdg.output.outputs.get(&(cid.clone(), *xdg_output_id)) else {
            continue;
        };
        if data.output_id != output_view.id {
            continue;
        }

        let lw = output_view.width as i32;
        let lh = output_view.height as i32;

        xdg_output.logical_position(output_view.x, output_view.y);
        xdg_output.logical_size(lw, lh);
        if xdg_output.version() >= 2 {
            xdg_output.name(output_view.name.clone());
            xdg_output.description(format!(
                "{} ({}x{} @ {}Hz)",
                output_view.name,
                output_view.width,
                output_view.height,
                output_view.refresh / 1000
            ));
        }
        if xdg_output.version() >= 3 {
            xdg_output.done();
        }
    }
}

