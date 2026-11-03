//! Remaining Plasma / KDE protocol globals (wayland-protocols-plasma).
//!
//! Portable core: accept objects and track lightweight request state. Hosts
//! apply fake-input / brightness / screencast / output config via capabilities.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use wayland_protocols_plasma::{
    appmenu::server::{
        org_kde_kwin_appmenu::{self, OrgKdeKwinAppmenu},
        org_kde_kwin_appmenu_manager::{self, OrgKdeKwinAppmenuManager},
    },
    external_brightness::v1::server::{
        kde_external_brightness_device_v1::{self, KdeExternalBrightnessDeviceV1},
        kde_external_brightness_v1::{self, KdeExternalBrightnessV1},
    },
    fake_input::server::org_kde_kwin_fake_input::{self, OrgKdeKwinFakeInput},
    keystate::server::org_kde_kwin_keystate::{self, OrgKdeKwinKeystate},
    lockscreen_overlay::v1::server::kde_lockscreen_overlay_v1::{
        self, KdeLockscreenOverlayV1,
    },
    output_device::v1::server::org_kde_kwin_outputdevice::{self, OrgKdeKwinOutputdevice},
    output_device::v2::server::{
        kde_output_device_mode_v2::{self, KdeOutputDeviceModeV2},
        kde_output_device_v2::{self, KdeOutputDeviceV2},
    },
    output_management::v1::server::{
        org_kde_kwin_outputconfiguration::{self, OrgKdeKwinOutputconfiguration},
        org_kde_kwin_outputmanagement::{self, OrgKdeKwinOutputmanagement},
    },
    output_management::v2::server::{
        kde_output_configuration_v2::{self, KdeOutputConfigurationV2},
        kde_output_management_v2::{self, KdeOutputManagementV2},
    },
    output_order::v1::server::kde_output_order_v1::{self, KdeOutputOrderV1},
    plasma_shell::server::{
        org_kde_plasma_shell::{self, OrgKdePlasmaShell},
        org_kde_plasma_surface::{self, OrgKdePlasmaSurface},
    },
    plasma_virtual_desktop::server::{
        org_kde_plasma_virtual_desktop::{self, OrgKdePlasmaVirtualDesktop},
        org_kde_plasma_virtual_desktop_management::{
            self, OrgKdePlasmaVirtualDesktopManagement,
        },
    },
    plasma_window_management::server::{
        org_kde_plasma_activation::{self, OrgKdePlasmaActivation},
        org_kde_plasma_activation_feedback::{self, OrgKdePlasmaActivationFeedback},
        org_kde_plasma_stacking_order::{self, OrgKdePlasmaStackingOrder},
        org_kde_plasma_window::{self, OrgKdePlasmaWindow},
        org_kde_plasma_window_management::{self, OrgKdePlasmaWindowManagement},
    },
    primary_output::v1::server::kde_primary_output_v1::{self, KdePrimaryOutputV1},
    screen_edge::v1::server::{
        kde_auto_hide_screen_edge_v1::{self, KdeAutoHideScreenEdgeV1},
        kde_screen_edge_manager_v1::{self, KdeScreenEdgeManagerV1},
    },
    screencast::v1::server::{
        zkde_screencast_stream_unstable_v1::{self, ZkdeScreencastStreamUnstableV1},
        zkde_screencast_unstable_v1::{self, ZkdeScreencastUnstableV1},
    },
    server_decoration_palette::server::{
        org_kde_kwin_server_decoration_palette::{self, OrgKdeKwinServerDecorationPalette},
        org_kde_kwin_server_decoration_palette_manager::{
            self, OrgKdeKwinServerDecorationPaletteManager,
        },
    },
};

use crate::core::state::CompositorState;

macro_rules! plasma_global {
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

macro_rules! plasma_noop {
    ($ty:ty, $req:ty) => {
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

// --- simple single-object globals ------------------------------------------------

plasma_global!(OrgKdeKwinFakeInput);
plasma_noop!(OrgKdeKwinFakeInput, org_kde_kwin_fake_input::Request);

plasma_global!(OrgKdeKwinKeystate);
impl Dispatch<OrgKdeKwinKeystate, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &OrgKdeKwinKeystate,
        request: org_kde_kwin_keystate::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_keystate::Request::FetchStates => {
                // No locked modifiers by default.
                resource.stateChanged(0, 0); // capslock unlocked
            }
            org_kde_kwin_keystate::Request::Destroy => {}
            _ => {}
        }
    }
}

