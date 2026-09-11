//! Image Capture Source protocol implementation.
//!
//! Provides sources for screen capture.

use crate::core::wayland::protocol::server::ext::image_capture_source::v1::server::{
    ext_image_capture_source_v1::{self, ExtImageCaptureSourceV1},
    ext_output_image_capture_source_manager_v1::{self, ExtOutputImageCaptureSourceManagerV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

/// Per-source data: output_id for output-backed sources.
#[derive(Debug, Clone, Copy)]
pub struct ImageCaptureSourceData {
    pub output_id: u32,
}

impl GlobalDispatch<ExtOutputImageCaptureSourceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtOutputImageCaptureSourceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_output_image_capture_source_manager_v1");
    }
}

impl Dispatch<ExtOutputImageCaptureSourceManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtOutputImageCaptureSourceManagerV1,
        request: ext_output_image_capture_source_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_output_image_capture_source_manager_v1::Request::CreateSource {
                source,
                output,
            } => {
                let output_id = state
                    .output_id_by_resource
                    .get(&output.id())
                    .copied()
                    .or_else(|| state.outputs.first().map(|o| o.id))
                    .unwrap_or(0);
                let src = data_init.init(source, ImageCaptureSourceData { output_id });
                state
                    .image_capture_source_output
                    .insert(src.id(), output_id);
                tracing::debug!("Created image capture source for output {}", output_id);
            }
            ext_output_image_capture_source_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCaptureSourceV1, ImageCaptureSourceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtImageCaptureSourceV1,
        request: ext_image_capture_source_v1::Request,
        _data: &ImageCaptureSourceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_image_capture_source_v1::Request::Destroy => {
                state.image_capture_source_output.remove(&resource.id());
            }
            _ => {}
        }
    }
}

pub fn register_image_capture_source(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtOutputImageCaptureSourceManagerV1, ()>(1, ())
}
