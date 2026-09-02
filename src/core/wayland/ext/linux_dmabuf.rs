//! Linux DMABuf Protocol Implementation (`zwp_linux_dmabuf_v1`)
//!
//! OS import switch (see `docs/linux-dmabuf-zero-copy.md`):
//! - Apple (except watchOS): high-bit modifier = IOSurface id (`NativeBufferData`)
//! - Android: same high-bit = AHardwareBuffer id (`NativeBufferData`)
//! - Linux: LINEAR + real modifiers; store as `BufferType::DmaBuf`
//! - watchOS: global is **not** registered
//!
//! Never advertise `DRM_FORMAT_MOD_LINEAR` on Apple or Android.
//! Structured logs use target `wwn.dmabuf` with fields op/os/sink/modifier/
//! backing_id/format/copy/client.

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

/// High bit set: IOSurface (Apple) or AHB (Android) id in low 63 bits.
pub const PLATFORM_NATIVE_MODIFIER: u64 = 0x8000_0000_0000_0000;
pub const DRM_FORMAT_ARGB8888: u32 = 0x34325241; // 'AR24'
pub const DRM_FORMAT_XRGB8888: u32 = 0x34325258; // 'XR24'
pub const DRM_FORMAT_MOD_LINEAR: u64 = 0;

#[derive(Debug, Clone, Default)]
pub struct DmabufBufferParamsData {
    pub width: u32,
    pub height: u32,
    pub format: u32,
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

fn is_platform_native_modifier(modifier: u64) -> bool {
    (modifier & PLATFORM_NATIVE_MODIFIER) != 0
}

fn native_backing_id(modifier: u64) -> u64 {
    modifier & 0x7FFF_FFFF_FFFF_FFFF
}

/// Host label for structured `wwn.dmabuf` logs.
fn dmabuf_os_label() -> &'static str {
    #[cfg(target_os = "android")]
    {
        "android"
    }
    #[cfg(all(target_vendor = "apple", not(target_os = "android")))]
    {
        "apple"
    }
    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    {
        "linux"
    }
}

fn dmabuf_sink_label() -> &'static str {
    #[cfg(target_os = "android")]
    {
        "ahb_surface"
    }
    #[cfg(all(target_vendor = "apple", not(target_os = "android")))]
    {
        "apple_metal"
    }
    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    {
        "linux_gbm"
    }
}

fn advertise_formats(dmabuf: &zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1) {
    #[cfg(any(target_vendor = "apple", target_os = "android"))]
    {
        let mod_hi = ((PLATFORM_NATIVE_MODIFIER >> 32) & 0xffff_ffff) as u32;
        let mod_lo = (PLATFORM_NATIVE_MODIFIER & 0xffff_ffff) as u32;
        if dmabuf.version() >= 3 {
            dmabuf.modifier(DRM_FORMAT_ARGB8888, mod_hi, mod_lo);
            dmabuf.modifier(DRM_FORMAT_XRGB8888, mod_hi, mod_lo);
        } else {
            dmabuf.format(DRM_FORMAT_ARGB8888);
            dmabuf.format(DRM_FORMAT_XRGB8888);
        }
        tracing::info!(
            target: "wwn.dmabuf",
            op = "modifier_ad",
            os = dmabuf_os_label(),
            sink = dmabuf_sink_label(),
            modifier = format!("0x{PLATFORM_NATIVE_MODIFIER:016x}"),
            copy = "zero",
            "advertised platform-native modifiers for ARGB8888/XRGB8888"
        );
    }
    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    {
        let mod_hi = ((DRM_FORMAT_MOD_LINEAR >> 32) & 0xffff_ffff) as u32;
        let mod_lo = (DRM_FORMAT_MOD_LINEAR & 0xffff_ffff) as u32;
        if dmabuf.version() >= 3 {
            dmabuf.modifier(DRM_FORMAT_ARGB8888, mod_hi, mod_lo);
            dmabuf.modifier(DRM_FORMAT_XRGB8888, mod_hi, mod_lo);
        } else {
            dmabuf.format(DRM_FORMAT_ARGB8888);
            dmabuf.format(DRM_FORMAT_XRGB8888);
        }
        tracing::info!(
            target: "wwn.dmabuf",
            op = "modifier_ad",
            os = "linux",
            sink = "linux_gbm",
            modifier = format!("0x{DRM_FORMAT_MOD_LINEAR:016x}"),
            copy = "zero",
            "advertised LINEAR modifiers for ARGB8888/XRGB8888"
        );
    }
}