plasma_global!(KdeLockscreenOverlayV1);
plasma_noop!(KdeLockscreenOverlayV1, kde_lockscreen_overlay_v1::Request);

plasma_global!(KdeOutputOrderV1);
plasma_noop!(KdeOutputOrderV1, kde_output_order_v1::Request);

plasma_global!(KdePrimaryOutputV1);
plasma_noop!(KdePrimaryOutputV1, kde_primary_output_v1::Request);

plasma_global!(OrgKdeKwinOutputdevice);
plasma_noop!(OrgKdeKwinOutputdevice, org_kde_kwin_outputdevice::Request);

plasma_global!(KdeOutputDeviceV2);
plasma_noop!(KdeOutputDeviceV2, kde_output_device_v2::Request);
plasma_noop!(KdeOutputDeviceModeV2, kde_output_device_mode_v2::Request);

// --- appmenu --------------------------------------------------------------------

plasma_global!(OrgKdeKwinAppmenuManager);
impl Dispatch<OrgKdeKwinAppmenuManager, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &OrgKdeKwinAppmenuManager,
        request: org_kde_kwin_appmenu_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_appmenu_manager::Request::Create { id, .. } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(OrgKdeKwinAppmenu, org_kde_kwin_appmenu::Request);

// --- palette --------------------------------------------------------------------

plasma_global!(OrgKdeKwinServerDecorationPaletteManager);
impl Dispatch<OrgKdeKwinServerDecorationPaletteManager, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &OrgKdeKwinServerDecorationPaletteManager,
        request: org_kde_kwin_server_decoration_palette_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_server_decoration_palette_manager::Request::Create { id, .. } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(
    OrgKdeKwinServerDecorationPalette,
    org_kde_kwin_server_decoration_palette::Request
);

// --- plasma shell ---------------------------------------------------------------

plasma_global!(OrgKdePlasmaShell);
impl Dispatch<OrgKdePlasmaShell, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &OrgKdePlasmaShell,
        request: org_kde_plasma_shell::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_plasma_shell::Request::GetSurface { id, .. } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(OrgKdePlasmaSurface, org_kde_plasma_surface::Request);

// --- virtual desktop ------------------------------------------------------------

plasma_global!(OrgKdePlasmaVirtualDesktopManagement);
impl Dispatch<OrgKdePlasmaVirtualDesktopManagement, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &OrgKdePlasmaVirtualDesktopManagement,
        request: org_kde_plasma_virtual_desktop_management::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_plasma_virtual_desktop_management::Request::GetVirtualDesktop {
                id, ..
            } => {
                let desk = data_init.init(id, ());
                desk.name(String::from("Desktop 1"));
                desk.done();
            }
            org_kde_plasma_virtual_desktop_management::Request::RequestCreateVirtualDesktop {
                ..
            } => {}
            org_kde_plasma_virtual_desktop_management::Request::RequestRemoveVirtualDesktop {
                ..
            } => {}
            _ => {
                let _ = resource;
            }
        }
    }
}
plasma_noop!(
    OrgKdePlasmaVirtualDesktop,
    org_kde_plasma_virtual_desktop::Request
);

// --- window management ----------------------------------------------------------

plasma_global!(OrgKdePlasmaWindowManagement);
impl Dispatch<OrgKdePlasmaWindowManagement, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &OrgKdePlasmaWindowManagement,
        request: org_kde_plasma_window_management::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_plasma_window_management::Request::GetWindow { id, .. }
            | org_kde_plasma_window_management::Request::GetWindowByUuid { id, .. } => {
                data_init.init(id, ());
            }
            org_kde_plasma_window_management::Request::GetStackingOrder { stacking_order } => {
                data_init.init(stacking_order, ());
            }
            org_kde_plasma_window_management::Request::ShowDesktop { .. } => {}
            _ => {}
        }
    }
}
plasma_noop!(OrgKdePlasmaWindow, org_kde_plasma_window::Request);
plasma_noop!(
    OrgKdePlasmaActivationFeedback,
    org_kde_plasma_activation_feedback::Request
);
plasma_noop!(OrgKdePlasmaActivation, org_kde_plasma_activation::Request);
plasma_noop!(
    OrgKdePlasmaStackingOrder,
    org_kde_plasma_stacking_order::Request
);

