//! River compositor protocols (`zriver_*` / `river_*`).
//!
//! Vendored XML under `protocols/river/`. Portable core: accept objects and
//! track request state; hosts apply layout / input / WM policy via capabilities.

mod control_protocol;
mod input_protocol;
mod layer_protocol;
mod layout_protocol;
mod libinput_protocol;
mod status_protocol;
mod window_protocol;
mod xkb_bindings_protocol;
mod xkb_config_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;
use crate::core::wayland::policy;

use control_protocol::zriver_command_callback_v1::{self, ZriverCommandCallbackV1};
use control_protocol::zriver_control_v1::{self, ZriverControlV1};
use input_protocol::river_input_device_v1::{self, RiverInputDeviceV1};
use input_protocol::river_input_manager_v1::{self, RiverInputManagerV1};
use layer_protocol::river_layer_shell_output_v1::{self, RiverLayerShellOutputV1};
use layer_protocol::river_layer_shell_seat_v1::{self, RiverLayerShellSeatV1};
use layer_protocol::river_layer_shell_v1::{self, RiverLayerShellV1};
use layout_protocol::river_layout_manager_v3::{self, RiverLayoutManagerV3};
use layout_protocol::river_layout_v3::{self, RiverLayoutV3};
use libinput_protocol::river_libinput_accel_config_v1::{self, RiverLibinputAccelConfigV1};
use libinput_protocol::river_libinput_config_v1::{self, RiverLibinputConfigV1};
use libinput_protocol::river_libinput_device_v1::{self, RiverLibinputDeviceV1};
use libinput_protocol::river_libinput_result_v1::{self, RiverLibinputResultV1};
use status_protocol::zriver_output_status_v1::{self, ZriverOutputStatusV1};
use status_protocol::zriver_seat_status_v1::{self, ZriverSeatStatusV1};
use status_protocol::zriver_status_manager_v1::{self, ZriverStatusManagerV1};
use window_protocol::river_decoration_v1::{self, RiverDecorationV1};
use window_protocol::river_node_v1::{self, RiverNodeV1};
use window_protocol::river_output_v1::{self, RiverOutputV1};
use window_protocol::river_pointer_binding_v1::{self, RiverPointerBindingV1};
use window_protocol::river_seat_v1::{self, RiverSeatV1};
use window_protocol::river_shell_surface_v1::{self, RiverShellSurfaceV1};
use window_protocol::river_window_manager_v1::{self, RiverWindowManagerV1};
use window_protocol::river_window_v1::{self, RiverWindowV1};
use xkb_bindings_protocol::river_xkb_binding_v1::{self, RiverXkbBindingV1};
use xkb_bindings_protocol::river_xkb_bindings_seat_v1::{self, RiverXkbBindingsSeatV1};
use xkb_bindings_protocol::river_xkb_bindings_v1::{self, RiverXkbBindingsV1};
use xkb_config_protocol::river_xkb_config_v1::{self, RiverXkbConfigV1};
use xkb_config_protocol::river_xkb_keyboard_v1::{self, RiverXkbKeyboardV1};
use xkb_config_protocol::river_xkb_keymap_v1::{self, RiverXkbKeymapV1};

#[derive(Debug, Default)]
pub struct RiverState {
    pub pending_args: std::collections::HashMap<u32, Vec<String>>,
    pub focused_tags: u32,
}

macro_rules! river_global {
    ($ty:ty) => {
        impl GlobalDispatch<$ty, ()> for CompositorState {
            fn bind(
                _state: &mut Self,
                _handle: &DisplayHandle,
                _client: &Client,
                resource: New<$ty>,
                _global_data: &(),
                data_init: &mut DataInit<'_, Self>,
            ) {
                data_init.init(resource, ());
            }
        }
    };
}

macro_rules! river_noop_dispatch {
    ($ty:ty, $req:path) => {
        impl Dispatch<$ty, ()> for CompositorState {
            fn request(
                _state: &mut Self,
                _client: &Client,
                _resource: &$ty,
                request: $req,
                _data: &(),
                _dhandle: &DisplayHandle,
                _data_init: &mut DataInit<'_, Self>,
            ) {
                let _ = request;
            }
        }
    };
}

// ---------------------------------------------------------------------------
// control + status (existing)
// ---------------------------------------------------------------------------

river_global!(ZriverControlV1);

