//! WP Viewporter protocol implementation.
//!
//! This protocol allows clients to crop and scale their surface content,
//! useful for video playback, image viewers, and resolution-independent UIs.
//! GTK4 / fractional-scale clients set destination to the logical size while
//! attaching a buffer at physical pixels; destination must drive surface
//! logical size on commit.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::wayland::protocol::server::wp::viewporter::server::{
    wp_viewporter::{self, WpViewporter},
    wp_viewport::{self, WpViewport},
};


use crate::core::state::CompositorState;
use crate::core::surface::surface::SurfaceState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone)]
pub struct ViewportData {
    pub surface_id: u32,
    /// Double-buffered: written by set_source, applied on wl_surface.commit.
    pub pending_source: Option<ViewportSource>,
    pub pending_destination: Option<(i32, i32)>,
    /// Applied on last surface commit (what scene/present use).
    pub source: Option<ViewportSource>,
    pub destination: Option<(i32, i32)>,
}

#[derive(Debug, Clone, Copy)]
pub struct ViewportSource {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl ViewportData {
    pub fn new(surface_id: u32) -> Self {
        Self {
            surface_id,
            pending_source: None,
            pending_destination: None,
            source: None,
            destination: None,
        }
    }

    /// Apply pending viewport state (call from surface commit).
    pub fn apply_pending(&mut self) {
        self.source = self.pending_source;
        self.destination = self.pending_destination;
    }
}

/// State for viewporter protocol
#[derive(Debug, Default)]
pub struct ViewporterState {
    /// viewport object id -> data
    pub viewports: HashMap<u32, ViewportData>,
    /// surface_id -> viewport object id (at most one viewport per surface)
    pub surface_to_viewport: HashMap<u32, u32>,
}

impl ViewporterState {
    pub fn for_surface(&self, surface_id: u32) -> Option<&ViewportData> {
        let vid = self.surface_to_viewport.get(&surface_id)?;
        self.viewports.get(vid)
    }

    pub fn for_surface_mut(&mut self, surface_id: u32) -> Option<&mut ViewportData> {
        let vid = *self.surface_to_viewport.get(&surface_id)?;
        self.viewports.get_mut(&vid)
    }

    /// Apply pending viewport and override surface logical size from destination.
    /// Returns true when a destination size was applied.
    pub fn apply_on_surface_commit(
        &mut self,
        surface_id: u32,
        current: &mut SurfaceState,
    ) -> bool {
        let Some(data) = self.for_surface_mut(surface_id) else {
            return false;
        };
        data.apply_pending();

        let dest = data.destination;
        let source = data.source;
        let applied_dest = if let Some((dw, dh)) = dest {
            current.width = dw;
            current.height = dh;
            true
        } else {
            false
        };

        let (buf_w, buf_h) = current
            .buffer
            .dimensions()
            .unwrap_or((0, 0));
        tracing::debug!(
            "Viewport commit surface={}: buf={}x{} logical={}x{} dest={:?} source={:?} buffer_scale={}",
            surface_id,
            buf_w,
            buf_h,
            current.width,
            current.height,
            dest,
            source.map(|s| (s.x, s.y, s.width, s.height)),
            current.scale
        );
        applied_dest
    }
}


// ============================================================================
// wp_viewporter
// ============================================================================

impl GlobalDispatch<WpViewporter, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpViewporter>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_viewporter");
    }
}

