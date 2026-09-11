use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol::wlroots::wlr_virtual_pointer_unstable_v1::{
    zwlr_virtual_pointer_manager_v1, zwlr_virtual_pointer_v1,
};

pub struct VirtualPointerManagerData;

/// State for a virtual pointer device
#[derive(Debug, Clone)]
pub struct VirtualPointerState {
    /// Associated seat name
    pub seat_name: Option<String>,
    /// Associated output ID (for absolute motion)
    pub output_id: Option<u32>,
}

impl VirtualPointerState {
    pub fn new(seat_name: Option<String>, output_id: Option<u32>) -> Self {
        Self {
            seat_name,
            output_id,
        }
    }
}

impl GlobalDispatch<zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, ()>
    for CompositorState
{
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, ()>
    for CompositorState
{
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1,
        request: zwlr_virtual_pointer_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_virtual_pointer_manager_v1::Request::CreateVirtualPointer { seat, id } => {
                let seat_name = seat
                    .as_ref()
                    .map(|s| s.data::<String>().cloned().unwrap_or_default());
                let pointer_res: zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1 =
                    data_init.init(id, ());
                let resource_id = pointer_res.id().protocol_id();

                let pointer_state = VirtualPointerState::new(seat_name, None);
                state.add_virtual_pointer(_client.id(), resource_id, pointer_state);
            }
            zwlr_virtual_pointer_manager_v1::Request::CreateVirtualPointerWithOutput {
                seat,
                output: _,
                id,
            } => {
                let seat_name = seat
                    .as_ref()
                    .map(|s| s.data::<String>().cloned().unwrap_or_default());
                // For now ignore output ID as we can't easily access user data from here without proper types
                let output_id = 0;
                let pointer_res: zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1 =
                    data_init.init(id, ());
                let resource_id = pointer_res.id().protocol_id();

                let pointer_state = VirtualPointerState::new(seat_name, Some(output_id));
                state.add_virtual_pointer(_client.id(), resource_id, pointer_state);
            }
            zwlr_virtual_pointer_manager_v1::Request::Destroy => {
                // Destructor
            }
            _ => {}
        }
    }
}

impl Dispatch<zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
        request: zwlr_virtual_pointer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_virtual_pointer_v1::Request::Motion { time, dx, dy } => {
                tracing::debug!("Virtual pointer motion: dx={}, dy={} at {}", dx, dy, time);
                state.inject_pointer_motion_relative(dx, dy, time);
            }
            zwlr_virtual_pointer_v1::Request::MotionAbsolute {
                time,
                x,
                y,
                x_extent,
                y_extent,
            } => {
                tracing::debug!(
                    "Virtual pointer motion absolute: {}/{} of {}/{} at {}",
                    x,
                    y,
                    x_extent,
                    y_extent,
                    time
                );
                // Convert to f64 to match state signature
                state.inject_pointer_motion_absolute(x as f64, y as f64, time);
            }
            zwlr_virtual_pointer_v1::Request::Button {
                time,
                button,
                state: button_state,
            } => {
                tracing::debug!(
                    "Virtual pointer button: {} is {:?} at {}",
                    button,
                    button_state,
                    time
                );

                let wl_state = match button_state {
                    wayland_server::WEnum::Value(s) => match s {
                        wayland_server::protocol::wl_pointer::ButtonState::Released => {
                            wayland_server::protocol::wl_pointer::ButtonState::Released
                        }
                        wayland_server::protocol::wl_pointer::ButtonState::Pressed => {
                            wayland_server::protocol::wl_pointer::ButtonState::Pressed
                        }
                        _ => return,
                    },
                    _ => return,
                };
                state.inject_pointer_button(button, wl_state, time);
            }
            zwlr_virtual_pointer_v1::Request::Axis { time, axis, value } => {
                tracing::debug!("Virtual pointer axis: {:?} is {} at {}", axis, value, time);
            }
            zwlr_virtual_pointer_v1::Request::Frame => {
                tracing::debug!("Virtual pointer frame");
                state.flush_pointer_events();
            }
            zwlr_virtual_pointer_v1::Request::AxisSource { axis_source } => {
                tracing::debug!("Virtual pointer axis source: {:?}", axis_source);
            }
            zwlr_virtual_pointer_v1::Request::AxisStop { time, axis } => {
                tracing::debug!("Virtual pointer axis stop: {:?} at {}", axis, time);
            }
            zwlr_virtual_pointer_v1::Request::AxisDiscrete {
                time,
                axis,
                value,
                discrete,
            } => {
                tracing::debug!(
                    "Virtual pointer axis discrete: {:?} value={}, discrete={} at {}",
                    axis,
                    value,
                    discrete,
                    time
                );
            }
            _ => {}
        }
    }
}

/// Register zwlr_virtual_pointer_manager_v1 global
pub fn register_virtual_pointer(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, ()>(2, ())
}
