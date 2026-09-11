//! Single Pixel Buffer protocol implementation.
//!
//! This protocol allows clients to create a buffer with a single pixel,
//! useful for solid color surfaces without needing shared memory.
//! The RGBA values are u32 fixed-point with 0 = 0.0 and u32::MAX = 1.0.

use wayland_protocols::wp::single_pixel_buffer::v1::server::wp_single_pixel_buffer_manager_v1::{
    self, WpSinglePixelBufferManagerV1,
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

// ============================================================================
// wp_single_pixel_buffer_manager_v1
// ============================================================================

impl GlobalDispatch<WpSinglePixelBufferManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpSinglePixelBufferManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_single_pixel_buffer_manager_v1");
    }
}

impl Dispatch<WpSinglePixelBufferManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpSinglePixelBufferManagerV1,
        request: wp_single_pixel_buffer_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_single_pixel_buffer_manager_v1::Request::CreateU32RgbaBuffer { id, r, g, b, a } => {
                let buffer_res = data_init.init(id, ());
                let buffer_id = buffer_res.id().protocol_id();

                // Convert fixed-point u32 RGBA to 8-bit values for storage
                // u32::MAX → 255, 0 → 0
                let r8 = (r >> 24) as u8;
                let g8 = (g >> 24) as u8;
                let b8 = (b >> 24) as u8;
                let a8 = (a >> 24) as u8;

                // Store as a 1x1 Native buffer with ARGB8888 packed pixel
                let pixel =
                    ((a8 as u32) << 24) | ((r8 as u32) << 16) | ((g8 as u32) << 8) | (b8 as u32);
                let native_data = crate::core::surface::buffer::NativeBufferData {
                    id: pixel as u64,
                    width: 1,
                    height: 1,
                    format: 0, // ARGB8888
                };

                state.add_buffer(
                    _client.id(),
                    crate::core::surface::Buffer::new(
                        buffer_id,
                        crate::core::surface::BufferType::Native(native_data),
                        Some(buffer_res),
                    ),
                );

                tracing::debug!(
                    "Created single pixel buffer {}: rgba({:#010x}, {:#010x}, {:#010x}, {:#010x}) → #{:02x}{:02x}{:02x}{:02x}",
                    buffer_id, r, g, b, a, r8, g8, b8, a8
                );
            }
            wp_single_pixel_buffer_manager_v1::Request::Destroy => {
                tracing::debug!("wp_single_pixel_buffer_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

/// Register wp_single_pixel_buffer_manager_v1 global
pub fn register_single_pixel_buffer(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpSinglePixelBufferManagerV1, ()>(1, ())
}
