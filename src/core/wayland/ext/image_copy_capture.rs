//! Image Copy Capture protocol implementation.
//!
//! Captures screen content into shared memory buffers.

use crate::core::wayland::protocol::server::ext::image_copy_capture::v1::server::{
    ext_image_copy_capture_cursor_session_v1::{self, ExtImageCopyCaptureCursorSessionV1},
    ext_image_copy_capture_frame_v1::{self, ExtImageCopyCaptureFrameV1},
    ext_image_copy_capture_manager_v1::{self, ExtImageCopyCaptureManagerV1},
    ext_image_copy_capture_session_v1::{self, ExtImageCopyCaptureSessionV1},
};
use std::sync::Mutex;
use wayland_server::protocol::wl_shm;
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use crate::core::surface::BufferType;

/// Session data: dimensions from source.
#[derive(Debug, Clone)]
pub struct CaptureSessionData {
    pub width: u32,
    pub height: u32,
}

/// Frame data: attached buffer, capture state, and session for cleanup on Destroy.
#[derive(Debug)]
pub struct CaptureFrameData {
    pub session_id: wayland_server::backend::ObjectId,
    pub buffer_id: Mutex<Option<u32>>,
    pub captured: Mutex<bool>,
}

/// Cursor session data (no extra state yet).
#[derive(Debug, Clone, Default)]
pub struct CursorSessionData;

/// Pending image copy capture: platform writes ARGB8888 pixels to ptr, then calls done.
pub struct PendingImageCopyCapture {
    pub capture_id: u64,
    pub frame: ExtImageCopyCaptureFrameV1,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub ptr: *mut u8,
    pub size: usize,
}
// SAFETY: ptr is only used by platform on callback thread; compositor processes completion under RwLock.
unsafe impl Send for PendingImageCopyCapture {}
unsafe impl Sync for PendingImageCopyCapture {}

impl GlobalDispatch<ExtImageCopyCaptureManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtImageCopyCaptureManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_image_copy_capture_manager_v1");
    }
}

impl Dispatch<ExtImageCopyCaptureManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtImageCopyCaptureManagerV1,
        request: ext_image_copy_capture_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_image_copy_capture_manager_v1::Request::CreateSession {
                session,
                source,
                options: _,
            } => {
                let output_id = state
                    .image_capture_source_output
                    .get(&source.id())
                    .copied()
                    .or_else(|| state.outputs.first().map(|o| o.id))
                    .unwrap_or(0);
                let (width, height) = state
                    .outputs
                    .iter()
                    .find(|o| o.id == output_id)
                    .map(|o| (o.width, o.height))
                    .unwrap_or_else(|| {
                        state
                            .outputs
                            .first()
                            .map(|o| (o.width, o.height))
                            .unwrap_or((0, 0))
                    });
                let session_data = CaptureSessionData { width, height };
                let s = data_init.init(session, session_data);
                if width == 0 || height == 0 {
                    s.stopped();
                } else {
                    s.buffer_size(width, height);
                    s.shm_format(wl_shm::Format::Argb8888);
                    s.done();
                }
                tracing::debug!(
                    "Created image copy capture session {}x{} for output {}",
                    width,
                    height,
                    output_id
                );
            }
            ext_image_copy_capture_manager_v1::Request::CreatePointerCursorSession {
                session,
                source: _,
                pointer: _,
            } => {
                let _s: ExtImageCopyCaptureCursorSessionV1 =
                    data_init.init(session, CursorSessionData);
            }
            ext_image_copy_capture_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCopyCaptureSessionV1, CaptureSessionData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtImageCopyCaptureSessionV1,
        request: ext_image_copy_capture_session_v1::Request,
        data: &CaptureSessionData,
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_image_copy_capture_session_v1::Request::CreateFrame { frame } => {
                if state
                    .ext
                    .image_copy_capture_active_frame
                    .contains_key(&resource.id())
                {
                    resource.post_error(
                        ext_image_copy_capture_session_v1::Error::DuplicateFrame,
                        "create_frame sent before destroying previous frame",
                    );
                    return;
                }
                let frame_data = CaptureFrameData {
                    session_id: resource.id().clone(),
                    buffer_id: Mutex::new(None),
                    captured: Mutex::new(false),
                };
                let _f = data_init.init(frame, frame_data);
                state
                    .ext
                    .image_copy_capture_active_frame
                    .insert(resource.id(), (data.width, data.height));
                tracing::debug!(
                    "Created image copy capture frame {}x{}",
                    data.width,
                    data.height
                );
            }
            ext_image_copy_capture_session_v1::Request::Destroy => {
                state
                    .ext
                    .image_copy_capture_active_frame
                    .remove(&resource.id());
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCopyCaptureFrameV1, CaptureFrameData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtImageCopyCaptureFrameV1,
        request: ext_image_copy_capture_frame_v1::Request,
        data: &CaptureFrameData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_image_copy_capture_frame_v1::Request::AttachBuffer { buffer } => {
                if *data.captured.lock().unwrap() {
                    resource.post_error(
                        ext_image_copy_capture_frame_v1::Error::AlreadyCaptured,
                        "capture already sent",
                    );
                    return;
                }
                *data.buffer_id.lock().unwrap() = Some(buffer.id().protocol_id());
                tracing::debug!(
                    "Image copy frame: attached buffer {}",
                    buffer.id().protocol_id()
                );
            }
            ext_image_copy_capture_frame_v1::Request::DamageBuffer {
                x,
                y,
                width,
                height,
            } => {
                if *data.captured.lock().unwrap() {
                    resource.post_error(
                        ext_image_copy_capture_frame_v1::Error::AlreadyCaptured,
                        "capture already sent",
                    );
                    return;
                }
                if x < 0 || y < 0 || width <= 0 || height <= 0 {
                    resource.post_error(
                        ext_image_copy_capture_frame_v1::Error::InvalidBufferDamage,
                        "invalid damage region",
                    );
                    return;
                }
                // Accept damage; we capture full buffer anyway for now
                tracing::trace!(
                    "Image copy frame: damage ({},{},{},{})",
                    x,
                    y,
                    width,
                    height
                );
            }
            ext_image_copy_capture_frame_v1::Request::Capture => {
                if *data.captured.lock().unwrap() {
                    resource.post_error(
                        ext_image_copy_capture_frame_v1::Error::AlreadyCaptured,
                        "capture already sent",
                    );
                    return;
                }
                let buffer_id = match *data.buffer_id.lock().unwrap() {
                    Some(id) => id,
                    None => {
                        resource.post_error(
                            ext_image_copy_capture_frame_v1::Error::NoBuffer,
                            "capture sent without attach_buffer",
                        );
                        return;
                    }
                };
                *data.captured.lock().unwrap() = true;

                let client_id = _client.id();
                let buffer_guard = match state.buffers.get(&(client_id.clone(), buffer_id)) {
                    Some(b) => b.read().unwrap().clone(),
                    None => {
                        tracing::warn!("Image copy Capture: unknown buffer {}", buffer_id);
                        resource.failed(
                            ext_image_copy_capture_frame_v1::FailureReason::BufferConstraints,
                        );
                        return;
                    }
                };
                let (width, height, stride, ptr, size) = match &buffer_guard.buffer_type {
                    BufferType::Shm(shm) => {
                        let pool = match state.shm_pools.get_mut(&(client_id, shm.pool_id)) {
                            Some(p) => p,
                            None => {
                                tracing::warn!("Image copy Copy: unknown pool {}", shm.pool_id);
                                resource.failed(ext_image_copy_capture_frame_v1::FailureReason::BufferConstraints);
                                return;
                            }
                        };
                        let base = match pool.map() {
                            Some(p) => p,
                            None => {
                                tracing::warn!("Image copy Copy: failed to map pool");
                                resource.failed(
                                    ext_image_copy_capture_frame_v1::FailureReason::Unknown,
                                );
                                return;
                            }
                        };
                        let offset = shm.offset.max(0) as usize;
                        let h = shm.height.max(0) as u32;
                        let s = shm.stride.max(0) as u32;
                        let sz = h as usize * s as usize;
                        let ptr = unsafe { base.add(offset) };
                        (shm.width.max(0) as u32, h, s, ptr, sz)
                    }
                    _ => {
                        tracing::warn!(
                            "Image copy Capture: buffer must be wl_shm, got {:?}",
                            buffer_guard.buffer_type
                        );
                        resource.failed(
                            ext_image_copy_capture_frame_v1::FailureReason::BufferConstraints,
                        );
                        return;
                    }
                };

                let capture_id = state.wlr.next_image_copy_capture_id;
                state.wlr.next_image_copy_capture_id =
                    state.wlr.next_image_copy_capture_id.wrapping_add(1);
                state
                    .wlr
                    .pending_image_copy_captures
                    .push(PendingImageCopyCapture {
                        capture_id,
                        frame: resource.clone(),
                        width,
                        height,
                        stride,
                        ptr,
                        size,
                    });
                tracing::debug!(
                    "Image copy Capture: queued capture {} ({}x{})",
                    capture_id,
                    width,
                    height
                );
            }
            ext_image_copy_capture_frame_v1::Request::Destroy => {
                state
                    .ext
                    .image_copy_capture_active_frame
                    .remove(&data.session_id);
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCopyCaptureCursorSessionV1, CursorSessionData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ExtImageCopyCaptureCursorSessionV1,
        request: ext_image_copy_capture_cursor_session_v1::Request,
        _data: &CursorSessionData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_image_copy_capture_cursor_session_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

/// Get the first pending image copy capture for platform to fulfill.
pub fn get_pending_image_copy_capture(
    state: &CompositorState,
) -> Option<(u64, *mut u8, u32, u32, u32, usize)> {
    state
        .wlr
        .pending_image_copy_captures
        .first()
        .map(|p| (p.capture_id, p.ptr, p.width, p.height, p.stride, p.size))
}

/// Complete an image copy capture: send transform, damage, presentation_time, ready; remove from pending.
pub fn complete_image_copy_capture(state: &mut CompositorState, capture_id: u64) -> bool {
    if let Some(pos) = state
        .wlr
        .pending_image_copy_captures
        .iter()
        .position(|p| p.capture_id == capture_id)
    {
        let pending = state.wlr.pending_image_copy_captures.remove(pos);
        if pending.frame.is_alive() {
            use wayland_server::protocol::wl_output;
            pending.frame.transform(wl_output::Transform::Normal);
            pending
                .frame
                .damage(0, 0, pending.width as i32, pending.height as i32);
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let tv_sec = now.as_secs();
            let tv_sec_hi = (tv_sec >> 32) as u32;
            let tv_sec_lo = (tv_sec & 0xFFFF_FFFF) as u32;
            let tv_nsec = now.subsec_nanos();
            pending
                .frame
                .presentation_time(tv_sec_hi, tv_sec_lo, tv_nsec);
            pending.frame.ready();
            tracing::debug!("Image copy capture {} ready", capture_id);
        }
        true
    } else {
        false
    }
}

/// Fail an image copy capture: send failed, remove from pending.
pub fn fail_image_copy_capture(state: &mut CompositorState, capture_id: u64) -> bool {
    if let Some(pos) = state
        .wlr
        .pending_image_copy_captures
        .iter()
        .position(|p| p.capture_id == capture_id)
    {
        let pending = state.wlr.pending_image_copy_captures.remove(pos);
        if pending.frame.is_alive() {
            pending
                .frame
                .failed(ext_image_copy_capture_frame_v1::FailureReason::Unknown);
            tracing::debug!("Image copy capture {} failed", capture_id);
        }
        true
    } else {
        false
    }
}

pub fn register_image_copy_capture(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtImageCopyCaptureManagerV1, ()>(1, ())
}
