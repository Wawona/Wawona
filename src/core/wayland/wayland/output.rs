//! wl_output protocol implementation.
//!
//! Outputs represent physical displays connected to the system.
//! Clients use this to understand display geometry, mode, scale, etc.

use wayland_server::{
    protocol::wl_output::{self, WlOutput, Subpixel, Transform},
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};

use crate::core::state::{CompositorState, OutputState};

/// Output global data - references an output by ID
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OutputGlobal {
    pub output_id: u32,
}

impl OutputGlobal {
    pub fn new(output_id: u32) -> Self {
        Self { output_id }
    }
}

// ============================================================================
// Helpers
// ============================================================================

/// Send all output information to a newly bound output resource.
fn send_output_info(output: &WlOutput, state: &OutputState) {
    crate::wlog!(crate::util::logging::COMPOSITOR, "Sending wl_output.geometry: {}x{} @ ({},{})", state.physical_width, state.physical_height, state.x, state.y);
    // Send geometry
    output.geometry(
        state.x,
        state.y,
        state.physical_width as i32,
        state.physical_height as i32,
        Subpixel::Unknown,
        state.name.clone(),
        state.name.clone(), // model
        Transform::Normal,
    );
    
    // wl_output.mode reports physical pixel dimensions.
    // OutputState.width/height are logical (points/dp), so multiply by scale.
    let phys_w = (state.width as f32 * state.scale) as i32;
    let phys_h = (state.height as f32 * state.scale) as i32;
    crate::wlog!(crate::util::logging::COMPOSITOR, "Sending wl_output.mode: {}x{} (Current | Preferred)", phys_w, phys_h);
    output.mode(
        wl_output::Mode::Current | wl_output::Mode::Preferred,
        phys_w,
        phys_h,
        state.refresh as i32,
    );
    
    // Send scale (version 2+)
    if output.version() >= 2 {
        output.scale(state.scale as i32);
    }
    
    // Send name (version 4+)
    if output.version() >= 4 {
        output.name(state.name.clone());
        output.description(format!("{} ({}x{})", state.name, state.width, state.height));
    }
    
    // Send done event to signal end of initial configuration
    if output.version() >= 2 {
        output.done();
    }
    
    crate::wlog!(crate::util::logging::COMPOSITOR,
        "Sent output info: {} {}x{} logical ({}x{} physical px, {}x{}mm) @ {}mHz, scale {}, version {}",
        state.name, state.width, state.height, phys_w, phys_h, state.physical_width, state.physical_height, state.refresh, state.scale, output.version()
    );
}

/// Notify all bound output resources of a configuration change.
///
/// Call this when output configuration changes (resolution, scale, position, etc.)
/// to send updated geometry, mode, scale, and done events to all clients.
pub fn notify_output_change(state: &CompositorState, output_id: u32) {
    let output_state = match state.outputs.iter().find(|o| o.id == output_id) {
        Some(o) => o,
        None => {
            tracing::warn!("notify_output_change: output {} not found", output_id);
            return;
        }
    };

    let mut notified = 0;
    for (_obj_id, output_res) in &state.output_resources {
        if !output_res.is_alive() {
            continue;
        }
        send_output_info(output_res, output_state);
        notified += 1;
    }

    tracing::debug!(
        "Notified {} bound wl_output resources of output {} change ({}x{})",
        notified, output_id, output_state.width, output_state.height
    );

    // Also notify xdg_output resources
    crate::core::wayland::xdg::xdg_output::notify_xdg_output_change(state);
}

/// Notify only a single client's bound output resources of a configuration change.
///
/// Used when a per-window resize should only inform the owning client about
/// the output mode change, not all connected clients.
pub fn notify_output_change_for_client(
    state: &CompositorState,
    output_id: u32,
    client_id: &wayland_server::backend::ClientId,
) {
    let output_state = match state.outputs.iter().find(|o| o.id == output_id) {
        Some(o) => o,
        None => {
            tracing::warn!("notify_output_change_for_client: output {} not found", output_id);
            return;
        }
    };

    let mut notified = 0;
    for (_obj_id, output_res) in &state.output_resources {
        if !output_res.is_alive() {
            continue;
        }
        if let Some(client) = output_res.client() {
            if client.id() == *client_id {
                send_output_info(output_res, output_state);
                notified += 1;
            }
        }
    }

    tracing::debug!(
        "Notified {} output resources for client {:?} of output {} change ({}x{})",
        notified, client_id, output_id, output_state.width, output_state.height
    );

    crate::core::wayland::xdg::xdg_output::notify_xdg_output_change_for_client(state, client_id);
}

/// Build an [`OutputState`] view with overridden logical size and scale for protocol
/// emission, matching [`CompositorState::set_output_size`] mm / mode semantics.
///
/// Does **not** mutate compositor state — used so one client can receive a
/// per-window `wl_output.mode` without rewriting the global primary output
/// (which would desync every other session).
fn output_state_view_for_dimensions(
    base: &OutputState,
    width: u32,
    height: u32,
    scale: f32,
) -> OutputState {
    let mut view = base.clone();
    let safe_scale = if scale < 1.0 { 1.0 } else { scale };
    let safe_width = if width == 0 { 1920 } else { width };
    let safe_height = if height == 0 { 1080 } else { height };

    view.width = safe_width;
    view.height = safe_height;
    view.scale = safe_scale;
    view.physical_width = ((safe_width as f32 / safe_scale) / 96.0 * 25.4) as u32;
    view.physical_height = ((safe_height as f32 / safe_scale) / 96.0 * 25.4) as u32;

    if let Some(mode) = view.modes.get_mut(0) {
        mode.width = safe_width;
        mode.height = safe_height;
    }
    view.usable_area = crate::util::geometry::Rect::new(0, 0, safe_width, safe_height);
    view
}

/// Like [`notify_output_change_for_client`], but sends the given logical size + scale
/// to that client's `wl_output` / `xdg_output` only, without reading dimensions from
/// [`CompositorState::outputs`].
pub fn notify_output_change_for_client_override(
    state: &CompositorState,
    output_id: u32,
    client_id: &wayland_server::backend::ClientId,
    width: u32,
    height: u32,
    scale: f32,
) {
    let base = match state.outputs.iter().find(|o| o.id == output_id) {
        Some(o) => o,
        None => {
            tracing::warn!("notify_output_change_for_client_override: output {} not found", output_id);
            return;
        }
    };

    let view = output_state_view_for_dimensions(base, width, height, scale);

    let mut notified = 0;
    for (_obj_id, output_res) in &state.output_resources {
        if !output_res.is_alive() {
            continue;
        }
        if let Some(client) = output_res.client() {
            if client.id() == *client_id {
                send_output_info(output_res, &view);
                notified += 1;
            }
        }
    }

    tracing::debug!(
        "Notified {} output resources for client {:?} of output {} override ({}x{} @ {}x)",
        notified,
        client_id,
        output_id,
        view.width,
        view.height,
        view.scale
    );

    crate::core::wayland::xdg::xdg_output::notify_xdg_output_change_for_client_override(
        state, client_id, &view,
    );
}