// --- output management ----------------------------------------------------------

plasma_global!(OrgKdeKwinOutputmanagement);
impl Dispatch<OrgKdeKwinOutputmanagement, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &OrgKdeKwinOutputmanagement,
        request: org_kde_kwin_outputmanagement::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_outputmanagement::Request::CreateConfiguration { id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(
    OrgKdeKwinOutputconfiguration,
    org_kde_kwin_outputconfiguration::Request
);

plasma_global!(KdeOutputManagementV2);
impl Dispatch<KdeOutputManagementV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &KdeOutputManagementV2,
        request: kde_output_management_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            kde_output_management_v2::Request::CreateConfiguration { id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(KdeOutputConfigurationV2, kde_output_configuration_v2::Request);

// --- screen edge ----------------------------------------------------------------

plasma_global!(KdeScreenEdgeManagerV1);
impl Dispatch<KdeScreenEdgeManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &KdeScreenEdgeManagerV1,
        request: kde_screen_edge_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            kde_screen_edge_manager_v1::Request::GetAutoHideScreenEdge { id, .. } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}
plasma_noop!(
    KdeAutoHideScreenEdgeV1,
    kde_auto_hide_screen_edge_v1::Request
);

// --- screencast -----------------------------------------------------------------

plasma_global!(ZkdeScreencastUnstableV1);
impl Dispatch<ZkdeScreencastUnstableV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZkdeScreencastUnstableV1,
        request: zkde_screencast_unstable_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zkde_screencast_unstable_v1::Request::StreamOutput { stream, .. }
            | zkde_screencast_unstable_v1::Request::StreamWindow { stream, .. }
            | zkde_screencast_unstable_v1::Request::StreamVirtualOutput { stream, .. }
            | zkde_screencast_unstable_v1::Request::StreamRegion { stream, .. } => {
                let s = data_init.init(stream, ());
                s.closed();
            }
            _ => {}
        }
    }
}
plasma_noop!(
    ZkdeScreencastStreamUnstableV1,
    zkde_screencast_stream_unstable_v1::Request
);

// --- external brightness --------------------------------------------------------

plasma_global!(KdeExternalBrightnessV1);
impl Dispatch<KdeExternalBrightnessV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &KdeExternalBrightnessV1,
        request: kde_external_brightness_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            kde_external_brightness_v1::Request::CreateBrightnessControl { id } => {
                data_init.init(id, ());
            }
            kde_external_brightness_v1::Request::Destroy => {}
            _ => {}
        }
    }
}
plasma_noop!(
    KdeExternalBrightnessDeviceV1,
    kde_external_brightness_device_v1::Request
);

/// Register Plasma Missing globals.
pub fn register(dh: &DisplayHandle) {
    dh.create_global::<CompositorState, OrgKdePlasmaShell, ()>(8, ());
    dh.create_global::<CompositorState, OrgKdePlasmaWindowManagement, ()>(18, ());
    dh.create_global::<CompositorState, OrgKdePlasmaVirtualDesktopManagement, ()>(2, ());
    dh.create_global::<CompositorState, OrgKdeKwinAppmenuManager, ()>(1, ());
    dh.create_global::<CompositorState, OrgKdeKwinFakeInput, ()>(5, ());
    dh.create_global::<CompositorState, OrgKdeKwinKeystate, ()>(5, ());
    dh.create_global::<CompositorState, KdeLockscreenOverlayV1, ()>(1, ());
    dh.create_global::<CompositorState, KdeOutputManagementV2, ()>(1, ());
    dh.create_global::<CompositorState, KdeOutputDeviceV2, ()>(1, ());
    dh.create_global::<CompositorState, KdeOutputOrderV1, ()>(1, ());
    dh.create_global::<CompositorState, KdePrimaryOutputV1, ()>(2, ());
    dh.create_global::<CompositorState, KdeScreenEdgeManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZkdeScreencastUnstableV1, ()>(4, ());
    dh.create_global::<CompositorState, OrgKdeKwinServerDecorationPaletteManager, ()>(1, ());
    dh.create_global::<CompositorState, KdeExternalBrightnessV1, ()>(1, ());
    dh.create_global::<CompositorState, OrgKdeKwinOutputmanagement, ()>(4, ());
    dh.create_global::<CompositorState, OrgKdeKwinOutputdevice, ()>(1, ());
}
