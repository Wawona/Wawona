//! Experimental / remaining protocol handlers.

mod wayland_drm_protocol;
mod xdg_session_management_v1_protocol;
mod xx_cutouts_v1_protocol;
mod xx_input_method_v2_protocol;
mod xx_keyboard_filter_v1_protocol;
mod xx_session_management_v1_protocol;
mod xx_text_input_v3_protocol;
mod xx_zones_v1_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

use wayland_drm_protocol::wl_drm::{self, WlDrm};
use xdg_session_management_v1_protocol::xdg_session_manager_v1::{self, XdgSessionManagerV1};
use xdg_session_management_v1_protocol::xdg_session_v1::{self, XdgSessionV1};
use xdg_session_management_v1_protocol::xdg_toplevel_session_v1::{self, XdgToplevelSessionV1};
use xx_cutouts_v1_protocol::xx_cutouts_manager_v1::{self, XxCutoutsManagerV1};
use xx_cutouts_v1_protocol::xx_cutouts_v1::{self, XxCutoutsV1};
use xx_input_method_v2_protocol::xx_input_method_v1::{self, XxInputMethodV1};
use xx_input_method_v2_protocol::xx_input_popup_surface_v2::{self, XxInputPopupSurfaceV2};
use xx_input_method_v2_protocol::xx_input_popup_positioner_v1::{self, XxInputPopupPositionerV1};
use xx_input_method_v2_protocol::xx_input_method_manager_v2::{self, XxInputMethodManagerV2};
use xx_keyboard_filter_v1_protocol::xx_keyboard_filter_v1::{self, XxKeyboardFilterV1};
use xx_keyboard_filter_v1_protocol::xx_keyboard_filter_manager_v1::{self, XxKeyboardFilterManagerV1};
use xx_session_management_v1_protocol::xx_session_manager_v1::{self, XxSessionManagerV1};
use xx_session_management_v1_protocol::xx_session_v1::{self, XxSessionV1};
use xx_session_management_v1_protocol::xx_toplevel_session_v1::{self, XxToplevelSessionV1};
use xx_text_input_v3_protocol::xx_text_input_v3::{self, XxTextInputV3};
use xx_text_input_v3_protocol::xx_text_input_manager_v3::{self, XxTextInputManagerV3};
use xx_zones_v1_protocol::xx_zone_manager_v1::{self, XxZoneManagerV1};
use xx_zones_v1_protocol::xx_zone_item_v1::{self, XxZoneItemV1};
use xx_zones_v1_protocol::xx_zone_v1::{self, XxZoneV1};

impl GlobalDispatch<WlDrm, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlDrm>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WlDrm, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WlDrm,
        request: wl_drm::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_drm::Request::CreateBuffer { id, name: _, width: _, height: _, stride: _, format: _ } => {
                data_init.init(id, ());
            }
            wl_drm::Request::CreatePlanarBuffer { id, name: _, width: _, height: _, format: _, offset0: _, stride0: _, offset1: _, stride1: _, offset2: _, stride2: _ } => {
                data_init.init(id, ());
            }
            wl_drm::Request::CreatePrimeBuffer { id, name: _, width: _, height: _, format: _, offset0: _, stride0: _, offset1: _, stride1: _, offset2: _, stride2: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<XdgSessionManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgSessionManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XdgSessionManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgSessionManagerV1,
        request: xdg_session_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_session_manager_v1::Request::GetSession { id, reason: _, session_id: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XdgSessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgSessionV1,
        request: xdg_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_session_v1::Request::AddToplevel { id, toplevel: _, name: _ } => {
                data_init.init(id, ());
            }
            xdg_session_v1::Request::RestoreToplevel { id, toplevel: _, name: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XdgToplevelSessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgToplevelSessionV1,
        request: xdg_toplevel_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<XxCutoutsManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XxCutoutsManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XxCutoutsManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxCutoutsManagerV1,
        request: xx_cutouts_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_cutouts_manager_v1::Request::GetCutouts { id, surface: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxCutoutsV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxCutoutsV1,
        request: xx_cutouts_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<XxInputMethodV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxInputMethodV1,
        request: xx_input_method_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_input_method_v1::Request::GetInputPopupSurface { id, surface: _, positioner: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxInputPopupSurfaceV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxInputPopupSurfaceV2,
        request: xx_input_popup_surface_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<XxInputPopupPositionerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxInputPopupPositionerV1,
        request: xx_input_popup_positioner_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<XxInputMethodManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XxInputMethodManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XxInputMethodManagerV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxInputMethodManagerV2,
        request: xx_input_method_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_input_method_manager_v2::Request::GetInputMethod { seat: _, input_method } => {
                data_init.init(input_method, ());
            }
            xx_input_method_manager_v2::Request::GetPositioner { id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxKeyboardFilterV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxKeyboardFilterV1,
        request: xx_keyboard_filter_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<XxKeyboardFilterManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XxKeyboardFilterManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XxKeyboardFilterManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxKeyboardFilterManagerV1,
        request: xx_keyboard_filter_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_keyboard_filter_manager_v1::Request::BindToInputMethod { keyboard: _, input_method: _, surface: _, extensions } => {
                data_init.init(extensions, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<XxSessionManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XxSessionManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XxSessionManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxSessionManagerV1,
        request: xx_session_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_session_manager_v1::Request::GetSession { id, reason: _, session: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxSessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxSessionV1,
        request: xx_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_session_v1::Request::AddToplevel { id, toplevel: _, name: _ } => {
                data_init.init(id, ());
            }
            xx_session_v1::Request::RestoreToplevel { id, toplevel: _, name: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxToplevelSessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxToplevelSessionV1,
        request: xx_toplevel_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<XxTextInputV3, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxTextInputV3,
        request: xx_text_input_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<XxTextInputManagerV3, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxTextInputManagerV3,
        request: xx_text_input_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_text_input_manager_v3::Request::GetTextInput { id, seat: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<XxZoneManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XxZoneManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<XxZoneManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxZoneManagerV1,
        request: xx_zone_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xx_zone_manager_v1::Request::GetZoneItem { id, toplevel: _ } => {
                data_init.init(id, ());
            }
            xx_zone_manager_v1::Request::GetZone { id, output: _ } => {
                data_init.init(id, ());
            }
            xx_zone_manager_v1::Request::GetZoneFromHandle { id, handle: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<XxZoneItemV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxZoneItemV1,
        request: xx_zone_item_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<XxZoneV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XxZoneV1,
        request: xx_zone_v1::Request,
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
    dh.create_global::<CompositorState, WlDrm, ()>(2, ());
    dh.create_global::<CompositorState, XdgSessionManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, XxCutoutsManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, XxInputMethodManagerV2, ()>(4, ());
    dh.create_global::<CompositorState, XxKeyboardFilterManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, XxSessionManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, XxZoneManagerV1, ()>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered experimental protocol globals");
}

#[cfg(test)]
mod tests {
    #[test]
    fn experimental_register_compiles() {
        assert!(true);
    }
}
