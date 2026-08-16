//! Content Type protocol implementation.
//!
//! This protocol allows clients to hint the compositor about the content type
//! of a surface (e.g., video, game, photo), enabling compositor optimizations.
//! The compositor can use this hint to adjust frame scheduling and rendering.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::content_type::v1::server::{
    wp_content_type_manager_v1::{self, WpContentTypeManagerV1},
    wp_content_type_v1::{self, WpContentTypeV1},
};

use crate::core::state::CompositorState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

/// Content type hint for a surface
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContentType {
    /// No content type hint
    None,
    /// Photo content. Optimize for quality
    Photo,
    /// Video content. Optimize for smooth playback
    Video,
    /// Game content. Optimize for low latency
    Game,
}

impl Default for ContentType {
    fn default() -> Self {
        ContentType::None
    }
}

/// State for tracking content type hints per surface
#[derive(Debug, Default)]
pub struct ContentTypeState {
    /// Content type per surface (surface_id -> content_type)
    pub surface_types: HashMap<u32, ContentType>,
}

impl ContentTypeState {
    pub fn get(&self, surface_id: u32) -> ContentType {
        self.surface_types.get(&surface_id).copied().unwrap_or(ContentType::None)
    }

    pub fn remove_surface(&mut self, surface_id: u32) {
        self.surface_types.remove(&surface_id);
    }
}

// ============================================================================
// wp_content_type_manager_v1
// ============================================================================

impl GlobalDispatch<WpContentTypeManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpContentTypeManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_content_type_manager_v1");
    }
}

impl Dispatch<WpContentTypeManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpContentTypeManagerV1,
        request: wp_content_type_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_content_type_manager_v1::Request::GetSurfaceContentType { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _ct: wp_content_type_v1::WpContentTypeV1 = data_init.init(id, surface_id);
                tracing::debug!("Created content type for surface {}", surface_id);
            }
            wp_content_type_manager_v1::Request::Destroy => {
                tracing::debug!("wp_content_type_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_content_type_v1. Uses surface_id (u32) as user data
// ============================================================================

impl Dispatch<WpContentTypeV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpContentTypeV1,
        request: wp_content_type_v1::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let surface_id = *data;
        match request {
            wp_content_type_v1::Request::SetContentType { content_type } => {
                let ct = match content_type {
                    wayland_server::WEnum::Value(v) => {
                        use wayland_protocols::wp::content_type::v1::server::wp_content_type_v1::Type;
                        match v {
                            Type::None => ContentType::None,
                            Type::Photo => ContentType::Photo,
                            Type::Video => ContentType::Video,
                            Type::Game => ContentType::Game,
                            _ => ContentType::None,
                        }
                    }
                    wayland_server::WEnum::Unknown(v) => {
                        tracing::warn!("Unknown content type value: {}", v);
                        ContentType::None
                    }
                };
                tracing::debug!("Set content type {:?} for surface {}", ct, surface_id);
                state.ext.content_type.surface_types.insert(surface_id, ct);
            }
            wp_content_type_v1::Request::Destroy => {
                state.ext.content_type.surface_types.remove(&surface_id);
                tracing::debug!("wp_content_type_v1 destroyed for surface {}", surface_id);
            }
            _ => {}
        }
    }
}

/// Register wp_content_type_manager_v1 global
pub fn register_content_type(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpContentTypeManagerV1, ()>(1, ())
}
