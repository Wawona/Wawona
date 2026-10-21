//! WP Viewporter protocol implementation.
//!
//! This protocol allows clients to crop and scale their surface content,
//! useful for video playback, image viewers, and resolution-independent UIs.
//! GTK4 / fractional-scale clients set destination to the logical size while
//! attaching a buffer at physical pixels; destination must drive surface
//! logical size on commit.

use crate::core::wayland::protocol::server::wp::viewporter::server::{
    wp_viewport::{self, WpViewport},
    wp_viewporter::{self, WpViewporter},
};
use wayland_server::protocol::wl_surface::WlSurface;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use crate::core::surface::surface::SurfaceState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone)]
pub struct ViewportData {
    pub surface_id: u32,
    /// The `wl_surface` this viewport belongs to; requests after it is
    /// destroyed raise `no_surface`.
    pub surface: Option<WlSurface>,
    /// Viewport object, for commit-time protocol errors.
    pub resource: Option<WpViewport>,
    /// Double-buffered: written by set_source, applied on wl_surface.commit.
    pub pending_source: Option<ViewportSource>,
    pub pending_destination: Option<(i32, i32)>,
    /// Applied on last surface commit (what scene/present use).
    pub source: Option<ViewportSource>,
    pub destination: Option<(i32, i32)>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ViewportSource {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// Commit-time `wp_viewport` violations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewportCommitError {
    /// Source has a fractional size and no destination is set.
    BadSize,
    /// Source rectangle extends outside the buffer (surface coordinates).
    OutOfBuffer,
}

impl ViewportData {
    pub fn new(surface_id: u32) -> Self {
        Self {
            surface_id,
            surface: None,
            resource: None,
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

/// Surface size after the viewport is applied, per wp_viewporter: the
/// destination if set, else the (integral) source size, else the buffer size
/// in surface coordinates. `buffer_size` is already divided by
/// `wl_surface.buffer_scale` and transformed.
pub fn viewport_surface_size(
    buffer_size: (i32, i32),
    source: Option<ViewportSource>,
    destination: Option<(i32, i32)>,
) -> Result<(i32, i32), ViewportCommitError> {
    if let Some(src) = source {
        let (bw, bh) = (f64::from(buffer_size.0), f64::from(buffer_size.1));
        if src.x + src.width > bw || src.y + src.height > bh {
            return Err(ViewportCommitError::OutOfBuffer);
        }
    }
    if let Some(dest) = destination {
        return Ok(dest);
    }
    match source {
        Some(src) if src.width.fract() != 0.0 || src.height.fract() != 0.0 => {
            Err(ViewportCommitError::BadSize)
        }
        Some(src) => Ok((src.width as i32, src.height as i32)),
        None => Ok(buffer_size),
    }
}

/// `set_source` arguments are all -1 (unset) or a non-negative origin with a
/// positive size.
fn source_request_is_valid(x: f64, y: f64, width: f64, height: f64) -> bool {
    let unset = [x, y, width, height].iter().all(|v| *v == -1.0);
    unset || (x >= 0.0 && y >= 0.0 && width > 0.0 && height > 0.0)
}

/// `set_destination` arguments are both -1 (unset) or both positive.
fn destination_request_is_valid(width: i32, height: i32) -> bool {
    (width == -1 && height == -1) || (width > 0 && height > 0)
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

    /// Apply pending viewport state and set the surface size from it. Posts
    /// the protocol error on the viewport and returns false on violation.
    /// Returns true when the viewport changed the surface size.
    pub fn apply_on_surface_commit(&mut self, surface_id: u32, current: &mut SurfaceState) -> bool {
        let Some(data) = self.for_surface_mut(surface_id) else {
            return false;
        };
        data.apply_pending();
        if current.buffer.dimensions().is_none() {
            return false;
        }
        let buffer_size = (current.width, current.height);
        match viewport_surface_size(buffer_size, data.source, data.destination) {
            Ok(size) => {
                current.width = size.0;
                current.height = size.1;
                size != buffer_size
            }
            Err(err) => {
                if let Some(resource) = &data.resource {
                    let (code, message) = match err {
                        ViewportCommitError::BadSize => (
                            wp_viewport::Error::BadSize,
                            "source size is not integral and no destination is set",
                        ),
                        ViewportCommitError::OutOfBuffer => (
                            wp_viewport::Error::OutOfBuffer,
                            "source rectangle extends outside the buffer",
                        ),
                    };
                    resource.post_error(code, message);
                }
                false
            }
        }
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
        resource: &WpViewporter,
        request: wp_viewporter::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_viewporter::Request::GetViewport { id, surface } => {
                // Must use the compositor's internal surface id. Protocol object
                // ids diverge from next_surface_id(); keying by protocol_id made
                // apply_on_surface_commit / scene lookups miss, so GTK
                // viewport destinations never applied (Retina quadrant bug).
                let Some(client_id) = surface.client().map(|c| c.id()) else {
                    tracing::warn!("GetViewport ignored: surface has no client");
                    return;
                };
                let surface_id = state.ensure_internal_surface_mapping(client_id, &surface);

                let has_live_viewport = state
                    .ext
                    .viewporter
                    .for_surface(surface_id)
                    .and_then(|data| data.surface.as_ref())
                    .is_some_and(|existing| existing.id() == surface.id());
                if has_live_viewport {
                    resource.post_error(
                        wp_viewporter::Error::ViewportExists,
                        "the surface already has a viewport",
                    );
                    return;
                }

                let viewport: wp_viewport::WpViewport = data_init.init(id, ());
                let viewport_id = viewport.id().protocol_id();
                let mut viewport_data = ViewportData::new(surface_id);
                viewport_data.surface = Some(surface.clone());
                viewport_data.resource = Some(viewport);
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

        if let wp_viewport::Request::Destroy = request {
            let owns_mapping = |state: &CompositorState, surface_id: u32| {
                state.ext.viewporter.surface_to_viewport.get(&surface_id) == Some(&viewport_id)
            };
            if let Some(data) = state.ext.viewporter.viewports.remove(&viewport_id) {
                if owns_mapping(state, data.surface_id) {
                    state
                        .ext
                        .viewporter
                        .surface_to_viewport
                        .remove(&data.surface_id);
                }
                tracing::debug!("Viewport destroyed for surface {}", data.surface_id);
            }
            return;
        }

        let Some(data) = state.ext.viewporter.viewports.get_mut(&viewport_id) else {
            return;
        };
        if !data.surface.as_ref().is_some_and(|s| s.is_alive()) {
            resource.post_error(
                wp_viewport::Error::NoSurface,
                "the wl_surface of this viewport was destroyed",
            );
            return;
        }

        match request {
            wp_viewport::Request::SetSource {
                x,
                y,
                width,
                height,
            } => {
                if !source_request_is_valid(x, y, width, height) {
                    resource.post_error(
                        wp_viewport::Error::BadValue,
                        "source origin must be non-negative and size positive, or all -1",
                    );
                    return;
                }
                data.pending_source = (x != -1.0).then_some(ViewportSource {
                    x,
                    y,
                    width,
                    height,
                });
            }
            wp_viewport::Request::SetDestination { width, height } => {
                if !destination_request_is_valid(width, height) {
                    resource.post_error(
                        wp_viewport::Error::BadValue,
                        "destination size must be positive, or both -1",
                    );
                    return;
                }
                data.pending_destination = (width != -1).then_some((width, height));
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

    fn source(x: f64, y: f64, width: f64, height: f64) -> Option<ViewportSource> {
        Some(ViewportSource {
            x,
            y,
            width,
            height,
        })
    }

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
        let mut data = ViewportData::new(42);
        data.pending_destination = Some((800, 500));
        vp.viewports.insert(10, data);
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

    #[test]
    fn viewport_surface_size_should_prefer_destination_over_source() {
        assert_eq!(
            viewport_surface_size((100, 100), source(0.0, 0.0, 50.5, 20.0), Some((83, 20))),
            Ok((83, 20))
        );
    }

    #[test]
    fn viewport_surface_size_should_use_integral_source_without_destination() {
        assert_eq!(
            viewport_surface_size((100, 50), source(0.0, 0.0, 82.0, 20.0), None),
            Ok((82, 20))
        );
    }

    #[test]
    fn viewport_surface_size_should_fall_back_to_buffer_size() {
        assert_eq!(
            viewport_surface_size((640, 480), None, None),
            Ok((640, 480))
        );
    }

    #[test]
    fn viewport_surface_size_should_reject_fractional_source_without_destination() {
        assert_eq!(
            viewport_surface_size((200, 100), source(0.0, 0.0, 23.2, 100.0), None),
            Err(ViewportCommitError::BadSize)
        );
    }

    #[test]
    fn viewport_surface_size_should_reject_source_outside_scaled_buffer() {
        // 200x100 buffer at scale 2 is 100x50 in surface coordinates.
        assert_eq!(
            viewport_surface_size((100, 50), source(50.0, 0.0, 50.5, 50.0), None),
            Err(ViewportCommitError::OutOfBuffer)
        );
    }

    #[test]
    fn source_request_should_accept_unset_and_positive_rects_only() {
        assert!(source_request_is_valid(-1.0, -1.0, -1.0, -1.0));
        assert!(source_request_is_valid(0.0, 0.0, 1.0, 1.0));
        assert!(!source_request_is_valid(0.0, 0.0, -1.0, 0.0));
        assert!(!source_request_is_valid(0.0, 0.0, 1.0, 0.0));
        assert!(!source_request_is_valid(-1.0, 0.0, 0.0, 0.0));
    }

    #[test]
    fn destination_request_should_accept_unset_and_positive_sizes_only() {
        assert!(destination_request_is_valid(-1, -1));
        assert!(destination_request_is_valid(83, 20));
        assert!(!destination_request_is_valid(-1, 0));
        assert!(!destination_request_is_valid(1, 0));
        assert!(!destination_request_is_valid(0, 1));
    }
}
