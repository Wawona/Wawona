//! Linux DMABuf Protocol Implementation
//!
//! This module provides the linux-dmabuf protocol implementation for Wawona.
//! 
//! # How It Works
//!
//! On macOS, DMABUF handling is delegated to waypipe which uses kosmickrisp
//! (Vulkan-on-Metal driver) to import/export GPU buffers. kosmickrisp supports
//! `VK_EXT_external_memory_dma_buf` for cross-process buffer sharing.
//!
//! The Wawona compositor advertises linux-dmabuf formats so that:
//! - waypipe can intercept and handle DMABUF requests via Vulkan
//! - Clients know that DMABUF is available (handled by waypipe)
//!
//! # Nested Compositors (Weston, etc.)
//!
//! Nested compositors like Weston can run through waypipe with full GPU
//! acceleration. waypipe handles the DMABUF protocol via Vulkan/kosmickrisp.
//!
//! # Buffer Flow
//!
//! 1. Remote client creates DMABUF buffer
//! 2. waypipe-server intercepts and sends buffer data to waypipe-client
//! 3. waypipe-client uses kosmickrisp Vulkan to import the buffer
//! 4. Buffer is rendered via Metal on macOS

use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};
use wayland_protocols::wp::linux_dmabuf::zv1::server::{
    zwp_linux_dmabuf_v1, zwp_linux_buffer_params_v1,
};
use std::os::fd::IntoRawFd;
use std::os::fd::RawFd;

use crate::core::state::CompositorState;
use std::collections::HashMap;

/// Data stored with DMA-BUF buffer params
#[derive(Debug, Clone, Default)]
pub struct DmabufBufferParamsData {
    pub width: u32,
    pub height: u32,
    pub format: u32, // DRM fourcc format
    pub flags: u32,
    pub fds: Vec<i32>,
    pub offsets: Vec<u32>,
    pub strides: Vec<u32>,
    pub modifiers: Vec<u64>,
}

impl DmabufBufferParamsData {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Debug, Default)]
pub struct LinuxDmabufState {
    pub pending_params: HashMap<(wayland_server::backend::ClientId, u32), DmabufBufferParamsData>,
}


// CoreFoundation/IOSurface bindings (Apple platforms only)
#[cfg(target_vendor = "apple")]
#[link(name = "IOSurface", kind = "framework")]
extern "C" {}

/// Buffer parameters state (User data for zwp_linux_buffer_params_v1)
pub struct BufferParams {
    pub width: i32,
    pub height: i32,
    pub format: u32,
    pub flags: u32,
    pub planes: Vec<Plane>,
}

#[derive(Clone, Copy)]
pub struct Plane {
    pub fd: std::os::unix::io::RawFd,
    pub plane_idx: u32,
    pub offset: u32,
    pub stride: u32,
    pub modifier: u64,
}

fn close_raw_fds(fds: &[RawFd]) {
    for fd in fds {
        // Safety: fds are owned by the compositor after `into_raw_fd`.
        unsafe {
            libc::close(*fd);
        }
    }
}

impl GlobalDispatch<zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let _dmabuf = data_init.init(resource, ());

        // Advertisement honesty: raw (LINEAR-modifier) dmabuf import is not
        // supported on any Wawona platform — only the IOSurface-modifier
        // convention used by wwn-waypipe (negotiated out-of-band). Sending
        // format/modifier events here made generic clients attempt raw
        // dmabuf and fail at create(); advertise nothing so they fall back
        // to wl_shm. waypipe's IOSurface path does not depend on these
        // events.
        tracing::debug!(
            "linux-dmabuf bound: no raw formats advertised (IOSurface-only import)"
        );
    }
}

