//! zwlr_output_power_management_unstable_v1.
//!
//! Protocol state lives in Rust core (`OutputState.power_mode`). Hosts apply
//! DPMS / blanking via a capability hook when they support it.

use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource, WEnum};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol_proofs::output_power_mode_is_on_or_off;
use crate::core::wayland::protocol::wlroots::wlr_output_power_management_unstable_v1::{
    zwlr_output_power_manager_v1, zwlr_output_power_v1,
};

fn output_id_from_wl_output(
    state: &CompositorState,
    _output: &wayland_server::protocol::wl_output::WlOutput,
) -> u32 {
    // Prefer primary / first advertised output until wl_output user-data is
    // wired uniformly across backends.
    state.outputs.first().map(|o| o.id).unwrap_or(0)
}

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
            zwlr_output_power_manager_v1::Request::GetOutputPower { id, output } => {
                let output_id = output_id_from_wl_output(state, &output);
                let power: zwlr_output_power_v1::ZwlrOutputPowerV1 =
                    data_init.init(id, output_id);
                if let Some(output_state) = state.outputs.iter().find(|o| o.id == output_id) {
                    let mode = if output_state.power_mode == 0 {
                        zwlr_output_power_v1::Mode::Off
                    } else {
                        zwlr_output_power_v1::Mode::On
                    };
                    power.mode(mode);
                } else {
                    power.mode(zwlr_output_power_v1::Mode::On);
                }
            }
            zwlr_output_power_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<zwlr_output_power_v1::ZwlrOutputPowerV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_output_power_v1::ZwlrOutputPowerV1,
        request: zwlr_output_power_v1::Request,
        output_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_power_v1::Request::SetMode { mode } => {
                let mode_val = match mode {
                    WEnum::Value(zwlr_output_power_v1::Mode::Off) => 0,
                    WEnum::Value(zwlr_output_power_v1::Mode::On) => 1,
                    _ => return,
                };
                if !output_power_mode_is_on_or_off(mode_val) {
                    return;
                }

                if let Some(output_state) = state.outputs.iter_mut().find(|o| o.id == *output_id) {
                    output_state.power_mode = mode_val;
                    tracing::debug!("Output {} power mode set to {}", output_id, mode_val);
                }

                if let WEnum::Value(m) = mode {
                    resource.mode(m);
                }
            }
            zwlr_output_power_v1::Request::Destroy => {}
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

#[cfg(test)]
mod tests {
    use crate::core::wayland::protocol_proofs::output_power_mode_is_on_or_off;

    #[test]
    fn power_mode_values_are_off_zero_on_one() {
        assert!(output_power_mode_is_on_or_off(0));
        assert!(output_power_mode_is_on_or_off(1));
        assert!(!output_power_mode_is_on_or_off(2));
    }
}
