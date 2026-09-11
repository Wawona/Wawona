//! wlr-layer-shell-unstable-v1 protocol implementation.
//!
//! Enables surfaces to be placed in "layers" (background, bottom, top, overlay).
//! Used for: panels, wallpapers, lock screens, notifications, overlays.
//!
//! ## wlroots Compositor Support
//!
//! This implementation is critical for wlroots-based compositors (Sway, Hyprland, river)
//! running as nested compositors via waypipe. They use layer shell for:
//! - Background surfaces
//! - Panels and status bars
//! - Overlay surfaces
//!
//! Key requirements for proper operation:
//! 1. Must send `configure` event after `get_layer_surface`
//! 2. Must track surface IDs correctly (not hardcode to 0)
//! 3. Must set surface role to Layer

use crate::core::wayland::protocol::wlroots::wlr_layer_shell_unstable_v1::{
    zwlr_layer_shell_v1, zwlr_layer_surface_v1,
};
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::{CompositorState, LayerSurface};
use crate::core::surface::role::SurfaceRole;

// ============================================================================
// Layer Surface Data (stored with each zwlr_layer_surface_v1 resource)
// ============================================================================

/// Data stored with each layer surface resource.
/// This is the key fix - we need to track the surface ID with the protocol resource.
#[derive(Debug, Clone)]
pub struct LayerSurfaceData {
    /// The wl_surface ID this layer surface is associated with
    pub surface_id: u32,
    /// The output ID this layer surface is on
    pub output_id: u32,
    /// The layer (background, bottom, top, overlay)
    pub layer: u32,
    /// Layer surface namespace
    pub namespace: String,
}

impl LayerSurfaceData {
    pub fn new(surface_id: u32, output_id: u32, layer: u32, namespace: String) -> Self {
        Self {
            surface_id,
            output_id,
            layer,
            namespace,
        }
    }
}

// ============================================================================
// Layer Shell Global
// ============================================================================

pub struct LayerShellGlobal;

impl GlobalDispatch<zwlr_layer_shell_v1::ZwlrLayerShellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_layer_shell_v1::ZwlrLayerShellV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwlr_layer_shell_v1");
    }
}