fn send_dmabuf_feedback(
    feedback: &zwp_linux_dmabuf_feedback_v1::ZwpLinuxDmabufFeedbackV1,
) {
    use std::io::Write;
    use std::os::fd::AsFd;

    const FORMATS: [u32; 2] = [DRM_FORMAT_ARGB8888, DRM_FORMAT_XRGB8888];

    #[cfg(any(target_vendor = "apple", target_os = "android"))]
    let table_modifier = PLATFORM_NATIVE_MODIFIER;
    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    let table_modifier = DRM_FORMAT_MOD_LINEAR;

    match tempfile::tempfile() {
        Ok(mut file) => {
            for fmt in FORMATS {
                let mut rec = [0u8; 16];
                rec[0..4].copy_from_slice(&fmt.to_le_bytes());
                rec[8..16].copy_from_slice(&table_modifier.to_le_bytes());
                if file.write_all(&rec).is_err() {
                    tracing::warn!(target: "wwn.dmabuf", op = "feedback", "failed to write format table");
                    feedback.format_table(file.as_fd(), 0);
                    feedback.main_device(Vec::new());
                    feedback.done();
                    return;
                }
            }
            let _ = file.flush();
            let table_size = (FORMATS.len() * 16) as u32;
            feedback.format_table(file.as_fd(), table_size);

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
            tracing::info!(
                target: "wwn.dmabuf",
                op = "feedback",
                os = dmabuf_os_label(),
                sink = dmabuf_sink_label(),
                modifier = format!("0x{table_modifier:016x}"),
                copy = "zero",
                "dmabuf feedback done"
            );
        }
        Err(e) => {
            tracing::warn!(target: "wwn.dmabuf", op = "feedback", error = %e, "failed to create format table");
            feedback.main_device(Vec::new());
            feedback.done();
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
        let dmabuf = data_init.init(resource, ());
        tracing::info!(
            target: "wwn.dmabuf",
            op = "bind",
            os = dmabuf_os_label(),
            sink = dmabuf_sink_label(),
            version = dmabuf.version(),
            "linux-dmabuf bound"
        );
        advertise_formats(&dmabuf);
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
                send_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::GetSurfaceFeedback { id, surface: _ } => {
                let feedback = data_init.init(id, ());
                send_dmabuf_feedback(&feedback);
            }
            zwp_linux_dmabuf_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

use wayland_protocols::wp::linux_dmabuf::zv1::server::zwp_linux_dmabuf_feedback_v1;

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

/// Import path after planes are collected. Returns true if a wl_buffer was created.
fn import_dmabuf_planes(
    state: &mut CompositorState,
    client: &wayland_server::Client,
    dhandle: &DisplayHandle,
    p: DmabufBufferParamsData,
    width: i32,
    height: i32,
    format: u32,
    immed: Option<(
        wayland_server::New<wayland_server::protocol::wl_buffer::WlBuffer>,
        &mut wayland_server::DataInit<'_, CompositorState>,
    )>,
    created_out: Option<&zwp_linux_buffer_params_v1::ZwpLinuxBufferParamsV1>,
) -> bool {
    use crate::core::surface::buffer::{Buffer, BufferType, NativeBufferData};
    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    use crate::core::surface::buffer::DmaBufData;
    use wayland_server::protocol::wl_buffer::WlBuffer;

    let modifier = p.modifiers.first().copied().unwrap_or(0);
    let client_id = client.id();

    #[cfg(any(target_vendor = "apple", target_os = "android"))]
    {
        if !is_platform_native_modifier(modifier) {
            tracing::warn!(
                target: "wwn.dmabuf",
                op = "create",
                os = dmabuf_os_label(),
                sink = dmabuf_sink_label(),
                modifier = format!("0x{modifier:016x}"),
                format,
                copy = "cpu",
                "rejecting non-native modifier on this OS"
            );
            close_raw_fds(&p.fds);
            return false;
        }
        let backing_id = native_backing_id(modifier);
        tracing::info!(
            target: "wwn.dmabuf",
            op = if immed.is_some() { "create_immed" } else { "create" },
            os = dmabuf_os_label(),
            sink = dmabuf_sink_label(),
            modifier = format!("0x{modifier:016x}"),
            backing_id,
            format,
            copy = "zero",
            "importing platform-native buffer"
        );

        let buffer_resource = if let Some((buffer_id, data_init)) = immed {
            data_init.init(buffer_id, ())
        } else {
            let buffer_resource = client
                .create_resource::<WlBuffer, (), CompositorState>(dhandle, 1, ())
                .expect("Failed to create wl_buffer resource");
            if let Some(params) = created_out {
                params.created(&buffer_resource);
            }
            buffer_resource
        };
        let internal_id = buffer_resource.id().protocol_id();
        let buffer = Buffer::new(
            internal_id,
            BufferType::Native(NativeBufferData {
                id: backing_id,
                width,
                height,
                format,
            }),
            Some(buffer_resource),
        );
        state
            .buffers
            .insert((client_id, internal_id), std::sync::Arc::new(std::sync::RwLock::new(buffer)));
        close_raw_fds(&p.fds);
        return true;
    }

    #[cfg(all(not(target_vendor = "apple"), not(target_os = "android")))]
    {
        // Linux: accept LINEAR and any modifier; keep fds in DmaBufData for GBM present.
        tracing::info!(
            target: "wwn.dmabuf",
            op = if immed.is_some() { "create_immed" } else { "create" },
            os = "linux",
            sink = "linux_gbm",
            modifier = format!("0x{modifier:016x}"),
            backing_id = p.fds.first().copied().unwrap_or(-1),
            format,
            copy = "zero",
            "importing linux dmabuf planes"
        );

        let buffer_resource = if let Some((buffer_id, data_init)) = immed {
            data_init.init(buffer_id, ())
        } else {
            let buffer_resource = client
                .create_resource::<WlBuffer, (), CompositorState>(dhandle, 1, ())
                .expect("Failed to create wl_buffer resource");
            if let Some(params) = created_out {
                params.created(&buffer_resource);
            }
            buffer_resource
        };
        let internal_id = buffer_resource.id().protocol_id();
        let buffer = Buffer::new(
            internal_id,
            BufferType::DmaBuf(DmaBufData {
                width: width as u32,
                height: height as u32,
                format,
                modifier,
                fds: p.fds.clone(),
                offsets: p.offsets.clone(),
                strides: p.strides.clone(),
            }),
            Some(buffer_resource),
        );
        state
            .buffers
            .insert((client_id, internal_id), std::sync::Arc::new(std::sync::RwLock::new(buffer)));
        // fds are owned by DmaBufData now; do not close.
        let _ = p;
        return true;
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
                    target: "wwn.dmabuf",
                    op = "add_plane",
                    plane_idx,
                    modifier = format!("0x{modifier:016x}"),
                    stride,
                    "received plane"
                );

                let params_id = resource.id().protocol_id();
                let client_id = _client.id();
                let p = state
                    .ext
                    .linux_dmabuf
                    .pending_params
                    .entry((client_id, params_id))
                    .or_default();

                let raw_fd = fd.into_raw_fd();
                if stride == 0 {
                    unsafe {
                        libc::close(raw_fd);
                    }
                    resource.failed();
                    return;
                }
                p.fds.push(raw_fd);
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
                if let Some(p) = state
                    .ext
                    .linux_dmabuf
                    .pending_params
                    .remove(&(client_id, params_id))
                {
                    if p.fds.is_empty() || width <= 0 || height <= 0 {
                        close_raw_fds(&p.fds);
                        resource.failed();
                        return;
                    }
                    if !import_dmabuf_planes(
                        state,
                        _client,
                        _dhandle,
                        p,
                        width,
                        height,
                        format,
                        None,
                        Some(resource),
                    ) {
                        resource.failed();
                    }
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
                if let Some(p) = state
                    .ext
                    .linux_dmabuf
                    .pending_params
                    .remove(&(client_id, params_id))
                {
                    if p.fds.is_empty() || width <= 0 || height <= 0 {
                        close_raw_fds(&p.fds);
                        resource.failed();
                        return;
                    }
                    if !import_dmabuf_planes(
                        state,
                        _client,
                        _dhandle,
                        p,
                        width,
                        height,
                        format,
                        Some((buffer_id, data_init)),
                        None,
                    ) {
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

/// Whether this host should advertise `zwp_linux_dmabuf_v1`.
/// watchOS uses SpriteKit of `wl_shm` only; nested niri checks this via absence.
pub fn host_offers_linux_dmabuf() -> bool {
    #[cfg(target_os = "watchos")]
    {
        false
    }
    #[cfg(not(target_os = "watchos"))]
    {
        true
    }
}

/// Register zwp_linux_dmabuf_v1 global (newest practical stable: v4).
/// No-op on watchOS.
pub fn register_linux_dmabuf(display: &DisplayHandle) -> Option<wayland_server::backend::GlobalId> {
    if !host_offers_linux_dmabuf() {
        tracing::info!(
            target: "wwn.dmabuf",
            op = "bind",
            os = "watchos",
            sink = "watch_spritekit",
            "skipping linux-dmabuf global on watchOS"
        );
        return None;
    }
    Some(display.create_global::<CompositorState, zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1, ()>(4, ()))
}
