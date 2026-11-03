//! COSMIC Wayland protocols (vendored XML under `protocols/cosmic/`).

mod a11y_protocol;
mod atspi_protocol;
mod image_capture_protocol;
mod image_source_protocol;
mod output_management_protocol;
mod overlap_protocol;
mod screencopy_v1_protocol;
mod screencopy_v2_protocol;
mod toplevel_info_protocol;
mod toplevel_management_protocol;
mod workspace_v1_protocol;
mod workspace_v2_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource, WEnum,
};

use crate::core::state::CompositorState;
use crate::core::wayland::ext::image_capture_source::ImageCaptureSourceData;
use crate::core::wayland::policy;

use a11y_protocol::cosmic_a11y_manager_v1::{self, CosmicA11yManagerV1};
use atspi_protocol::cosmic_atspi_manager_v1::{self, CosmicAtspiManagerV1};
use image_capture_protocol::zcosmic_workspace_image_capture_source_manager_v1::{
    self, ZcosmicWorkspaceImageCaptureSourceManagerV1,
};
use image_source_protocol::zcosmic_ext_workspace_image_source_manager_v1::{
    self, ZcosmicExtWorkspaceImageSourceManagerV1,
};
use image_source_protocol::zcosmic_image_source_v1::{self, ZcosmicImageSourceV1};
use image_source_protocol::zcosmic_output_image_source_manager_v1::{
    self, ZcosmicOutputImageSourceManagerV1,
};
use image_source_protocol::zcosmic_toplevel_image_source_manager_v1::{
    self, ZcosmicToplevelImageSourceManagerV1,
};
use image_source_protocol::zcosmic_workspace_image_source_manager_v1::{
    self, ZcosmicWorkspaceImageSourceManagerV1,
};
use screencopy_v1_protocol::zcosmic_screencopy_manager_v1::{self, ZcosmicScreencopyManagerV1};
use screencopy_v1_protocol::zcosmic_screencopy_session_v1::{self, ZcosmicScreencopySessionV1};
use screencopy_v2_protocol::zcosmic_screencopy_cursor_session_v2::{
    self, ZcosmicScreencopyCursorSessionV2,
};
use screencopy_v2_protocol::zcosmic_screencopy_frame_v2::{self, ZcosmicScreencopyFrameV2};
use screencopy_v2_protocol::zcosmic_screencopy_manager_v2::{self, ZcosmicScreencopyManagerV2};
use screencopy_v2_protocol::zcosmic_screencopy_session_v2::{self, ZcosmicScreencopySessionV2};
use output_management_protocol::zcosmic_output_configuration_head_v1::{
    self, ZcosmicOutputConfigurationHeadV1,
};
use output_management_protocol::zcosmic_output_configuration_v1::{
    self, ZcosmicOutputConfigurationV1,
};
use output_management_protocol::zcosmic_output_head_v1::{self, ZcosmicOutputHeadV1};
use output_management_protocol::zcosmic_output_manager_v1::{self, ZcosmicOutputManagerV1};
use overlap_protocol::zcosmic_overlap_notification_v1::{self, ZcosmicOverlapNotificationV1};
use overlap_protocol::zcosmic_overlap_notify_v1::{self, ZcosmicOverlapNotifyV1};
use toplevel_info_protocol::zcosmic_toplevel_handle_v1::{self, ZcosmicToplevelHandleV1};
use toplevel_info_protocol::zcosmic_toplevel_info_v1::{self, ZcosmicToplevelInfoV1};
use toplevel_management_protocol::zcosmic_toplevel_manager_v1::{self, ZcosmicToplevelManagerV1};
use workspace_v1_protocol::zcosmic_workspace_group_handle_v1::{
    self, ZcosmicWorkspaceGroupHandleV1,
};
use workspace_v1_protocol::zcosmic_workspace_handle_v1::{self, ZcosmicWorkspaceHandleV1};
use workspace_v1_protocol::zcosmic_workspace_manager_v1::{self, ZcosmicWorkspaceManagerV1};
use workspace_v2_protocol::zcosmic_workspace_handle_v2::{self, ZcosmicWorkspaceHandleV2};
use workspace_v2_protocol::zcosmic_workspace_manager_v2::{self, ZcosmicWorkspaceManagerV2};

#[derive(Debug, Default)]
pub struct CosmicState {
    pub magnifier: bool,
}

// ---------------------------------------------------------------------------
// a11y
// ---------------------------------------------------------------------------

