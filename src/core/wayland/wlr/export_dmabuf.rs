//! zwlr_export_dmabuf_unstable_v1.
//!
//! Protocol queues a capture request in Rust core. Hosts with a DMA-BUF (or
//! portable buffer-export) capability complete the frame; hosts without that
//! capability cancel. Semantics do not assume Linux kernel DRM.

use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol_proofs::export_dmabuf_should_cancel_without_capability;

use crate::core::wayland::protocol::wlroots::wlr_export_dmabuf_unstable_v1::{
    zwlr_export_dmabuf_frame_v1, zwlr_export_dmabuf_manager_v1,
};

use std::collections::HashMap;

/// Frame metadata queued for the host export capability.
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
    /// Pending frame resource ids waiting for host completion or cancel.
    pub pending: Vec<u32>,
}

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

                let frame_res: zwlr_export_dmabuf_frame_v1::ZwlrExportDmabufFrameV1 =
                    data_init.init(frame, ());
                let resource_id = frame_res.id().protocol_id();

                let mut frame_state = DmabufExportFrame::new(output_id, overlay_cursor);
                if let Some(out) = state.outputs.iter().find(|o| o.id == output_id).or_else(|| {
                    state.outputs.first()
                }) {
                    frame_state.width = out.width;
                    frame_state.height = out.height;
                }

                state
                    .wlr
                    .export_dmabuf
                    .frames
                    .insert(resource_id, frame_state);
                state.wlr.export_dmabuf.pending.push(resource_id);

                // Without a host DMA-BUF/export capability, cancel temporarily.
                // Hosts that support export pop pending and complete the frame.
                if export_dmabuf_should_cancel_without_capability(false) {
                    frame_res.cancel(zwlr_export_dmabuf_frame_v1::CancelReason::Temporary);
                    state.wlr.export_dmabuf.frames.remove(&resource_id);
                    state.wlr.export_dmabuf.pending.retain(|id| *id != resource_id);
                }
            }
            zwlr_export_dmabuf_manager_v1::Request::Destroy => {}
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
                let id = resource.id().protocol_id();
                state.wlr.export_dmabuf.frames.remove(&id);
                state.wlr.export_dmabuf.pending.retain(|p| *p != id);
            }
            _ => {}
        }
    }
}

/// Register zwlr_export_dmabuf_manager_v1 global
pub fn register_export_dmabuf(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use crate::core::wayland::protocol_proofs::export_dmabuf_should_cancel_without_capability;

    #[test]
    fn cancel_without_capability() {
        assert!(export_dmabuf_should_cancel_without_capability(false));
        assert!(!export_dmabuf_should_cancel_without_capability(true));
    }

    #[test]
    fn frame_defaults_zero_geometry() {
        let f = super::DmabufExportFrame::new(7, true);
        assert_eq!(f.output_id, 7);
        assert!(f.overlay_cursor);
        assert_eq!(f.width, 0);
        assert_eq!(f.height, 0);
    }
}