impl Dispatch<zwlr_layer_shell_v1::ZwlrLayerShellV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_layer_shell_v1::ZwlrLayerShellV1,
        request: zwlr_layer_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_layer_shell_v1::Request::GetLayerSurface {
                id,
                surface,
                output,
                layer,
                namespace,
            } => {
                // Get the internal surface ID from the wl_surface resource's user data
                let surface_protocol_id = surface.id().protocol_id();

                // Look up the internal surface ID from our mapping
                let client_id = _client.id();
                let surface_id = state.protocol_to_internal_surface
                    .get(&(client_id.clone(), surface_protocol_id))
                    .copied()
                    .unwrap_or_else(|| {
                        // Fallback: use protocol ID if no mapping exists
                        tracing::warn!("Layer shell: No internal ID mapping for protocol surface {}, using protocol ID", surface_protocol_id);
                        surface_protocol_id
                    });

                let output_id = output
                    .as_ref()
                    .map(|o| o.id().protocol_id())
                    .unwrap_or_else(|| {
                        state
                            .outputs
                            .get(state.primary_output)
                            .map(|o| o.id)
                            .unwrap_or(0)
                    });
                let output_id = output
                    .as_ref()
                    .and_then(|o| state.output_id_by_resource.get(&o.id()).copied())
                    .unwrap_or(output_id);

                // Map the layer enum from the protocol to our u32
                let layer_val = match layer {
                    wayland_server::backend::protocol::WEnum::Value(v) => v as u32,
                    wayland_server::backend::protocol::WEnum::Unknown(v) => v,
                };

                tracing::info!(
                    "Layer shell: Creating layer surface for surface {} on output {} (layer={}, namespace={})",
                    surface_id, output_id, layer_val, namespace
                );

                // Create and store the layer surface state
                let layer_surface =
                    LayerSurface::new(surface_id, output_id, layer_val, namespace.clone());
                state.add_layer_surface(client_id.clone(), layer_surface);

                // Map surface to layer surface for buffer handling
                state
                    .wlr
                    .surface_to_layer
                    .insert((client_id.clone(), surface_id), surface_id);

                // Set the surface role to Layer
                if let Some(surf) = state.get_surface(surface_id) {
                    let mut surf = surf.write().unwrap();
                    if let Err(e) = surf.set_role(SurfaceRole::Layer) {
                        tracing::warn!("Failed to set Layer role on surface {}: {}", surface_id, e);
                    }
                }

                // Create layer surface data to store with the resource
                let layer_surface_data =
                    LayerSurfaceData::new(surface_id, output_id, layer_val, namespace);

                // Initialize the layer surface resource with our data
                let layer_surface_resource: zwlr_layer_surface_v1::ZwlrLayerSurfaceV1 =
                    data_init.init(id, layer_surface_data);

                // CRITICAL: Send initial configure event!
                // wlroots clients BLOCK until they receive this configure event.
                // Get output dimensions for the configure
                let (output_width, output_height) = state
                    .outputs
                    .iter()
                    .find(|o| o.id == output_id)
                    .map(|o| (o.width, o.height))
                    .unwrap_or_else(|| {
                        state
                            .outputs
                            .get(state.primary_output)
                            .map(|o| (o.width, o.height))
                            .unwrap_or((1920, 1080))
                    });

                let serial = state.next_serial();

                // Update layer surface state with resource and pending serial
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.pending_serial = serial;
                    ls.resource = Some(layer_surface_resource.clone());
                }

                // Send configure event with output dimensions
                layer_surface_resource.configure(serial, output_width, output_height);

                tracing::info!(
                    "Layer shell: Sent configure (serial={}) with dimensions {}x{} to surface {}",
                    serial,
                    output_width,
                    output_height,
                    surface_id
                );
            }
            zwlr_layer_shell_v1::Request::Destroy => {
                tracing::debug!("zwlr_layer_shell_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// Layer Surface
// ============================================================================

impl Dispatch<zwlr_layer_surface_v1::ZwlrLayerSurfaceV1, LayerSurfaceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_layer_surface_v1::ZwlrLayerSurfaceV1,
        request: zwlr_layer_surface_v1::Request,
        data: &LayerSurfaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        // Use the surface ID from our stored data - THIS IS THE KEY FIX
        let surface_id = data.surface_id;
        let client_id = _client.id();

        match request {
            zwlr_layer_surface_v1::Request::SetSize { width, height } => {
                tracing::debug!(
                    "Layer surface {}: set_size {}x{}",
                    surface_id,
                    width,
                    height
                );
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.width = width;
                    ls.height = height;
                }
                state.reposition_layer_surfaces();
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let ls = ls.read().unwrap();
                    state.configure_layer_surface(surface_id, ls.width, ls.height);
                }
            }
            zwlr_layer_surface_v1::Request::SetAnchor { anchor } => {
                let anchor_val = match anchor {
                    wayland_server::backend::protocol::WEnum::Value(v) => v.bits(),
                    wayland_server::backend::protocol::WEnum::Unknown(v) => v,
                };
                tracing::debug!(
                    "Layer surface {}: set_anchor 0x{:x}",
                    surface_id,
                    anchor_val
                );
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.anchor = anchor_val;
                }
                state.reposition_layer_surfaces();
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let ls = ls.read().unwrap();
                    state.configure_layer_surface(surface_id, ls.width, ls.height);
                }
            }
            zwlr_layer_surface_v1::Request::SetExclusiveZone { zone } => {
                tracing::debug!("Layer surface {}: set_exclusive_zone {}", surface_id, zone);
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.exclusive_zone = zone;
                }
                state.reposition_layer_surfaces();
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let ls = ls.read().unwrap();
                    state.configure_layer_surface(surface_id, ls.width, ls.height);
                }
            }
            zwlr_layer_surface_v1::Request::SetMargin {
                top,
                right,
                bottom,
                left,
            } => {
                tracing::debug!(
                    "Layer surface {}: set_margin t={} r={} b={} l={}",
                    surface_id,
                    top,
                    right,
                    bottom,
                    left
                );
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.margin = (top, right, bottom, left);
                }
                state.reposition_layer_surfaces();
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let ls = ls.read().unwrap();
                    state.configure_layer_surface(surface_id, ls.width, ls.height);
                }
            }
            zwlr_layer_surface_v1::Request::SetKeyboardInteractivity {
                keyboard_interactivity,
            } => {
                let interactivity_val = match keyboard_interactivity {
                    wayland_server::backend::protocol::WEnum::Value(v) => v as u32,
                    wayland_server::backend::protocol::WEnum::Unknown(v) => v,
                };
                tracing::debug!(
                    "Layer surface {}: set_keyboard_interactivity {}",
                    surface_id,
                    interactivity_val
                );
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.interactivity = interactivity_val;
                }
            }
            zwlr_layer_surface_v1::Request::GetPopup { popup: _popup } => {
                tracing::debug!("Layer surface {}: get_popup", surface_id);
                // popup is already initialized in this protocol version/implementation
            }
            zwlr_layer_surface_v1::Request::AckConfigure { serial } => {
                tracing::info!(
                    "Layer surface {}: ack_configure serial={}",
                    surface_id,
                    serial
                );
                if let Some(ls) = state.get_layer_surface(client_id.clone(), surface_id) {
                    let mut ls = ls.write().unwrap();
                    if serial == ls.pending_serial {
                        ls.configured = true;
                    }
                }
            }
            zwlr_layer_surface_v1::Request::Destroy => {
                tracing::info!("Layer surface {}: destroy", surface_id);
                state.remove_layer_surface(client_id.clone(), surface_id);
                state.wlr.surface_to_layer.remove(&(client_id, surface_id));
            }
            zwlr_layer_surface_v1::Request::SetLayer { layer } => {
                let layer_val = match layer {
                    wayland_server::backend::protocol::WEnum::Value(v) => v as u32,
                    wayland_server::backend::protocol::WEnum::Unknown(v) => v,
                };
                tracing::debug!("Layer surface {}: set_layer {}", surface_id, layer_val);
                if let Some(ls) = state.get_layer_surface(client_id, surface_id) {
                    let mut ls = ls.write().unwrap();
                    ls.layer = layer_val;
                }
                state.reposition_layer_surfaces();
                if let Some(ls) = state.get_layer_surface(_client.id(), surface_id) {
                    let ls = ls.read().unwrap();
                    state.configure_layer_surface(surface_id, ls.width, ls.height);
                }
            }
            _ => {}
        }
    }
}

// ============================================================================
// Helper function to send configure events for size changes
// ============================================================================

impl CompositorState {
    /// Send a configure event to a layer surface with new dimensions
    pub fn configure_layer_surface(&mut self, surface_id: u32, width: u32, height: u32) {
        let client_id = self
            .surfaces
            .get(&surface_id)
            .and_then(|s| s.read().unwrap().client_id.clone());
        if let Some(cid) = client_id {
            if let Some(ls) = self.get_layer_surface(cid, surface_id) {
                let serial = self.next_serial();
                let mut ls = ls.write().unwrap();
                ls.pending_serial = serial;
                ls.width = width;
                ls.height = height;
                if let Some(resource) = ls.resource.as_ref() {
                    resource.configure(serial, width, height);
                }
                tracing::debug!(
                    "Layer surface {}: sent configure serial={} {}x{}",
                    surface_id,
                    serial,
                    width,
                    height
                );
            }
        }
    }
}

/// Register zwlr_layer_shell_v1 global
pub fn register_layer_shell(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_layer_shell_v1::ZwlrLayerShellV1, ()>(4, ())
}
