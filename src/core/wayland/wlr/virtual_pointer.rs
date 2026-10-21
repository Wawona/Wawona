use wayland_server::protocol::wl_pointer;
use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::pointer_focus::PointerAxisEvent;

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
                    data_init.init(id, VirtualPointerData::default());
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
                    data_init.init(id, VirtualPointerData::default());
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

/// Events of one `zwlr_virtual_pointer_v1` frame. Nothing reaches clients
/// until `frame`, and then in `wl_pointer` order (axis source first).
#[derive(Debug, Default)]
pub struct VirtualPointerFrame {
    motion: Option<FrameMotion>,
    buttons: Vec<(u32, wl_pointer::ButtonState)>,
    axes: Vec<PointerAxisEvent>,
    axis_source: Option<wl_pointer::AxisSource>,
    time: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum FrameMotion {
    Relative(f64, f64),
    Absolute(f64, f64),
}

impl VirtualPointerFrame {
    fn add_relative(&mut self, dx: f64, dy: f64) {
        self.motion = Some(match self.motion {
            Some(FrameMotion::Relative(x, y)) => FrameMotion::Relative(x + dx, y + dy),
            Some(FrameMotion::Absolute(x, y)) => FrameMotion::Absolute(x + dx, y + dy),
            None => FrameMotion::Relative(dx, dy),
        });
    }

    fn axis_mut(&mut self, axis: wl_pointer::Axis) -> &mut PointerAxisEvent {
        let index = match self.axes.iter().position(|a| a.axis == axis) {
            Some(index) => index,
            None => {
                self.axes.push(PointerAxisEvent {
                    axis,
                    value: None,
                    discrete: None,
                    source: None,
                    stop: false,
                });
                self.axes.len() - 1
            }
        };
        &mut self.axes[index]
    }
}

/// Map `(x, y)` within `(x_extent, y_extent)` onto the output rectangle.
pub fn absolute_to_output(
    (x, y): (u32, u32),
    (x_extent, y_extent): (u32, u32),
    (ox, oy, ow, oh): (i32, i32, u32, u32),
) -> Option<(f64, f64)> {
    if x_extent == 0 || y_extent == 0 {
        return None;
    }
    let fx = f64::from(x) / f64::from(x_extent);
    let fy = f64::from(y) / f64::from(y_extent);
    Some((
        f64::from(ox) + fx * f64::from(ow),
        f64::from(oy) + fy * f64::from(oh),
    ))
}

type VirtualPointerData = std::sync::Mutex<VirtualPointerFrame>;

impl CompositorState {
    /// Deliver one completed virtual-pointer frame through the global
    /// pointer, as a physical device would.
    fn flush_virtual_pointer_frame(&mut self, frame: VirtualPointerFrame) {
        let time = frame.time;
        if let Some(motion) = frame.motion {
            let (cx, cy) = self.seat.pointer.global_position.unwrap_or((0.0, 0.0));
            let (x, y) = match motion {
                FrameMotion::Relative(dx, dy) => (cx + dx, cy + dy),
                FrameMotion::Absolute(x, y) => (x, y),
            };
            if let Some(position) = self.constrain_global_pointer(x, y, time) {
                self.seat.pointer.global_position = Some(position);
                let serial = self.next_serial();
                self.deliver_global_pointer(position.0, position.1, time, serial);
            }
        }
        for (button, button_state) in frame.buttons {
            self.deliver_global_button(button, button_state, time);
        }
        let client = self.focused_pointer_client();
        if let Some(client) = client.as_ref() {
            let mut source = frame.axis_source;
            for mut axis in frame.axes {
                axis.source = source.take();
                self.send_pointer_axis(client, time, &axis);
            }
            self.send_pointer_frame(client);
        }
    }
}

impl Dispatch<zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1, VirtualPointerData>
    for CompositorState
{
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
        request: zwlr_virtual_pointer_v1::Request,
        data: &VirtualPointerData,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        use zwlr_virtual_pointer_v1::Request;
        let Ok(mut frame) = data.lock() else {
            return;
        };
        match request {
            Request::Motion { time, dx, dy } => {
                frame.time = time;
                frame.add_relative(dx, dy);
            }
            Request::MotionAbsolute {
                time,
                x,
                y,
                x_extent,
                y_extent,
            } => {
                frame.time = time;
                let output = state.primary_output();
                let rect = (output.x, output.y, output.width, output.height);
                if let Some((ax, ay)) = absolute_to_output((x, y), (x_extent, y_extent), rect) {
                    frame.motion = Some(FrameMotion::Absolute(ax, ay));
                }
            }
            Request::Button {
                time,
                button,
                state: wayland_server::WEnum::Value(button_state),
            } => {
                frame.time = time;
                frame.buttons.push((button, button_state));
            }
            Request::Axis {
                time,
                axis: wayland_server::WEnum::Value(axis),
                value,
            } => {
                frame.time = time;
                let event = frame.axis_mut(axis);
                event.value = Some(event.value.unwrap_or(0.0) + value);
            }
            Request::AxisDiscrete {
                time,
                axis: wayland_server::WEnum::Value(axis),
                value,
                discrete,
            } => {
                frame.time = time;
                let event = frame.axis_mut(axis);
                event.value = Some(event.value.unwrap_or(0.0) + value);
                event.discrete = Some(event.discrete.unwrap_or(0) + discrete);
            }
            Request::AxisSource {
                axis_source: wayland_server::WEnum::Value(source),
            } => {
                frame.axis_source = Some(source);
            }
            Request::AxisStop {
                time,
                axis: wayland_server::WEnum::Value(axis),
            } => {
                frame.time = time;
                frame.axis_mut(axis).stop = true;
            }
            Request::Frame => {
                let completed = std::mem::take(&mut *frame);
                drop(frame);
                state.flush_virtual_pointer_frame(completed);
            }
            _ => {}
        }
    }
}

/// Register zwlr_virtual_pointer_manager_v1 global
pub fn register_virtual_pointer(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, ()>(2, ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_to_output_should_scale_extent_onto_output() {
        assert_eq!(
            absolute_to_output((44, 66), (3840, 2160), (0, 0, 1920, 1080)),
            Some((22.0, 33.0))
        );
    }

    #[test]
    fn absolute_to_output_should_reject_zero_extent() {
        assert_eq!(
            absolute_to_output((1, 1), (0, 10), (0, 0, 1920, 1080)),
            None
        );
    }

    #[test]
    fn relative_motion_should_accumulate_within_a_frame() {
        let mut frame = VirtualPointerFrame::default();
        frame.add_relative(7.0, 22.0);
        frame.add_relative(5.0, -12.0);
        assert_eq!(frame.motion, Some(FrameMotion::Relative(12.0, 10.0)));
    }
}
