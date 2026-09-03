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

use std::os::fd::IntoRawFd;
use std::os::fd::RawFd;
use wayland_protocols::wp::linux_dmabuf::zv1::server::{
    zwp_linux_buffer_params_v1, zwp_linux_dmabuf_v1,
};
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;
use std::collections::{HashMap, HashSet};

/// Data stored with DMA-BUF buffer params
#[derive(Debug, Clone, Default)]
pub struct DmabufBufferParamsData {
    pub width: u32,
    pub height: u32,
    pub format: u32, // DRM fourcc format
    pub flags: u32,
    pub fds: Vec<i32>,
    pub plane_indices: Vec<u32>,
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
    pub used_params: HashSet<(wayland_server::backend::ClientId, u32)>,
}

// CoreFoundation/IOSurface bindings (Apple platforms only)
#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
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

const DRM_FORMAT_ARGB8888: u32 = 0x3432_5241;
const DRM_FORMAT_XRGB8888: u32 = 0x3432_5258;
const IOSURFACE_MODIFIER: u64 = 0x8000_0000_0000_0000;

#[cfg(target_vendor = "apple")]
#[link(name = "IOSurface", kind = "framework")]
extern "C" {
    fn IOSurfaceGetWidth(surface: *mut std::ffi::c_void) -> usize;
    fn IOSurfaceGetHeight(surface: *mut std::ffi::c_void) -> usize;
    fn IOSurfaceGetBytesPerRow(surface: *mut std::ffi::c_void) -> usize;
    fn IOSurfaceGetPixelFormat(surface: *mut std::ffi::c_void) -> u32;
}

