//! Auto-generated weston protocol handlers.

mod ivi_application_protocol;
mod ivi_hmi_controller_protocol;
mod text_cursor_position_protocol;
mod weston_content_protection_protocol;
mod weston_debug_protocol;
mod weston_desktop_shell_protocol;
mod weston_direct_display_protocol;
mod weston_output_capture_protocol;
mod weston_test_protocol;
mod weston_touch_calibration_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

use ivi_application_protocol::ivi_surface::{self, IviSurface};
use ivi_application_protocol::ivi_application::{self, IviApplication};
use ivi_hmi_controller_protocol::ivi_hmi_controller::{self, IviHmiController};
use text_cursor_position_protocol::text_cursor_position::{self, TextCursorPosition};
use weston_content_protection_protocol::weston_content_protection::{self, WestonContentProtection};
use weston_content_protection_protocol::weston_protected_surface::{self, WestonProtectedSurface};
use weston_debug_protocol::weston_debug_v1::{self, WestonDebugV1};
use weston_debug_protocol::weston_debug_stream_v1::{self, WestonDebugStreamV1};
use weston_desktop_shell_protocol::weston_desktop_shell::{self, WestonDesktopShell};
use weston_desktop_shell_protocol::weston_screensaver::{self, WestonScreensaver};
use weston_direct_display_protocol::weston_direct_display_v1::{self, WestonDirectDisplayV1};
use weston_output_capture_protocol::weston_capture_v1::{self, WestonCaptureV1};
use weston_output_capture_protocol::weston_capture_source_v1::{self, WestonCaptureSourceV1};
use weston_test_protocol::weston_test::{self, WestonTest};
use weston_test_protocol::weston_test_runner::{self, WestonTestRunner};
use weston_touch_calibration_protocol::weston_touch_calibration::{self, WestonTouchCalibration};
use weston_touch_calibration_protocol::weston_touch_calibrator::{self, WestonTouchCalibrator};
use weston_touch_calibration_protocol::weston_touch_coordinate::{self, WestonTouchCoordinate};

impl Dispatch<IviSurface, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &IviSurface,
        request: ivi_surface::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<IviApplication, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<IviApplication>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<IviApplication, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &IviApplication,
        request: ivi_application::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ivi_application::Request::SurfaceCreate { ivi_id: _, surface: _, id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<IviHmiController, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<IviHmiController>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<IviHmiController, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &IviHmiController,
        request: ivi_hmi_controller::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TextCursorPosition, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TextCursorPosition>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TextCursorPosition, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TextCursorPosition,
        request: text_cursor_position::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonContentProtection, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonContentProtection>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonContentProtection, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonContentProtection,
        request: weston_content_protection::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            weston_content_protection::Request::GetProtection { id, surface: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<WestonProtectedSurface, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonProtectedSurface,
        request: weston_protected_surface::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonDebugV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonDebugV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonDebugV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonDebugV1,
        request: weston_debug_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            weston_debug_v1::Request::Subscribe { name: _, streamfd: _, stream } => {
                data_init.init(stream, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<WestonDebugStreamV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonDebugStreamV1,
        request: weston_debug_stream_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonDesktopShell, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonDesktopShell>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonDesktopShell, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonDesktopShell,
        request: weston_desktop_shell::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<WestonScreensaver, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonScreensaver,
        request: weston_screensaver::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonDirectDisplayV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonDirectDisplayV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonDirectDisplayV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonDirectDisplayV1,
        request: weston_direct_display_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonCaptureV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonCaptureV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonCaptureV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonCaptureV1,
        request: weston_capture_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            weston_capture_v1::Request::Create { output: _, source: _, capture_source_new_id } => {
                data_init.init(capture_source_new_id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<WestonCaptureSourceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonCaptureSourceV1,
        request: weston_capture_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonTest, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonTest>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonTest, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonTest,
        request: weston_test::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<WestonTestRunner, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonTestRunner,
        request: weston_test_runner::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<WestonTouchCalibration, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WestonTouchCalibration>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WestonTouchCalibration, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonTouchCalibration,
        request: weston_touch_calibration::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            weston_touch_calibration::Request::CreateCalibrator { surface: _, device: _, cal } => {
                data_init.init(cal, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<WestonTouchCalibrator, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonTouchCalibrator,
        request: weston_touch_calibrator::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            weston_touch_calibrator::Request::Convert { x: _, y: _, reply } => {
                data_init.init(reply, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<WestonTouchCoordinate, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WestonTouchCoordinate,
        request: weston_touch_coordinate::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_desktop_extensions(state.protocol_profile) {
        return;
    }
    dh.create_global::<CompositorState, IviApplication, ()>(1, ());
    dh.create_global::<CompositorState, IviHmiController, ()>(1, ());
    dh.create_global::<CompositorState, TextCursorPosition, ()>(1, ());
    dh.create_global::<CompositorState, WestonContentProtection, ()>(1, ());
    dh.create_global::<CompositorState, WestonDebugV1, ()>(1, ());
    dh.create_global::<CompositorState, WestonDesktopShell, ()>(1, ());
    dh.create_global::<CompositorState, WestonDirectDisplayV1, ()>(2, ());
    dh.create_global::<CompositorState, WestonCaptureV1, ()>(2, ());
    dh.create_global::<CompositorState, WestonTest, ()>(1, ());
    dh.create_global::<CompositorState, WestonTouchCalibration, ()>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered weston protocol globals");
}

#[cfg(test)]
mod tests {
    #[test]
    fn weston_register_compiles() {
        assert!(true);
    }
}
