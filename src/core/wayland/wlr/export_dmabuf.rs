use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;

use crate::core::wayland::protocol::wlroots::wlr_export_dmabuf_unstable_v1::{
    zwlr_export_dmabuf_frame_v1, zwlr_export_dmabuf_manager_v1,
};

use std::collections::HashMap;

/// Frame metadata (width, height, etc.) - populated when frame is ready
#[derive(Debug, Clone)]
pub struct DmabufExportFrame {
    pub output_id: u32,
    pub overlay_cursor: bool,
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub num_objects: u32,
}

impl DmabufExportFrame {
    pub fn new(output_id: u32, overlay_cursor: bool) -> Self {
        Self {
            output_id,
            overlay_cursor,
            width: 0,
            height: 0,
            format: 0,
            num_objects: 0,
        }
    }
}

#[derive(Debug, Default)]
pub struct ExportDmabufState {
    pub frames: HashMap<u32, DmabufExportFrame>,
}

pub struct ExportDmabufManagerData;

impl GlobalDispatch<zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1, ()>
    for CompositorState
{
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1,
        request: zwlr_export_dmabuf_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_export_dmabuf_manager_v1::Request::CaptureOutput {
                frame,
                overlay_cursor,
                output,
            } => {
                let output_id = output.data::<u32>().copied().unwrap_or(0);
                let overlay_cursor = overlay_cursor != 0;

                // Initialize the frame resource
                let frame_res: zwlr_export_dmabuf_frame_v1::ZwlrExportDmabufFrameV1 =
                    data_init.init(frame, ());
                let resource_id = frame_res.id().protocol_id();

                // Create frame state
                let frame_state = DmabufExportFrame::new(output_id, overlay_cursor);
                state
                    .wlr
                    .export_dmabuf
                    .frames
                    .insert(resource_id, frame_state);

                tracing::info!(
                    "DMABUF CaptureOutput requested: output={}, overlay_cursor={}, frame_id={}",
                    output_id,
                    overlay_cursor,
                    resource_id
                );

                // For now, we immediately cancel because we don't have the DMABUF export pipeline ready.
                // In a future phase, we would wait for the next frame and send metadata/fds.
                frame_res.cancel(zwlr_export_dmabuf_frame_v1::CancelReason::Temporary);
                state.wlr.export_dmabuf.frames.remove(&resource_id);
            }
            zwlr_export_dmabuf_manager_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_export_dmabuf_frame_v1::ZwlrExportDmabufFrameV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_export_dmabuf_frame_v1::ZwlrExportDmabufFrameV1,
        request: zwlr_export_dmabuf_frame_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_export_dmabuf_frame_v1::Request::Destroy => {
                let resource_id = resource.id().protocol_id();
                state.wlr.export_dmabuf.frames.remove(&resource_id);
            }

            _ => {}
        }
    }
}

/// Register zwlr_export_dmabuf_manager_v1 global
pub fn register_export_dmabuf(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1, ()>(1, ())
}