impl GlobalDispatch<CosmicA11yManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<CosmicA11yManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<CosmicA11yManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &CosmicA11yManagerV1,
        request: cosmic_a11y_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            cosmic_a11y_manager_v1::Request::SetMagnifier { active } => {
                state.cosmic.magnifier = matches!(
                    active,
                    WEnum::Value(cosmic_a11y_manager_v1::ActiveState::Enabled)
                );
                tracing::debug!("cosmic a11y magnifier={}", state.cosmic.magnifier);
            }
            cosmic_a11y_manager_v1::Request::SetScreenFilter { .. } => {}
            cosmic_a11y_manager_v1::Request::SetScreenFilter2 { .. } => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// workspace v1
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicWorkspaceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        handle: &DisplayHandle,
        client: &Client,
        resource: New<ZcosmicWorkspaceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let mgr = data_init.init(resource, ());
        if let Ok(group) =
            client.create_resource::<ZcosmicWorkspaceGroupHandleV1, (), CompositorState>(
                handle,
                mgr.version(),
                (),
            )
        {
            mgr.workspace_group(&group);
            if let Ok(ws) =
                client.create_resource::<ZcosmicWorkspaceHandleV1, (), CompositorState>(
                    handle,
                    mgr.version(),
                    (),
                )
            {
                group.workspace(&ws);
                ws.name(String::from("Workspace 1"));
            }
        }
        mgr.done();
    }
}

impl Dispatch<ZcosmicWorkspaceManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceManagerV1,
        request: zcosmic_workspace_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_manager_v1::Request::Commit => {}
            zcosmic_workspace_manager_v1::Request::Stop => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicWorkspaceGroupHandleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceGroupHandleV1,
        request: zcosmic_workspace_group_handle_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_group_handle_v1::Request::CreateWorkspace { .. } => {}
            zcosmic_workspace_group_handle_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicWorkspaceHandleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceHandleV1,
        request: zcosmic_workspace_handle_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_handle_v1::Request::Activate => {}
            zcosmic_workspace_handle_v1::Request::Deactivate => {}
            zcosmic_workspace_handle_v1::Request::Remove => {}
            zcosmic_workspace_handle_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// workspace v2
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicWorkspaceManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicWorkspaceManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicWorkspaceManagerV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceManagerV2,
        request: zcosmic_workspace_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_manager_v2::Request::GetCosmicWorkspace {
                cosmic_workspace,
                workspace: _,
            } => {
                let handle = data_init.init(cosmic_workspace, ());
                handle.capabilities(
                    zcosmic_workspace_handle_v2::WorkspaceCapabilities::empty().into(),
                );
                handle.tiling_state(zcosmic_workspace_handle_v2::TilingState::FloatingOnly);
            }
            zcosmic_workspace_manager_v2::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicWorkspaceHandleV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceHandleV2,
        request: zcosmic_workspace_handle_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_handle_v2::Request::Destroy => {}
            zcosmic_workspace_handle_v2::Request::Rename { .. } => {}
            zcosmic_workspace_handle_v2::Request::SetTilingState { .. } => {}
            zcosmic_workspace_handle_v2::Request::MoveBefore { .. } => {}
            zcosmic_workspace_handle_v2::Request::MoveAfter { .. } => {}
            zcosmic_workspace_handle_v2::Request::Pin => {}
            zcosmic_workspace_handle_v2::Request::Unpin => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// image capture source
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicWorkspaceImageCaptureSourceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicWorkspaceImageCaptureSourceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicWorkspaceImageCaptureSourceManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicWorkspaceImageCaptureSourceManagerV1,
        request: zcosmic_workspace_image_capture_source_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_workspace_image_capture_source_manager_v1::Request::CreateSource {
                source,
                output: _,
            } => {
                // Portable core: accept the object; host capture is capability-gated.
                data_init.init(source, ImageCaptureSourceData { output_id: 0 });
            }
            zcosmic_workspace_image_capture_source_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// output management
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicOutputManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicOutputManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicOutputManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOutputManagerV1,
        request: zcosmic_output_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_output_manager_v1::Request::GetHead { extended, head: _ } => {
                data_init.init(extended, ());
            }
            zcosmic_output_manager_v1::Request::GetConfiguration {
                extended,
                config: _,
            } => {
                data_init.init(extended, ());
            }
            zcosmic_output_manager_v1::Request::GetConfigurationHead {
                extended,
                config_head: _,
            } => {
                data_init.init(extended, ());
            }
            zcosmic_output_manager_v1::Request::Release => {}
            zcosmic_output_manager_v1::Request::SetXwaylandPrimary { .. } => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicOutputHeadV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOutputHeadV1,
        request: zcosmic_output_head_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_output_head_v1::Request::Release => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicOutputConfigurationV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOutputConfigurationV1,
        request: zcosmic_output_configuration_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_output_configuration_v1::Request::MirrorHead { id, .. } => {
                // Creates a zwlr_output_configuration_head_v1; host applies mirror.
                data_init.init(id, ());
            }
            zcosmic_output_configuration_v1::Request::Release => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicOutputConfigurationHeadV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOutputConfigurationHeadV1,
        request: zcosmic_output_configuration_head_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_output_configuration_head_v1::Request::SetScale1000 { .. } => {}
            zcosmic_output_configuration_head_v1::Request::SetAdaptiveSyncExt { .. } => {}
            zcosmic_output_configuration_head_v1::Request::Release => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// overlap notify
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicOverlapNotifyV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicOverlapNotifyV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicOverlapNotifyV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOverlapNotifyV1,
        request: zcosmic_overlap_notify_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_overlap_notify_v1::Request::NotifyOnOverlap {
                overlap_notification,
                layer_surface: _,
            } => {
                data_init.init(overlap_notification, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicOverlapNotificationV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicOverlapNotificationV1,
        request: zcosmic_overlap_notification_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_overlap_notification_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// toplevel info
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicToplevelInfoV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicToplevelInfoV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let info = data_init.init(resource, ());
        if info.version() >= 2 {
            info.done();
        }
    }
}

