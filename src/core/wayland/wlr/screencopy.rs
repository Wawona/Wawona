//! zwlr_screencopy_manager_v1. Screen capture via platform pixel readback.

use wayland_server::{protocol::wl_shm, Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;
use crate::core::surface::BufferType;
use crate::core::wayland::protocol::wlroots::wlr_screencopy_unstable_v1::{
    zwlr_screencopy_frame_v1, zwlr_screencopy_manager_v1,
};

/// Pending screencopy: platform writes ARGB8888 pixels to `ptr`, then calls `screencopy_done`.
/// SAFETY: The raw pointer is only dereferenced from the compositor's main loop. It points
/// into wl_shm pool memory. WawonaCore requires Send+Sync for IPC; we assert that the
/// pointer is never dereferenced concurrently across threads.
unsafe impl Send for PendingScreencopy {}
unsafe impl Sync for PendingScreencopy {}

pub struct PendingScreencopy {
    pub capture_id: u64,
    pub frame: zwlr_screencopy_frame_v1::ZwlrScreencopyFrameV1,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub ptr: *mut u8,
    pub size: usize,
}

impl GlobalDispatch<zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1,
        request: zwlr_screencopy_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_screencopy_manager_v1::Request::CaptureOutput { frame, overlay_cursor: _, output: _ } => {
                let _output_id = 0; // output.data::<u32>().copied().unwrap_or(0);
                let frame: zwlr_screencopy_frame_v1::ZwlrScreencopyFrameV1 = data_init.init(frame, ());
                
                // Send initial buffer information (default to primary output logic)
                if let Some(output_state) = state.outputs.first() {
                    // Advertise ARGB8888 as the preferred SHM format
                    frame.buffer(
                        wl_shm::Format::Argb8888,
                        output_state.width,
                        output_state.height,
                        output_state.width * 4,
                    );
                    
                    if frame.version() >= 3 {
                        frame.buffer_done();
                    }
                } else {
                    frame.failed();
                }
            }
            zwlr_screencopy_manager_v1::Request::CaptureOutputRegion { frame, overlay_cursor: _, output: _, x: _, y: _, width, height } => {
                let _output_id = 0; // output.data::<u32>().copied().unwrap_or(0);
                let frame: zwlr_screencopy_frame_v1::ZwlrScreencopyFrameV1 = data_init.init(frame, ());
                
                // Advertise requested region dimensions
                frame.buffer(
                    wl_shm::Format::Argb8888,
                    width as u32,
                    height as u32,
                    width as u32 * 4,
                );
                
                if frame.version() >= 3 {
                    frame.buffer_done();
                }
            }
            zwlr_screencopy_manager_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_screencopy_frame_v1::ZwlrScreencopyFrameV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_screencopy_frame_v1::ZwlrScreencopyFrameV1,
        request: zwlr_screencopy_frame_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_screencopy_frame_v1::Request::Copy { buffer }
            | zwlr_screencopy_frame_v1::Request::CopyWithDamage { buffer } => {
                let buffer_id = buffer.id().protocol_id();
                let client_id = _client.id();
                let buffer_guard = match state.buffers.get(&(client_id.clone(), buffer_id)) {
                    Some(b) => b.read().unwrap().clone(),
                    None => {
                        tracing::warn!("screencopy Copy: unknown buffer {}", buffer_id);
                        resource.failed();
                        return;
                    }
                };
                let (width, height, stride, ptr, size) = match &buffer_guard.buffer_type {
                    BufferType::Shm(shm) => {
                        let pool = match state.shm_pools.get_mut(&(client_id, shm.pool_id)) {
                            Some(p) => p,
                            None => {
                                tracing::warn!("screencopy Copy: unknown pool {}", shm.pool_id);
                                resource.failed();
                                return;
                            }
                        };
                        let base = match pool.map() {
                            Some(p) => p,
                            None => {
                                tracing::warn!("screencopy Copy: failed to map pool");
                                resource.failed();
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
                        tracing::warn!("screencopy Copy: buffer must be wl_shm, got {:?}", buffer_guard.buffer_type);
                        resource.failed();
                        return;
                    }
                };
                let capture_id = state.wlr.next_screencopy_id;
                state.wlr.next_screencopy_id = state.wlr.next_screencopy_id.wrapping_add(1);
                state.wlr.pending_screencopies.push(PendingScreencopy {
                    capture_id,
                    frame: resource.clone(),
                    width,
                    height,
                    stride,
                    ptr,
                    size,
                });
                tracing::debug!("screencopy Copy: queued capture {} ({}x{})", capture_id, width, height);
            }
            zwlr_screencopy_frame_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

/// Pop the first pending screencopy for platform to fulfill (does not remove; use complete_screencopy to remove)
pub fn get_pending_screencopy(state: &CompositorState) -> Option<(u64, *mut u8, u32, u32, u32, usize)> {
    state.wlr.pending_screencopies.first().map(|p| {
        (
            p.capture_id,
            p.ptr,
            p.width,
            p.height,
            p.stride,
            p.size,
        )
    })
}

/// Complete a screencopy capture (success): send frame.ready(), remove from pending
pub fn complete_screencopy(state: &mut CompositorState, capture_id: u64) -> bool {
    if let Some(pos) = state.wlr.pending_screencopies.iter().position(|p| p.capture_id == capture_id) {
        let pending = state.wlr.pending_screencopies.remove(pos);
        if pending.frame.is_alive() {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default();
            let tv_sec = now.as_secs();
            let tv_sec_hi = (tv_sec >> 32) as u32;
            let tv_sec_lo = (tv_sec & 0xFFFF_FFFF) as u32;
            let tv_nsec = now.subsec_nanos();
            // Protocol v3: flags event should be sent before ready. The wayland-protocols-wlr
            // generated API expects a Flags type that isn't publicly exported. Skipping flags
            // (0 = no y_invert). Most clients accept ready without it.
            pending.frame.ready(tv_sec_hi, tv_sec_lo, tv_nsec);
            tracing::debug!("screencopy complete: capture {} ready", capture_id);
        }
        true
    } else {
        false
    }
}

/// Fail a screencopy capture: send frame.failed(), remove from pending
pub fn fail_screencopy(state: &mut CompositorState, capture_id: u64) -> bool {
    if let Some(pos) = state.wlr.pending_screencopies.iter().position(|p| p.capture_id == capture_id) {
        let pending = state.wlr.pending_screencopies.remove(pos);
        if pending.frame.is_alive() {
            pending.frame.failed();
            tracing::debug!("screencopy failed: capture {}", capture_id);
        }
        true
    } else {
        false
    }
}

/// Register zwlr_screencopy_manager_v1 global
pub fn register_screencopy(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1, ()>(1, ())
}
