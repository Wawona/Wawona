//! Auto-generated treeland protocol handlers.

mod treeland_capture_unstable_v1_protocol;
mod treeland_dde_shell_v1_protocol;
mod treeland_foreign_toplevel_manager_v1_protocol;
mod treeland_output_manager_v1_protocol;
mod treeland_personalization_manager_v1_protocol;
mod treeland_shortcut_manager_v1_protocol;
mod treeland_virtual_output_manager_v1_protocol;
mod treeland_wallpaper_color_v1_protocol;
mod treeland_wallpaper_manager_unstable_v1_protocol;
mod treeland_wallpaper_shell_unstable_v1_protocol;
mod treeland_window_management_v1_protocol;

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

use treeland_capture_unstable_v1_protocol::treeland_capture_session_v1::{self, TreelandCaptureSessionV1};
use treeland_capture_unstable_v1_protocol::treeland_capture_frame_v1::{self, TreelandCaptureFrameV1};
use treeland_capture_unstable_v1_protocol::treeland_capture_context_v1::{self, TreelandCaptureContextV1};
use treeland_capture_unstable_v1_protocol::treeland_capture_manager_v1::{self, TreelandCaptureManagerV1};
use treeland_dde_shell_v1_protocol::treeland_dde_shell_manager_v1::{self, TreelandDdeShellManagerV1};
use treeland_dde_shell_v1_protocol::treeland_window_overlap_checker::{self, TreelandWindowOverlapChecker};
use treeland_dde_shell_v1_protocol::treeland_dde_shell_surface_v1::{self, TreelandDdeShellSurfaceV1};
use treeland_dde_shell_v1_protocol::treeland_dde_active_v1::{self, TreelandDdeActiveV1};
use treeland_dde_shell_v1_protocol::treeland_multitaskview_v1::{self, TreelandMultitaskviewV1};
use treeland_dde_shell_v1_protocol::treeland_window_picker_v1::{self, TreelandWindowPickerV1};
use treeland_dde_shell_v1_protocol::treeland_lockscreen_v1::{self, TreelandLockscreenV1};
use treeland_foreign_toplevel_manager_v1_protocol::treeland_foreign_toplevel_manager_v1::{self, TreelandForeignToplevelManagerV1};
use treeland_foreign_toplevel_manager_v1_protocol::treeland_foreign_toplevel_handle_v1::{self, TreelandForeignToplevelHandleV1};
use treeland_foreign_toplevel_manager_v1_protocol::treeland_dock_preview_context_v1::{self, TreelandDockPreviewContextV1};
use treeland_output_manager_v1_protocol::treeland_output_manager_v1::{self, TreelandOutputManagerV1};
use treeland_output_manager_v1_protocol::treeland_output_color_control_v1::{self, TreelandOutputColorControlV1};
use treeland_personalization_manager_v1_protocol::treeland_personalization_manager_v1::{self, TreelandPersonalizationManagerV1};
use treeland_personalization_manager_v1_protocol::treeland_personalization_cursor_context_v1::{self, TreelandPersonalizationCursorContextV1};
use treeland_personalization_manager_v1_protocol::treeland_personalization_window_context_v1::{self, TreelandPersonalizationWindowContextV1};
use treeland_personalization_manager_v1_protocol::treeland_personalization_font_context_v1::{self, TreelandPersonalizationFontContextV1};
use treeland_personalization_manager_v1_protocol::treeland_personalization_appearance_context_v1::{self, TreelandPersonalizationAppearanceContextV1};
use treeland_shortcut_manager_v1_protocol::treeland_shortcut_manager_v1::{self, TreelandShortcutManagerV1};
use treeland_shortcut_manager_v1_protocol::treeland_shortcut_context_v1::{self, TreelandShortcutContextV1};
use treeland_virtual_output_manager_v1_protocol::treeland_virtual_output_manager_v1::{self, TreelandVirtualOutputManagerV1};
use treeland_virtual_output_manager_v1_protocol::treeland_virtual_output_v1::{self, TreelandVirtualOutputV1};
use treeland_wallpaper_color_v1_protocol::treeland_wallpaper_color_manager_v1::{self, TreelandWallpaperColorManagerV1};
use treeland_wallpaper_manager_unstable_v1_protocol::treeland_wallpaper_manager_v1::{self, TreelandWallpaperManagerV1};
use treeland_wallpaper_manager_unstable_v1_protocol::treeland_wallpaper_v1::{self, TreelandWallpaperV1};
use treeland_wallpaper_shell_unstable_v1_protocol::treeland_wallpaper_notifier_v1::{self, TreelandWallpaperNotifierV1};
use treeland_wallpaper_shell_unstable_v1_protocol::treeland_wallpaper_shell_v1::{self, TreelandWallpaperShellV1};
use treeland_wallpaper_shell_unstable_v1_protocol::treeland_wallpaper_surface_v1::{self, TreelandWallpaperSurfaceV1};
use treeland_window_management_v1_protocol::treeland_window_management_v1::{self, TreelandWindowManagementV1};

impl Dispatch<TreelandCaptureSessionV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandCaptureSessionV1,
        request: treeland_capture_session_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandCaptureFrameV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandCaptureFrameV1,
        request: treeland_capture_frame_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandCaptureContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandCaptureContextV1,
        request: treeland_capture_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_capture_context_v1::Request::Capture { frame } => {
                data_init.init(frame, ());
            }
            treeland_capture_context_v1::Request::CreateSession { session } => {
                data_init.init(session, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<TreelandCaptureManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandCaptureManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandCaptureManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandCaptureManagerV1,
        request: treeland_capture_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_capture_manager_v1::Request::GetContext { context } => {
                data_init.init(context, ());
            }
            _ => {}
        }
    }
}