impl Dispatch<zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1,
        request: zwp_linux_dmabuf_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwp_linux_dmabuf_v1::Request::CreateParams { params_id } => {
                let params = BufferParams {
                    width: 0,
                    height: 0,
                    format: 0,
                    flags: 0,
                    planes: Vec::new(),
                };
                let _: zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1 = data_init.init(params_id, params);
            }
            zwp_linux_dmabuf_v1::Request::GetDefaultFeedback { id } => {
                let feedback = data_init.init(id, ());
                send_empty_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::GetSurfaceFeedback { id, surface: _ } => {
                let feedback = data_init.init(id, ());
                send_empty_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

use wayland_protocols::wp::linux_dmabuf::zv1::server::zwp_linux_dmabuf_feedback_v1;

/// Send a complete (v4) feedback sequence describing zero renderable dmabuf
/// formats. Clients waiting on `done` proceed immediately and fall back to
/// wl_shm instead of stalling on a feedback object that never resolves.
fn send_empty_dmabuf_feedback(
    feedback: &zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1,
) {
    use std::os::fd::AsFd;
    match tempfile::tempfile() {
        Ok(file) => {
            feedback.format_table(file.as_fd(), 0);
        }
        Err(e) => {
            tracing::warn!("linux-dmabuf: failed to create empty format table: {}", e);
        }
    }
    // No main device: there is no DRM render node on Wawona hosts.
    feedback.main_device(Vec::new());
    feedback.done();
}

impl Dispatch<zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1,
        request: zwp_linux_dmabuf_feedback_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwp_linux_dmabuf_feedback_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1, BufferParams> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1,
        request: zwp_linux_buffer_params_v1::Request,
        _params: &BufferParams,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwp_linux_buffer_params_v1::Request::Add { fd, plane_idx, offset, stride, modifier_hi, modifier_lo } => {
                let modifier = ((modifier_hi as u64) << 32) | (modifier_lo as u64);
                tracing::debug!("linux-dmabuf: Received plane {} (modifier=0x{:016x})", plane_idx, modifier);
                
                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                let p = state.ext.linux_dmabuf.pending_params.entry((client_id, params_id)).or_default();
                
                // Store FD by converting to raw (we own it now)
                let raw_fd = fd.into_raw_fd();
                if stride == 0 {
                    unsafe { libc::close(raw_fd); }
                    resource.failed();
                    return;
                }
                p.fds.push(raw_fd);
                p.offsets.push(offset);
                p.strides.push(stride);
                p.modifiers.push(modifier);
            }
            zwp_linux_buffer_params_v1::Request::Create { width, height, format, flags: _ } => {
                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                if let Some(p) = state.ext.linux_dmabuf.pending_params.remove(&(client_id.clone(), params_id)) {
                    if p.fds.is_empty() || width <= 0 || height <= 0 {
                        close_raw_fds(&p.fds);
                        resource.failed();
                        return;
                    }
                    let modifier = p.modifiers.first().copied().unwrap_or(0);

                    let is_iosurface = (modifier & 0x8000_0000_0000_0000) != 0;
                    if is_iosurface {
                        let surface_id = (modifier & 0x7FFF_FFFF_FFFF_FFFF) as u32;
                        tracing::info!("linux-dmabuf: Importing IOSurface ID {} (Asynchronous) from modifier 0x{:016x}", surface_id, modifier);

                        use crate::core::surface::buffer::{Buffer, BufferType, NativeBufferData};
                        use wayland_server::Resource;
                        use wayland_server::protocol::wl_buffer::WlBuffer;
                        
                        // Manually create the wl_buffer resource since 'created' event creates it
                        let buffer_resource = _client.create_resource::<WlBuffer, (), CompositorState>(
                            _dhandle,
                            1,
                            (),
                        ).expect("Failed to create wl_buffer resource");

                        // Emit 'created' event with the new resource
                        resource.created(&buffer_resource);
                        
                        let internal_id = buffer_resource.id().protocol_id();

                        let buffer = Buffer::new(
                            internal_id,
                            BufferType::Native(NativeBufferData {
                                id: surface_id as u64,
                                width,
                                height,
                                format,
                            }),
                            Some(buffer_resource.clone())
                        );

                        state.buffers.insert((client_id, internal_id), std::sync::Arc::new(std::sync::RwLock::new(buffer)));
                        close_raw_fds(&p.fds);
                    } else {
                        close_raw_fds(&p.fds);
                        resource.failed();
                    }
                } else {
                    resource.failed();
                }
            }
            zwp_linux_buffer_params_v1::Request::CreateImmed { buffer_id, width, height, format, flags: _ } => {
               
                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                if let Some(p) = state.ext.linux_dmabuf.pending_params.remove(&(client_id.clone(), params_id)) {
                     if p.fds.is_empty() || width <= 0 || height <= 0 {
                         close_raw_fds(&p.fds);
                         resource.failed();
                         return;
                     }
                     let modifier = p.modifiers.first().copied().unwrap_or(0);

                     let is_iosurface = (modifier & 0x8000_0000_0000_0000) != 0;
                     if is_iosurface {
                         let surface_id = (modifier & 0x7FFF_FFFF_FFFF_FFFF) as u32;
                         tracing::info!("linux-dmabuf: Importing IOSurface ID {} (Immediate) from modifier 0x{:016x}", surface_id, modifier);
                         
                         // Create the buffer stored in CompositorState
                         use crate::core::surface::buffer::{Buffer, BufferType, NativeBufferData};
                         use wayland_server::Resource;
                         
                         let buffer_resource = data_init.init(buffer_id, ());
                         let internal_id = buffer_resource.id().protocol_id();
                         
                         let buffer = Buffer::new(
                             internal_id,
                             BufferType::Native(NativeBufferData {
                                 id: surface_id as u64,
                                 width,
                                 height,
                                 format,
                             }),
                             Some(buffer_resource.clone())
                         );
                         
                         state.buffers.insert((client_id, internal_id), std::sync::Arc::new(std::sync::RwLock::new(buffer)));
                         close_raw_fds(&p.fds);
                         
                         // Note: We don't send 'created' event for CreateImmed.
                     } else {
                         close_raw_fds(&p.fds);
                         resource.failed();
                     }
                } else {
                    resource.failed();
                }
            }
            zwp_linux_buffer_params_v1::Request::Destroy => {}
            _ => {}
        }
    }
}


/// Register zwp_linux_dmabuf_v1 global
pub fn register_linux_dmabuf(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()>(4, ())
}