impl Dispatch<ZriverControlV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZriverControlV1,
        request: zriver_control_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let cid = resource.id().protocol_id();
        match request {
            zriver_control_v1::Request::AddArgument { argument } => {
                state
                    .river
                    .pending_args
                    .entry(cid)
                    .or_default()
                    .push(argument);
            }
            zriver_control_v1::Request::RunCommand { seat: _, callback } => {
                let cb: ZriverCommandCallbackV1 = data_init.init(callback, ());
                let args = state.river.pending_args.remove(&cid).unwrap_or_default();
                if args.is_empty() {
                    cb.failure(String::from("no command"));
                } else {
                    tracing::info!(target: "river", "zriver_control run {:?}", args);
                    cb.success(String::new());
                }
            }
            zriver_control_v1::Request::Destroy => {
                state.river.pending_args.remove(&cid);
            }
            _ => {}
        }
    }
}

river_noop_dispatch!(ZriverCommandCallbackV1, zriver_command_callback_v1::Request);

river_global!(ZriverStatusManagerV1);

impl Dispatch<ZriverStatusManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZriverStatusManagerV1,
        request: zriver_status_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zriver_status_manager_v1::Request::GetRiverOutputStatus { id, output: _ } => {
                let status: ZriverOutputStatusV1 = data_init.init(id, ());
                let tags = if state.river.focused_tags == 0 {
                    1
                } else {
                    state.river.focused_tags
                };
                status.focused_tags(tags);
                status.view_tags(Vec::new());
                if status.version() >= 2 {
                    status.urgent_tags(0);
                }
            }
            zriver_status_manager_v1::Request::GetRiverSeatStatus { id, seat: _ } => {
                let _s: ZriverSeatStatusV1 = data_init.init(id, ());
            }
            zriver_status_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(ZriverOutputStatusV1, zriver_output_status_v1::Request);
river_noop_dispatch!(ZriverSeatStatusV1, zriver_seat_status_v1::Request);

// ---------------------------------------------------------------------------
// layout v3
// ---------------------------------------------------------------------------

river_global!(RiverLayoutManagerV3);

impl Dispatch<RiverLayoutManagerV3, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverLayoutManagerV3,
        request: river_layout_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_layout_manager_v3::Request::GetLayout {
                id,
                output: _,
                namespace: _,
            } => {
                data_init.init(id, ());
            }
            river_layout_manager_v3::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverLayoutV3, river_layout_v3::Request);

// ---------------------------------------------------------------------------
// input management
// ---------------------------------------------------------------------------

river_global!(RiverInputManagerV1);

impl Dispatch<RiverInputManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverInputManagerV1,
        request: river_input_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_input_manager_v1::Request::CreateSeat { .. } => {}
            river_input_manager_v1::Request::DestroySeat { .. } => {}
            river_input_manager_v1::Request::Stop => {}
            river_input_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverInputDeviceV1, river_input_device_v1::Request);

// ---------------------------------------------------------------------------
// libinput config
// ---------------------------------------------------------------------------

river_global!(RiverLibinputConfigV1);

impl Dispatch<RiverLibinputConfigV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverLibinputConfigV1,
        request: river_libinput_config_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_libinput_config_v1::Request::CreateAccelConfig { id, profile: _ } => {
                data_init.init(id, ());
            }
            river_libinput_config_v1::Request::Stop => {}
            river_libinput_config_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<RiverLibinputDeviceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverLibinputDeviceV1,
        request: river_libinput_device_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        // Many set_* requests return a result object named `result`.
        match request {
            river_libinput_device_v1::Request::SetSendEvents { result, .. }
            | river_libinput_device_v1::Request::SetTap { result, .. }
            | river_libinput_device_v1::Request::SetTapButtonMap { result, .. }
            | river_libinput_device_v1::Request::SetDrag { result, .. }
            | river_libinput_device_v1::Request::SetDragLock { result, .. }
            | river_libinput_device_v1::Request::SetAccelProfile { result, .. }
            | river_libinput_device_v1::Request::SetAccelSpeed { result, .. }
            | river_libinput_device_v1::Request::ApplyAccelConfig { result, .. }
            | river_libinput_device_v1::Request::SetNaturalScroll { result, .. }
            | river_libinput_device_v1::Request::SetLeftHanded { result, .. }
            | river_libinput_device_v1::Request::SetClickMethod { result, .. }
            | river_libinput_device_v1::Request::SetMiddleEmulation { result, .. }
            | river_libinput_device_v1::Request::SetScrollMethod { result, .. }
            | river_libinput_device_v1::Request::SetScrollButton { result, .. }
            | river_libinput_device_v1::Request::SetScrollButtonLock { result, .. }
            | river_libinput_device_v1::Request::SetDwt { result, .. }
            | river_libinput_device_v1::Request::SetDwtp { result, .. }
            | river_libinput_device_v1::Request::SetRotation { result, .. }
            | river_libinput_device_v1::Request::SetCalibrationMatrix { result, .. }
            | river_libinput_device_v1::Request::SetThreeFingerDrag { result, .. }
            | river_libinput_device_v1::Request::SetClickfingerButtonMap { result, .. } => {
                let r: RiverLibinputResultV1 = data_init.init(result, ());
                r.success();
            }
            river_libinput_device_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(
    RiverLibinputAccelConfigV1,
    river_libinput_accel_config_v1::Request
);
river_noop_dispatch!(RiverLibinputResultV1, river_libinput_result_v1::Request);

// ---------------------------------------------------------------------------
// xkb bindings
// ---------------------------------------------------------------------------

river_global!(RiverXkbBindingsV1);

impl Dispatch<RiverXkbBindingsV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverXkbBindingsV1,
        request: river_xkb_bindings_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_xkb_bindings_v1::Request::GetXkbBinding { id, .. } => {
                data_init.init(id, ());
            }
            river_xkb_bindings_v1::Request::GetSeat { id, .. } => {
                data_init.init(id, ());
            }
            river_xkb_bindings_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverXkbBindingV1, river_xkb_binding_v1::Request);