impl Dispatch<WpViewporter, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpViewporter,
        request: wp_viewporter::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_viewporter::Request::GetViewport { id, surface } => {
                // Must use the compositor's internal surface id. Protocol object
                // ids diverge from next_surface_id(); keying by protocol_id made
                // apply_on_surface_commit / scene lookups miss, so GTK/Ghostty
                // viewport destinations never applied (Retina quadrant bug).
                let Some(client_id) = surface.client().map(|c| c.id()) else {
                    tracing::warn!("GetViewport ignored: surface has no client");
                    return;
                };
                let surface_id =
                    state.ensure_internal_surface_mapping(client_id, &surface);

                if state.ext.viewporter.surface_to_viewport.contains_key(&surface_id) {
                    // Protocol: at most one viewport per surface.
                    tracing::warn!(
                        "Viewport already exists for surface {}; replacing mapping",
                        surface_id
                    );
                }

                let viewport_data = ViewportData::new(surface_id);
                let viewport: wp_viewport::WpViewport = data_init.init(id, ());
                let viewport_id = viewport.id().protocol_id();
                state
                    .ext
                    .viewporter
                    .viewports
                    .insert(viewport_id, viewport_data);
                state
                    .ext
                    .viewporter
                    .surface_to_viewport
                    .insert(surface_id, viewport_id);

                tracing::debug!(
                    "Created viewport for surface {} (protocol object {})",
                    surface_id,
                    surface.id().protocol_id()
                );
            }
            wp_viewporter::Request::Destroy => {
                tracing::debug!("wp_viewporter destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_viewport
// ============================================================================

impl Dispatch<WpViewport, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpViewport,
        request: wp_viewport::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let viewport_id = resource.id().protocol_id();

        match request {
            wp_viewport::Request::SetSource { x, y, width, height } => {
                if let Some(data) = state.ext.viewporter.viewports.get_mut(&viewport_id) {
                    // -1 means unset
                    if x == -1.0 && y == -1.0 && width == -1.0 && height == -1.0 {
                        data.pending_source = None;
                        tracing::debug!(
                            "Viewport source unset (pending) for surface {}",
                            data.surface_id
                        );
                    } else {
                        if width <= 0.0 || height <= 0.0 {
                            resource.post_error(
                                wp_viewport::Error::BadSize,
                                "Source width and height must be positive",
                            );
                            return;
                        }

                        data.pending_source = Some(ViewportSource { x, y, width, height });
                        tracing::debug!(
                            "Viewport source pending for surface {}: ({}, {}) {}x{}",
                            data.surface_id, x, y, width, height
                        );
                    }
                }
            }
            wp_viewport::Request::SetDestination { width, height } => {
                if let Some(data) = state.ext.viewporter.viewports.get_mut(&viewport_id) {
                    // -1 means unset
                    if width == -1 && height == -1 {
                        data.pending_destination = None;
                        tracing::debug!(
                            "Viewport destination unset (pending) for surface {}",
                            data.surface_id
                        );
                    } else {
                        if width <= 0 || height <= 0 {
                            resource.post_error(
                                wp_viewport::Error::BadSize,
                                "Destination width and height must be positive",
                            );
                            return;
                        }

                        data.pending_destination = Some((width, height));
                        tracing::debug!(
                            "Viewport destination pending for surface {}: {}x{}",
                            data.surface_id, width, height
                        );
                    }
                }
            }
            wp_viewport::Request::Destroy => {
                if let Some(data) = state.ext.viewporter.viewports.remove(&viewport_id) {
                    state
                        .ext
                        .viewporter
                        .surface_to_viewport
                        .remove(&data.surface_id);
                    tracing::debug!("Viewport destroyed for surface {}", data.surface_id);
                }
            }
            _ => {}
        }
    }
}

/// Register wp_viewporter global
pub fn register_viewporter(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpViewporter, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::surface::buffer::{BufferType, ShmBufferData};
    use crate::core::surface::commit::apply_commit;
    use crate::core::surface::surface::SurfaceState;

    #[test]
    fn destination_overrides_buffer_logical_size() {
        let mut pending = SurfaceState::default();
        let mut current = SurfaceState::default();
        pending.buffer = BufferType::Shm(ShmBufferData {
            width: 1600,
            height: 1000,
            stride: 6400,
            format: 0,
            offset: 0,
            pool_id: 1,
        });
        pending.buffer_id = Some(1);
        pending.scale = 1;
        apply_commit(&mut pending, &mut current);
        assert_eq!(current.width, 1600);
        assert_eq!(current.height, 1000);

        let mut vp = ViewporterState::default();
        vp.viewports.insert(
            10,
            ViewportData {
                surface_id: 42,
                pending_source: None,
                pending_destination: Some((800, 500)),
                source: None,
                destination: None,
            },
        );
        vp.surface_to_viewport.insert(42, 10);

        assert!(vp.apply_on_surface_commit(42, &mut current));
        assert_eq!(current.width, 800);
        assert_eq!(current.height, 500);
        assert_eq!(
            vp.for_surface(42).and_then(|d| d.destination),
            Some((800, 500))
        );
        // Lookup by a different id (e.g. raw protocol object id) must miss.
        // Regression: GetViewport used to key by protocol_id while commit/scene
        // used internal ids, so destinations never applied.
        assert!(vp.for_surface(16).is_none());
        assert!(!vp.apply_on_surface_commit(16, &mut current));
        assert_eq!(current.width, 800);
        assert_eq!(current.height, 500);
    }
}
