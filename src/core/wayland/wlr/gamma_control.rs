//! zwlr_gamma_control_manager_v1. Gamma table adjustment (night light, redshift).
//! Platform applies via CGSetDisplayTransferByTable on macOS.

use std::os::unix::io::AsRawFd;

use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::{CompositorState, GammaRampApply};
use crate::core::wayland::protocol::wlroots::wlr_gamma_control_unstable_v1::{
    zwlr_gamma_control_manager_v1, zwlr_gamma_control_v1,
};

const GAMMA_SIZE: u32 = 256;

fn output_id_from_wl_output(state: &CompositorState, _output: &wayland_server::protocol::wl_output::WlOutput) -> u32 {
    state.outputs.first().map(|o| o.id).unwrap_or(0)
}

impl GlobalDispatch<zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        client: &wayland_server::Client,
        _resource: &zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1,
        request: zwlr_gamma_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_gamma_control_manager_v1::Request::GetGammaControl { id, output } => {
                let output_id = output_id_from_wl_output(state, &output);
                if state.wlr.gamma_control.active_controls.contains_key(&output_id) {
                    let control: zwlr_gamma_control_v1::ZwlrGammaControlV1 =
                        data_init.init(id, output_id);
                    control.failed();
                    tracing::warn!("Gamma control: output {} already has control", output_id);
                    return;
                }
                let control: zwlr_gamma_control_v1::ZwlrGammaControlV1 =
                    data_init.init(id, output_id);
                let client_id = client.id();
                state.wlr.gamma_control.active_controls
                    .insert(output_id, (control.id().protocol_id(), client_id));
                control.gamma_size(GAMMA_SIZE);
                tracing::debug!("Gamma control: created for output {}", output_id);
            }
            zwlr_gamma_control_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<zwlr_gamma_control_v1::ZwlrGammaControlV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_gamma_control_v1::ZwlrGammaControlV1,
        request: zwlr_gamma_control_v1::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let output_id = *data;
        match request {
            zwlr_gamma_control_v1::Request::SetGamma { fd } => {
                let size = GAMMA_SIZE as usize;
                let expected_len = size * 3 * 2;
                let mut bytes = vec![0u8; expected_len];
                let raw_fd = fd.as_raw_fd();
                let n = unsafe { libc::read(raw_fd, bytes.as_mut_ptr() as *mut libc::c_void, expected_len) };
                if n != expected_len as isize {
                    tracing::warn!("Gamma control SetGamma: read failed (got {} expected {})", n, expected_len);
                    resource.failed();
                    return;
                }
                let mut red = vec![0u16; size];
                let mut green = vec![0u16; size];
                let mut blue = vec![0u16; size];
                for i in 0..size {
                    let off = i * 2;
                    red[i] = u16::from_le_bytes([bytes[off], bytes[off + 1]]);
                    green[i] = u16::from_le_bytes([bytes[off + size * 2], bytes[off + size * 2 + 1]]);
                    blue[i] = u16::from_le_bytes([bytes[off + size * 4], bytes[off + size * 4 + 1]]);
                }
                state.wlr.gamma_control.pending_apply = Some(GammaRampApply {
                    output_id,
                    size: GAMMA_SIZE,
                    red,
                    green,
                    blue,
                });
                tracing::debug!("Gamma control: queued apply for output {}", output_id);
            }
            zwlr_gamma_control_v1::Request::Destroy => {
                state.wlr.gamma_control.active_controls.remove(&output_id);
                state.wlr.gamma_control.pending_restore = Some(output_id);
                tracing::debug!("Gamma control: queued restore for output {}", output_id);
            }
            _ => {}
        }
    }
}

/// Pop pending gamma apply for platform to apply (CGSetDisplayTransferByTable on macOS)
pub fn pop_pending_gamma_apply(state: &mut CompositorState) -> Option<GammaRampApply> {
    state.wlr.gamma_control.pending_apply.take()
}

/// Pop pending gamma restore for platform to restore original tables
pub fn pop_pending_gamma_restore(state: &mut CompositorState) -> Option<u32> {
    state.wlr.gamma_control.pending_restore.take()
}

/// Register zwlr_gamma_control_manager_v1 global
pub fn register_gamma_control(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1, ()>(1, ())
}
