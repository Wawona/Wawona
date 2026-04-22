//! wl_subcompositor and wl_subsurface protocol implementation
//!
//! The subcompositor allows clients to create subsurfaces - surfaces that are
//! positioned relative to a parent surface and composited together.
//!
//! Use cases:
//! - Video overlays
//! - Tooltips and popups positioned relative to widgets
//! - Hardware cursor planes
//! - Picture-in-picture


use wayland_server::{
    protocol::{
        wl_subcompositor::{self, WlSubcompositor},
        wl_subsurface::{self, WlSubsurface},

    },
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;
use crate::core::surface::SurfaceRole;

/// Subcompositor global data
#[derive(Debug, Default)]
pub struct SubcompositorState {
    // Can track subsurface relationships if needed
}

/// User data for wl_subsurface resources - stores the internal surface ID
pub type SubsurfaceData = u32;

// Use state::SubsurfaceState instead of local definition
use crate::core::state::SubsurfaceState;

// ============================================================================
// wl_subcompositor implementation
// ============================================================================

#[cfg(any())]
impl GlobalDispatch<WlSubcompositor, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlSubcompositor>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

#[cfg(any())]
impl Dispatch<WlSubcompositor, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WlSubcompositor,
        request: wl_subcompositor::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_subcompositor::Request::Destroy => {
                // Client is done with subcompositor
            }
            wl_subcompositor::Request::GetSubsurface { id, surface, parent } => {
                // Validate that surface is not the parent or an ancestor
                if surface == parent {
                    resource.post_error(
                        wl_subcompositor::Error::BadParent,
                        "Cannot make a surface its own subsurface",
                    );
                    return;
                }

                // Get protocol IDs first
                let surface_protocol_id = surface.id().protocol_id();
                let parent_protocol_id = parent.id().protocol_id();
                
                // Translate protocol IDs to internal IDs for proper lookup
                // Scoped by client ID to prevent collisions
                let client_id = _client.id();
                let surface_id = state.protocol_to_internal_surface
                    .get(&(client_id.clone(), surface_protocol_id))
                    .copied()
                    .unwrap_or(surface_protocol_id);
                let parent_id = state.protocol_to_internal_surface
                    .get(&(client_id, parent_protocol_id))
                    .copied()
                    .unwrap_or(parent_protocol_id);

                // Cannot assign subsurface role twice.
                if state.subsurfaces.contains_key(&surface_id) {
                    resource.post_error(
                        wl_subcompositor::Error::BadSurface,
                        format!("surface {} is already a subsurface", surface_id),
                    );
                    return;
                }

                // Prevent parent cycles.
                let mut ancestor = parent_id;
                for _ in 0..64 {
                    if ancestor == surface_id {
                        resource.post_error(
                            wl_subcompositor::Error::BadParent,
                            "Cannot create subsurface cycle",
                        );
                        return;
                    }
                    let Some(parent_state) = state.subsurfaces.get(&ancestor) else {
                        break;
                    };
                    ancestor = parent_state.parent_id;
                }

                // Child surface role must be None/Subsurface.
                if let Some(surface_ref) = state.get_surface(surface_id) {
                    let mut surface_state = surface_ref.write().unwrap();
                    if let Err(err) = surface_state.set_role(SurfaceRole::Subsurface) {
                        resource.post_error(
                            wl_subcompositor::Error::BadSurface,
                            format!("subsurface role conflict: {}", err),
                        );
                        return;
                    }
                }
                
                let subsurface_state = SubsurfaceState {
                    surface_id,
                    parent_id,
                    position: (0, 0),
                    pending_position: (0, 0),
                    sync: true,
                    z_order: 0,
                };
                // Store surface_id in user data so operations can look up the subsurface
                let subsurface: WlSubsurface = data_init.init(id, surface_id);
                
                // Track in our state map - key by INTERNAL surface ID so commit can find it
                state.subsurfaces.insert(surface_id, subsurface_state);

                // Register the subsurface relationship in state
                state.add_subsurface_resource(surface_id, parent_id, subsurface.clone());
                
                crate::wlog!(crate::util::logging::COMPOSITOR, 
                    "Created subsurface: surface={} (protocol={}), parent={} (protocol={})",
                    surface_id, surface_protocol_id, parent_id, parent_protocol_id);
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_subsurface implementation
// ============================================================================

#[cfg(any())]
impl Dispatch<WlSubsurface, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WlSubsurface,
        request: wl_subsurface::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        // Use the internal surface ID stored in user data
        let surface_id = *data;
        
        match request {
            wl_subsurface::Request::Destroy => {
                // Remove subsurface from tracking
                state.subsurfaces.remove(&surface_id);
                crate::wlog!(crate::util::logging::COMPOSITOR, "Subsurface destroyed: surface_id={}", surface_id);
            }
            wl_subsurface::Request::SetPosition { x, y } => {
                // Set pending position (applied on parent commit)
                state.set_subsurface_position(surface_id, x, y);
                
                // If this subsurface has been promoted to a window (popup), assume it effectively updates immediately
                // or at least we should notify the bridge to move the window.
                if let Some(window_id) = state.surface_to_window.get(&surface_id).copied() {
                    crate::wlog!(crate::util::logging::COMPOSITOR, "Repositioning promoted subsurface {} (window {}) to {},{}", surface_id, window_id, x, y);
                    state.pending_compositor_events.push(crate::core::compositor::CompositorEvent::PopupRepositioned {
                        window_id,
                        x,
                        y,
                        width: 0, // Bridge ignores these for simple move
                        height: 0,
                    });
                } else {
                     crate::wlog!(crate::util::logging::COMPOSITOR, 
                        "Subsurface set_position: surface_id={}, pos=({}, {})", surface_id, x, y);
                }
            }
            wl_subsurface::Request::PlaceAbove { sibling } => {
                // Reorder this subsurface to be above sibling
                let sibling_protocol_id = sibling.id().protocol_id();
                let sibling_id = state.protocol_to_internal_surface
                    .get(&(_client.id(), sibling_protocol_id))
                    .copied()
                    .unwrap_or(sibling_protocol_id);
                state.place_subsurface_above(surface_id, sibling_id);
                crate::wlog!(crate::util::logging::COMPOSITOR, 
                    "Subsurface place_above: {} above {}", surface_id, sibling_id);
            }
            wl_subsurface::Request::PlaceBelow { sibling } => {
                // Reorder this subsurface to be below sibling
                let sibling_protocol_id = sibling.id().protocol_id();
                let sibling_id = state.protocol_to_internal_surface
                    .get(&(_client.id(), sibling_protocol_id))
                    .copied()
                    .unwrap_or(sibling_protocol_id);
                state.place_subsurface_below(surface_id, sibling_id);
                crate::wlog!(crate::util::logging::COMPOSITOR, 
                    "Subsurface place_below: {} below {}", surface_id, sibling_id);
            }
            wl_subsurface::Request::SetSync => {
                // Enable synchronized mode (subsurface state applied with parent)
                state.set_subsurface_sync(surface_id, true);
                crate::wlog!(crate::util::logging::COMPOSITOR, "Subsurface set_sync: {}", surface_id);
            }
            wl_subsurface::Request::SetDesync => {
                // Enable desynchronized mode (subsurface state applied immediately)
                state.set_subsurface_sync(surface_id, false);
                crate::wlog!(crate::util::logging::COMPOSITOR, "Subsurface set_desync: {}", surface_id);
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        _client: wayland_server::backend::ClientId,
        _resource: &WlSubsurface,
        data: &u32,
    ) {
        let surface_id = *data;
        state.remove_subsurface(surface_id);
        crate::wlog!(crate::util::logging::COMPOSITOR, "Subsurface resource destroyed: surface_id={}", surface_id);
    }
}

/// Register wl_subcompositor global
pub fn register_subcompositor(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WlSubcompositor, ()>(1, ())
}
