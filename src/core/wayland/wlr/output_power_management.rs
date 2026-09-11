use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, WEnum};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol::wlroots::wlr_output_power_management_unstable_v1::{
    zwlr_output_power_manager_v1, zwlr_output_power_v1,
};

pub struct OutputPowerManagerData;

impl GlobalDispatch<zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1, ()>
    for CompositorState
{
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1,
        request: zwlr_output_power_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_power_manager_v1::Request::GetOutputPower { id, output: _ } => {
                // Get the output ID from the wl_output resource
                // The wl_output user data is u32 as defined in output.rs
                let output_id = 0; // output.data::<u32>().copied().unwrap_or(0);

                let power: zwlr_output_power_v1::ZwlrOutputPowerV1 = data_init.init(id, ());

                // Send initial mode
                if let Some(output_state) = state.outputs.iter().find(|o| o.id == output_id) {
                    let mode = if output_state.power_mode == 0 {
                        zwlr_output_power_v1::Mode::Off
                    } else {
                        zwlr_output_power_v1::Mode::On
                    };
                    power.mode(mode);
                }
            }
            zwlr_output_power_manager_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_output_power_v1::ZwlrOutputPowerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_output_power_v1::ZwlrOutputPowerV1,
        request: zwlr_output_power_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        // Fallback to first output
        let output_id = state.outputs.first().map(|o| o.id).unwrap_or(0);
        match request {
            zwlr_output_power_v1::Request::SetMode { mode } => {
                let mode_val = match mode {
                    WEnum::Value(zwlr_output_power_v1::Mode::Off) => 0,
                    WEnum::Value(zwlr_output_power_v1::Mode::On) => 1,
                    _ => {
                        // Protocol error if invalid enum value
                        return;
                    }
                };

                if let Some(output_state) = state.outputs.iter_mut().find(|o| o.id == output_id) {
                    output_state.power_mode = mode_val;
                    tracing::debug!("Output {} power mode set to {}", output_id, mode_val);

                    // Acknowledge the change
                    if let WEnum::Value(m) = mode {
                        resource.mode(m);
                    }

                    // Power mode stored; platform can query via output state
                }
            }
            zwlr_output_power_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

/// Register zwlr_output_power_manager_v1 global
pub fn register_output_power_management(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1, ()>(1, ())
}