struct ValidatedIOSurface {
    id: u32,
    #[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
    owner: std::sync::Arc<crate::core::surface::buffer::AppleIOSurfaceOwner>,
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
fn validate_iosurface_params(
    params: &DmabufBufferParamsData,
    width: i32,
    height: i32,
    format: u32,
) -> Option<ValidatedIOSurface> {
    if width <= 0
        || height <= 0
        || !matches!(format, DRM_FORMAT_ARGB8888 | DRM_FORMAT_XRGB8888)
        || params.fds.len() != 1
        || params.plane_indices.as_slice() != [0]
        || params.offsets.as_slice() != [0]
        || params.strides.len() != 1
        || params.modifiers.len() != 1
    {
        return None;
    }
    let modifier = params.modifiers[0];
    if modifier & IOSURFACE_MODIFIER == 0 {
        return None;
    }
    let encoded_id = modifier & !IOSURFACE_MODIFIER;
    if encoded_id == 0 || encoded_id > u32::MAX as u64 {
        return None;
    }
    let id = encoded_id as u32;
    let owner = crate::core::surface::buffer::retain_iosurface(id)?;
    let raw = owner.raw();
    let actual_width = unsafe { IOSurfaceGetWidth(raw) };
    let actual_height = unsafe { IOSurfaceGetHeight(raw) };
    let actual_stride = unsafe { IOSurfaceGetBytesPerRow(raw) };
    let actual_format = unsafe { IOSurfaceGetPixelFormat(raw) };
    if actual_width != width as usize
        || actual_height != height as usize
        || actual_stride != params.strides[0] as usize
        || actual_format != u32::from_be_bytes(*b"BGRA")
    {
        tracing::warn!(
            target: "wwn.dmabuf",
            id,
            width,
            height,
            actual_width,
            actual_height,
            stride = params.strides[0],
            actual_stride,
            actual_format = format_args!("0x{actual_format:08x}"),
            "IOSurface metadata does not match linux-dmabuf params"
        );
        return None;
    }
    Some(ValidatedIOSurface { id, owner })
}

#[cfg(any(not(target_vendor = "apple"), target_os = "watchos"))]
fn validate_iosurface_params(
    _params: &DmabufBufferParamsData,
    _width: i32,
    _height: i32,
    _format: u32,
) -> Option<ValidatedIOSurface> {
    None
}

fn make_iosurface_buffer(
    internal_id: u32,
    width: i32,
    height: i32,
    format: u32,
    resource: wayland_server::protocol::wl_buffer::WlBuffer,
    validated: ValidatedIOSurface,
) -> crate::core::surface::buffer::Buffer {
    use crate::core::surface::buffer::{Buffer, BufferType, NativeBufferData};
    let buffer = Buffer::new(
        internal_id,
        BufferType::Native(NativeBufferData {
            id: validated.id as u64,
            width,
            height,
            format,
        }),
        Some(resource),
    );
    #[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
    let buffer = buffer.with_native_iosurface(validated.owner);
    buffer
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
        let dmabuf = data_init.init(resource, ());

        #[cfg(not(target_os = "watchos"))]
        {
            // Advertise the IOSurface-modifier convention (#86 / wwn-iland + waypipe).
            // High bit set = IOSurface id in low 63 bits. Do NOT advertise LINEAR
            // (raw dmabuf). That path is unsupported and caused client failures.
            let mod_hi = ((IOSURFACE_MODIFIER >> 32) & 0xffff_ffff) as u32;
            let mod_lo = (IOSURFACE_MODIFIER & 0xffff_ffff) as u32;
            if dmabuf.version() >= 3 {
                dmabuf.modifier(DRM_FORMAT_ARGB8888, mod_hi, mod_lo);
                dmabuf.modifier(DRM_FORMAT_XRGB8888, mod_hi, mod_lo);
            } else {
                dmabuf.format(DRM_FORMAT_ARGB8888);
                dmabuf.format(DRM_FORMAT_XRGB8888);
            }
            tracing::info!(
                "linux-dmabuf bound: advertised IOSurface modifiers for ARGB8888/XRGB8888"
            );
        }
        #[cfg(target_os = "watchos")]
        tracing::info!("linux-dmabuf bound without formats: watchOS has no IOSurface framework");
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
                let _: zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1 =
                    data_init.init(params_id, params);
            }
            zwp_linux_dmabuf_v1::Request::GetDefaultFeedback { id } => {
                let feedback = data_init.init(id, ());
                send_iosurface_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::GetSurfaceFeedback { id, surface: _ } => {
                let feedback = data_init.init(id, ());
                send_iosurface_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

use wayland_protocols::wp::linux_dmabuf::zv1::server::zwp_linux_dmabuf_feedback_v1;

/// Advertise IOSurface-modifier dmabuf formats (v4 feedback). Clients waiting
/// on `done` proceed immediately. Do not advertise LINEAR (raw dmabuf): that
/// path is unsupported and caused client failures.
fn send_iosurface_dmabuf_feedback(
    feedback: &zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1,
) {
    use std::io::Write;
    use std::os::fd::AsFd;

    const FORMATS: [u32; 2] = [DRM_FORMAT_ARGB8888, DRM_FORMAT_XRGB8888];

    match tempfile::tempfile() {
        Ok(mut file) => {
            for fmt in FORMATS {
                let mut rec = [0u8; 16];
                rec[0..4].copy_from_slice(&fmt.to_le_bytes());
                rec[8..16].copy_from_slice(&IOSURFACE_MODIFIER.to_le_bytes());
                if file.write_all(&rec).is_err() {
                    tracing::warn!("linux-dmabuf: failed to write format table");
                    feedback.format_table(file.as_fd(), 0);
                    feedback.main_device(Vec::new());
                    feedback.done();
                    return;
                }
            }
            let _ = file.flush();
            let table_size = (FORMATS.len() * 16) as u32;
            feedback.format_table(file.as_fd(), table_size);

            // No DRM render node on Wawona hosts. 8 zero bytes so the tranche
            // still names a device; clients that require a real node fall back.
            let dummy_dev = vec![0u8; 8];
            feedback.main_device(dummy_dev.clone());
            feedback.tranche_target_device(dummy_dev);
            let mut indices = Vec::with_capacity(FORMATS.len() * 2);
            for i in 0u16..(FORMATS.len() as u16) {
                indices.extend_from_slice(&i.to_le_bytes());
            }
            feedback.tranche_formats(indices);
            feedback.tranche_done();
            feedback.done();
        }
        Err(e) => {
            tracing::warn!("linux-dmabuf: failed to create format table: {}", e);
            feedback.main_device(Vec::new());
            feedback.done();
        }
    }
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

impl Dispatch<zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1, BufferParams>
    for CompositorState
{
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
            zwp_linux_buffer_params_v1::Request::Add {
                fd,
                plane_idx,
                offset,
                stride,
                modifier_hi,
                modifier_lo,
            } => {
                let modifier = ((modifier_hi as u64) << 32) | (modifier_lo as u64);
                tracing::debug!(
                    "linux-dmabuf: Received plane {} (modifier=0x{:016x})",
                    plane_idx,
                    modifier
                );

                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                let key = (client_id.clone(), params_id);
                // Store FD by converting to raw (we own it now).
                let raw_fd = fd.into_raw_fd();
                if state.ext.linux_dmabuf.used_params.contains(&key) {
                    unsafe { libc::close(raw_fd) };
                    resource.failed();
                    return;
                }
                let p = state
                    .ext
                    .linux_dmabuf
                    .pending_params
                    .entry(key)
                    .or_default();

                if stride == 0 || p.plane_indices.contains(&plane_idx) {
                    unsafe {
                        libc::close(raw_fd);
                    }
                    resource.failed();
                    return;
                }
                p.fds.push(raw_fd);
                p.plane_indices.push(plane_idx);
                p.offsets.push(offset);
                p.strides.push(stride);
                p.modifiers.push(modifier);
            }
            zwp_linux_buffer_params_v1::Request::Create {
                width,
                height,
                format,
                flags: _,
            } => {
                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                let key = (client_id.clone(), params_id);
                if !state.ext.linux_dmabuf.used_params.insert(key.clone()) {
                    resource.failed();
                    return;
                }
                if let Some(p) = state.ext.linux_dmabuf.pending_params.remove(&key) {
                    let validated = validate_iosurface_params(&p, width, height, format);
                    close_raw_fds(&p.fds);
                    let Some(validated) = validated else {
                        tracing::warn!(
                            target: "wwn.dmabuf",
                            width,
                            height,
                            format = format_args!("0x{format:08x}"),
                            "create rejected invalid IOSurface dmabuf"
                        );
                        resource.failed();
                        return;
                    };
                    use wayland_server::protocol::wl_buffer::WlBuffer;
                    let Ok(buffer_resource) =
                        _client.create_resource::<WlBuffer, (), CompositorState>(_dhandle, 1, ())
                    else {
                        resource.failed();
                        return;
                    };
                    let internal_id = buffer_resource.id().protocol_id();
                    let backing_id = validated.id;
                    let buffer = make_iosurface_buffer(
                        internal_id,
                        width,
                        height,
                        format,
                        buffer_resource.clone(),
                        validated,
                    );
                    state.buffers.insert(
                        (client_id, internal_id),
                        std::sync::Arc::new(std::sync::RwLock::new(buffer)),
                    );
                    resource.created(&buffer_resource);
                    tracing::info!(
                        target: "wwn.dmabuf",
                        op = "create",
                        internal_id,
                        backing_id,
                        width,
                        height,
                        copy = "zero",
                        "imported retained IOSurface"
                    );
                } else {
                    resource.failed();
                }
            }
            zwp_linux_buffer_params_v1::Request::CreateImmed {
                buffer_id,
                width,
                height,
                format,
                flags: _,
            } => {
                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                let key = (client_id.clone(), params_id);
                if !state.ext.linux_dmabuf.used_params.insert(key.clone()) {
                    resource.failed();
                    return;
                }
                if let Some(p) = state.ext.linux_dmabuf.pending_params.remove(&key) {
                    let validated = validate_iosurface_params(&p, width, height, format);
                    close_raw_fds(&p.fds);
                    let Some(validated) = validated else {
                        tracing::warn!(
                            target: "wwn.dmabuf",
                            width,
                            height,
                            format = format_args!("0x{format:08x}"),
                            "create_immed rejected invalid IOSurface dmabuf"
                        );
                        resource.failed();
                        return;
                    };
                    let buffer_resource = data_init.init(buffer_id, ());
                    let internal_id = buffer_resource.id().protocol_id();
                    let backing_id = validated.id;
                    let buffer = make_iosurface_buffer(
                        internal_id,
                        width,
                        height,
                        format,
                        buffer_resource,
                        validated,
                    );
                    state.buffers.insert(
                        (client_id, internal_id),
                        std::sync::Arc::new(std::sync::RwLock::new(buffer)),
                    );
                    tracing::info!(
                        target: "wwn.dmabuf",
                        op = "create_immed",
                        internal_id,
                        backing_id,
                        width,
                        height,
                        copy = "zero",
                        "imported retained IOSurface"
                    );
                } else {
                    resource.failed();
                }
            }
            zwp_linux_buffer_params_v1::Request::Destroy => {
                let key = (_client.id(), resource.id().protocol_id());
                if let Some(params) = state.ext.linux_dmabuf.pending_params.remove(&key) {
                    close_raw_fds(&params.fds);
                }
                state.ext.linux_dmabuf.used_params.remove(&key);
            }
            _ => {}
        }
    }

    fn destroyed(
        state: &mut Self,
        client_id: wayland_server::backend::ClientId,
        resource: &zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1,
        _data: &BufferParams,
    ) {
        let key = (client_id, resource.id().protocol_id());
        if let Some(params) = state.ext.linux_dmabuf.pending_params.remove(&key) {
            close_raw_fds(&params.fds);
        }
        state.ext.linux_dmabuf.used_params.remove(&key);
    }
}

/// Register zwp_linux_dmabuf_v1 global
pub fn register_linux_dmabuf(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()>(4, ())
}