impl Dispatch<ZcosmicToplevelInfoV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        resource: &ZcosmicToplevelInfoV1,
        request: zcosmic_toplevel_info_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_toplevel_info_v1::Request::Stop => {
                resource.finished();
            }
            zcosmic_toplevel_info_v1::Request::GetCosmicToplevel {
                cosmic_toplevel,
                foreign_toplevel: _,
            } => {
                let handle = data_init.init(cosmic_toplevel, ());
                handle.done();
            }
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicToplevelHandleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicToplevelHandleV1,
        request: zcosmic_toplevel_handle_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_toplevel_handle_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// toplevel management
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicToplevelManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicToplevelManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let mgr = data_init.init(resource, ());
        // Empty capability set: portable core accepts requests as no-ops.
        mgr.capabilities(Vec::new());
    }
}

impl Dispatch<ZcosmicToplevelManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicToplevelManagerV1,
        request: zcosmic_toplevel_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_toplevel_manager_v1::Request::Destroy => {}
            zcosmic_toplevel_manager_v1::Request::Close { .. } => {}
            zcosmic_toplevel_manager_v1::Request::Activate { .. } => {}
            zcosmic_toplevel_manager_v1::Request::SetMaximized { .. } => {}
            zcosmic_toplevel_manager_v1::Request::UnsetMaximized { .. } => {}
            zcosmic_toplevel_manager_v1::Request::SetMinimized { .. } => {}
            zcosmic_toplevel_manager_v1::Request::UnsetMinimized { .. } => {}
            zcosmic_toplevel_manager_v1::Request::SetFullscreen { .. } => {}
            zcosmic_toplevel_manager_v1::Request::UnsetFullscreen { .. } => {}
            zcosmic_toplevel_manager_v1::Request::MoveToWorkspace { .. } => {}
            zcosmic_toplevel_manager_v1::Request::SetSticky { .. } => {}
            zcosmic_toplevel_manager_v1::Request::UnsetSticky { .. } => {}
            zcosmic_toplevel_manager_v1::Request::MoveToExtWorkspace { .. } => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// atspi
// ---------------------------------------------------------------------------

impl GlobalDispatch<CosmicAtspiManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<CosmicAtspiManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<CosmicAtspiManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &CosmicAtspiManagerV1,
        request: cosmic_atspi_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            cosmic_atspi_manager_v1::Request::Destroy => {}
            cosmic_atspi_manager_v1::Request::AddKeyGrab { .. } => {}
            cosmic_atspi_manager_v1::Request::RemoveKeyGrab { .. } => {}
            cosmic_atspi_manager_v1::Request::GrabKeyboard => {}
            cosmic_atspi_manager_v1::Request::UngrabKeyboard => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// image source managers
// ---------------------------------------------------------------------------

macro_rules! cosmic_image_source_manager {
    ($global:ty, $req_mod:ident) => {
        impl GlobalDispatch<$global, ()> for CompositorState {
            fn bind(
                _state: &mut Self,
                _handle: &DisplayHandle,
                _client: &Client,
                resource: New<$global>,
                _global_data: &(),
                data_init: &mut DataInit<'_, Self>,
            ) {
                data_init.init(resource, ());
            }
        }

        impl Dispatch<$global, ()> for CompositorState {
            fn request(
                _state: &mut Self,
                _client: &Client,
                _resource: &$global,
                request: $req_mod::Request,
                _data: &(),
                _dhandle: &DisplayHandle,
                data_init: &mut DataInit<'_, Self>,
            ) {
                match request {
                    $req_mod::Request::CreateSource { source, .. } => {
                        data_init.init(source, ());
                    }
                    $req_mod::Request::Destroy => {}
                    _ => {}
                }
            }
        }
    };
}