river_noop_dispatch!(RiverXkbBindingsSeatV1, river_xkb_bindings_seat_v1::Request);

// ---------------------------------------------------------------------------
// xkb config
// ---------------------------------------------------------------------------

river_global!(RiverXkbConfigV1);

impl Dispatch<RiverXkbConfigV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverXkbConfigV1,
        request: river_xkb_config_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_xkb_config_v1::Request::CreateKeymap { id, .. } => {
                data_init.init(id, ());
            }
            river_xkb_config_v1::Request::Stop => {}
            river_xkb_config_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverXkbKeymapV1, river_xkb_keymap_v1::Request);
river_noop_dispatch!(RiverXkbKeyboardV1, river_xkb_keyboard_v1::Request);

// ---------------------------------------------------------------------------
// window management (accept objects; host applies policy)
// ---------------------------------------------------------------------------

river_global!(RiverWindowManagerV1);

impl Dispatch<RiverWindowManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverWindowManagerV1,
        request: river_window_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        // Windows/outputs/seats are server-pushed; create shell surfaces when asked.
        match request {
            river_window_manager_v1::Request::GetShellSurface { id, .. } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverWindowV1, river_window_v1::Request);
river_noop_dispatch!(RiverDecorationV1, river_decoration_v1::Request);
river_noop_dispatch!(RiverShellSurfaceV1, river_shell_surface_v1::Request);
river_noop_dispatch!(RiverNodeV1, river_node_v1::Request);
river_noop_dispatch!(RiverOutputV1, river_output_v1::Request);
river_noop_dispatch!(RiverSeatV1, river_seat_v1::Request);
river_noop_dispatch!(RiverPointerBindingV1, river_pointer_binding_v1::Request);

// ---------------------------------------------------------------------------
// layer shell (depends on river_output_v1 / river_seat_v1)
// ---------------------------------------------------------------------------

river_global!(RiverLayerShellV1);

impl Dispatch<RiverLayerShellV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &RiverLayerShellV1,
        request: river_layer_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            river_layer_shell_v1::Request::GetOutput { id, .. } => {
                data_init.init(id, ());
            }
            river_layer_shell_v1::Request::GetSeat { id, .. } => {
                data_init.init(id, ());
            }
            river_layer_shell_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

river_noop_dispatch!(RiverLayerShellOutputV1, river_layer_shell_output_v1::Request);
river_noop_dispatch!(RiverLayerShellSeatV1, river_layer_shell_seat_v1::Request);

pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_desktop_extensions(state.protocol_profile) {
        return;
    }
    dh.create_global::<CompositorState, ZriverControlV1, ()>(1, ());
    dh.create_global::<CompositorState, ZriverStatusManagerV1, ()>(4, ());
    dh.create_global::<CompositorState, RiverLayoutManagerV3, ()>(2, ());
    dh.create_global::<CompositorState, RiverInputManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, RiverLibinputConfigV1, ()>(2, ());
    dh.create_global::<CompositorState, RiverXkbBindingsV1, ()>(3, ());
    dh.create_global::<CompositorState, RiverXkbConfigV1, ()>(3, ());
    dh.create_global::<CompositorState, RiverWindowManagerV1, ()>(6, ());
    dh.create_global::<CompositorState, RiverLayerShellV1, ()>(1, ());
    crate::wlog!(
        crate::util::logging::COMPOSITOR,
        "Registered River protocol globals"
    );
}

#[cfg(test)]
mod tests {
    #[test]
    fn default_focused_tags_zero() {
        let s = super::RiverState::default();
        assert_eq!(s.focused_tags, 0);
    }
}