impl GlobalDispatch<TreelandDdeShellManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandDdeShellManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandDdeShellManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandDdeShellManagerV1,
        request: treeland_dde_shell_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_dde_shell_manager_v1::Request::GetWindowOverlapChecker { id } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::GetShellSurface { id, surface: _ } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::GetTreelandDdeActive { id, seat: _ } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::GetTreelandMultitaskview { id } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::GetTreelandWindowPicker { id } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::GetTreelandLockscreen { id } => {
                data_init.init(id, ());
            }
            treeland_dde_shell_manager_v1::Request::SetXwindowPositionRelative { callback, wid: _, anchor: _, dx: _, dy: _ } => {
                data_init.init(callback, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandWindowOverlapChecker, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWindowOverlapChecker,
        request: treeland_window_overlap_checker::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandDdeShellSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandDdeShellSurfaceV1,
        request: treeland_dde_shell_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandDdeActiveV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandDdeActiveV1,
        request: treeland_dde_active_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandMultitaskviewV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandMultitaskviewV1,
        request: treeland_multitaskview_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandWindowPickerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWindowPickerV1,
        request: treeland_window_picker_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandLockscreenV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandLockscreenV1,
        request: treeland_lockscreen_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandForeignToplevelManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandForeignToplevelManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandForeignToplevelManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandForeignToplevelManagerV1,
        request: treeland_foreign_toplevel_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_foreign_toplevel_manager_v1::Request::GetDockPreviewContext { relative_surface: _, id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandForeignToplevelHandleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandForeignToplevelHandleV1,
        request: treeland_foreign_toplevel_handle_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandDockPreviewContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandDockPreviewContextV1,
        request: treeland_dock_preview_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandOutputManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandOutputManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandOutputManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandOutputManagerV1,
        request: treeland_output_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_output_manager_v1::Request::GetColorControl { id, output: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandOutputColorControlV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandOutputColorControlV1,
        request: treeland_output_color_control_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandPersonalizationManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandPersonalizationManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandPersonalizationManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandPersonalizationManagerV1,
        request: treeland_personalization_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_personalization_manager_v1::Request::GetWindowContext { id, surface: _ } => {
                data_init.init(id, ());
            }
            treeland_personalization_manager_v1::Request::GetCursorContext { id } => {
                data_init.init(id, ());
            }
            treeland_personalization_manager_v1::Request::GetFontContext { id } => {
                data_init.init(id, ());
            }
            treeland_personalization_manager_v1::Request::GetAppearanceContext { id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandPersonalizationCursorContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandPersonalizationCursorContextV1,
        request: treeland_personalization_cursor_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandPersonalizationWindowContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandPersonalizationWindowContextV1,
        request: treeland_personalization_window_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandPersonalizationFontContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandPersonalizationFontContextV1,
        request: treeland_personalization_font_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandPersonalizationAppearanceContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandPersonalizationAppearanceContextV1,
        request: treeland_personalization_appearance_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandShortcutManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandShortcutManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandShortcutManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandShortcutManagerV1,
        request: treeland_shortcut_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_shortcut_manager_v1::Request::RegisterShortcutContext { key: _, id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandShortcutContextV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandShortcutContextV1,
        request: treeland_shortcut_context_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandVirtualOutputManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandVirtualOutputManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandVirtualOutputManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandVirtualOutputManagerV1,
        request: treeland_virtual_output_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_virtual_output_manager_v1::Request::CreateVirtualOutput { id, name: _, outputs: _ } => {
                data_init.init(id, ());
            }
            treeland_virtual_output_manager_v1::Request::GetVirtualOutput { name: _, id } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandVirtualOutputV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandVirtualOutputV1,
        request: treeland_virtual_output_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandWallpaperColorManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandWallpaperColorManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandWallpaperColorManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperColorManagerV1,
        request: treeland_wallpaper_color_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandWallpaperManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandWallpaperManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandWallpaperManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperManagerV1,
        request: treeland_wallpaper_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_wallpaper_manager_v1::Request::GetTreelandWallpaper { id, output: _, surface: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandWallpaperV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperV1,
        request: treeland_wallpaper_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl Dispatch<TreelandWallpaperNotifierV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperNotifierV1,
        request: treeland_wallpaper_notifier_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandWallpaperShellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandWallpaperShellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandWallpaperShellV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperShellV1,
        request: treeland_wallpaper_shell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            treeland_wallpaper_shell_v1::Request::GetTreelandWallpaperSurface { id, surface: _, file_source: _ } => {
                data_init.init(id, ());
            }
            _ => {}
        }
    }
}

impl Dispatch<TreelandWallpaperSurfaceV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWallpaperSurfaceV1,
        request: treeland_wallpaper_surface_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        let _ = (request, data_init);
    }
}

impl GlobalDispatch<TreelandWindowManagementV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<TreelandWindowManagementV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<TreelandWindowManagementV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &TreelandWindowManagementV1,
        request: treeland_window_management_v1::Request,
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
    dh.create_global::<CompositorState, TreelandCaptureManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, TreelandDdeShellManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandForeignToplevelManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandOutputManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandPersonalizationManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandShortcutManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandVirtualOutputManagerV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandWallpaperColorManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, TreelandWallpaperManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, TreelandWallpaperShellV1, ()>(2, ());
    dh.create_global::<CompositorState, TreelandWindowManagementV1, ()>(1, ());
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered treeland protocol globals");
}

#[cfg(test)]
mod tests {
    #[test]
    fn treeland_register_compiles() {
        assert!(true);
    }
}