cosmic_image_source_manager!(
    ZcosmicOutputImageSourceManagerV1,
    zcosmic_output_image_source_manager_v1
);
cosmic_image_source_manager!(
    ZcosmicWorkspaceImageSourceManagerV1,
    zcosmic_workspace_image_source_manager_v1
);
cosmic_image_source_manager!(
    ZcosmicExtWorkspaceImageSourceManagerV1,
    zcosmic_ext_workspace_image_source_manager_v1
);
cosmic_image_source_manager!(
    ZcosmicToplevelImageSourceManagerV1,
    zcosmic_toplevel_image_source_manager_v1
);

impl Dispatch<ZcosmicImageSourceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicImageSourceV1,
        request: zcosmic_image_source_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_image_source_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// screencopy v1
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicScreencopyManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicScreencopyManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicScreencopyManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopyManagerV1,
        request: zcosmic_screencopy_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_manager_v1::Request::CaptureOutput { session, .. }
            | zcosmic_screencopy_manager_v1::Request::CaptureWorkspace { session, .. }
            | zcosmic_screencopy_manager_v1::Request::CaptureToplevel { session, .. } => {
                let s = data_init.init(session, ());
                // Portable core: fail closed until host capture is wired.
                s.failed(zcosmic_screencopy_session_v1::FailureReason::Unspec);
            }
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicScreencopySessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopySessionV1,
        request: zcosmic_screencopy_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_session_v1::Request::CaptureCursor { .. } => {}
            zcosmic_screencopy_session_v1::Request::AttachBuffer { .. } => {}
            zcosmic_screencopy_session_v1::Request::Commit { .. } => {}
            zcosmic_screencopy_session_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// screencopy v2
// ---------------------------------------------------------------------------

impl GlobalDispatch<ZcosmicScreencopyManagerV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZcosmicScreencopyManagerV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<ZcosmicScreencopyManagerV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopyManagerV2,
        request: zcosmic_screencopy_manager_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_manager_v2::Request::CreateSession { session, .. } => {
                data_init.init(session, ());
            }
            zcosmic_screencopy_manager_v2::Request::CreatePointerCursorSession {
                session, ..
            } => {
                data_init.init(session, ());
            }
            zcosmic_screencopy_manager_v2::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicScreencopySessionV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopySessionV2,
        request: zcosmic_screencopy_session_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_session_v2::Request::CreateFrame { frame } => {
                let f = data_init.init(frame, ());
                f.failed(zcosmic_screencopy_frame_v2::FailureReason::Unknown);
            }
            zcosmic_screencopy_session_v2::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicScreencopyFrameV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopyFrameV2,
        request: zcosmic_screencopy_frame_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_frame_v2::Request::Destroy => {}
            zcosmic_screencopy_frame_v2::Request::AttachBuffer { .. } => {}
            zcosmic_screencopy_frame_v2::Request::DamageBuffer { .. } => {}
            zcosmic_screencopy_frame_v2::Request::Capture => {}
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicScreencopyCursorSessionV2, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &ZcosmicScreencopyCursorSessionV2,
        request: zcosmic_screencopy_cursor_session_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zcosmic_screencopy_cursor_session_v2::Request::Destroy => {}
            zcosmic_screencopy_cursor_session_v2::Request::GetScreencopySession { session } => {
                data_init.init(session, ());
            }
            _ => {}
        }
    }
}

pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_desktop_extensions(state.protocol_profile) {
        return;
    }
    dh.create_global::<CompositorState, CosmicA11yManagerV1, ()>(3, ());
    dh.create_global::<CompositorState, CosmicAtspiManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicWorkspaceManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, ZcosmicWorkspaceManagerV2, ()>(2, ());
    dh.create_global::<CompositorState, ZcosmicWorkspaceImageCaptureSourceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicOutputImageSourceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicWorkspaceImageSourceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicExtWorkspaceImageSourceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicToplevelImageSourceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicOutputManagerV1, ()>(3, ());
    dh.create_global::<CompositorState, ZcosmicOverlapNotifyV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicToplevelInfoV1, ()>(3, ());
    dh.create_global::<CompositorState, ZcosmicToplevelManagerV1, ()>(4, ());
    dh.create_global::<CompositorState, ZcosmicScreencopyManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, ZcosmicScreencopyManagerV2, ()>(1, ());
    crate::wlog!(
        crate::util::logging::COMPOSITOR,
        "Registered COSMIC protocol globals"
    );
}

#[cfg(test)]
mod tests {
    #[test]
    fn cosmic_state_defaults() {
        let s = super::CosmicState::default();
        assert!(!s.magnifier);
    }
}
