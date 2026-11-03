//! Hyprland protocol globals (wayland-protocols-hyprland).
//!
//! Portable Rust core: track request state; hosts apply CTM / focus-grab /
//! shortcuts / export via capability hooks.

use std::collections::HashMap;

use wayland_protocols_hyprland::{
    ctm_control::v1::server::{
        hyprland_ctm_control_manager_v1::{self, HyprlandCtmControlManagerV1},
    },
    focus_grab::v1::server::{
        hyprland_focus_grab_manager_v1::{self, HyprlandFocusGrabManagerV1},
        hyprland_focus_grab_v1::{self, HyprlandFocusGrabV1},
    },
    global_shortcuts::v1::server::{
        hyprland_global_shortcut_v1::{self, HyprlandGlobalShortcutV1},
        hyprland_global_shortcuts_manager_v1::{self, HyprlandGlobalShortcutsManagerV1},
    },
    lock_notify::v1::server::{
        hyprland_lock_notification_v1::{self, HyprlandLockNotificationV1},
        hyprland_lock_notifier_v1::{self, HyprlandLockNotifierV1},
    },
    surface::v1::server::{
        hyprland_surface_manager_v1::{self, HyprlandSurfaceManagerV1},
        hyprland_surface_v1::{self, HyprlandSurfaceV1},
    },
    toplevel_export::v1::server::{
        hyprland_toplevel_export_frame_v1::{self, HyprlandToplevelExportFrameV1},
        hyprland_toplevel_export_manager_v1::{self, HyprlandToplevelExportManagerV1},
    },
    toplevel_mapping::v1::server::{
        hyprland_toplevel_mapping_manager_v1::{self, HyprlandToplevelMappingManagerV1},
        hyprland_toplevel_window_mapping_handle_v1::{
            self, HyprlandToplevelWindowMappingHandleV1,
        },
    },
};
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;
use crate::core::wayland::policy;
use crate::core::wayland::protocol_proofs::hyprland_shortcut_rejects_duplicate;

#[derive(Debug, Default)]
pub struct HyprlandState {
    /// "app_id\0id" → shortcut resource protocol id
    pub shortcuts: HashMap<String, u32>,
    pub lock_notifications: Vec<u32>,
    pub session_locked: bool,
}

fn shortcut_key(app_id: &str, id: &str) -> String {
    format!("{app_id}\0{id}")
}

// ---------------------------------------------------------------------------
// CTM control
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandCtmControlManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandCtmControlManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandCtmControlManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandCtmControlManagerV1,
        request: hyprland_ctm_control_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_ctm_control_manager_v1::Request::SetCtmForOutput { .. } => {
                // Host applies color transform matrix when capable.
            }
            hyprland_ctm_control_manager_v1::Request::Commit => {}
            hyprland_ctm_control_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Focus grab
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandFocusGrabManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandFocusGrabManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandFocusGrabManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandFocusGrabManagerV1,
        request: hyprland_focus_grab_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_focus_grab_manager_v1::Request::CreateGrab { grab } => {
                let _g = data_init.init(grab, ());
            }
            hyprland_focus_grab_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandFocusGrabV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandFocusGrabV1,
        request: hyprland_focus_grab_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_focus_grab_v1::Request::AddSurface { .. } => {}
            hyprland_focus_grab_v1::Request::Commit => {}
            hyprland_focus_grab_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Global shortcuts
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandGlobalShortcutsManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandGlobalShortcutsManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandGlobalShortcutsManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &HyprlandGlobalShortcutsManagerV1,
        request: hyprland_global_shortcuts_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_global_shortcuts_manager_v1::Request::RegisterShortcut {
                shortcut,
                id,
                app_id,
                description: _,
                trigger_description: _,
            } => {
                let key = shortcut_key(&app_id, &id);
                let already = state.hyprland.shortcuts.contains_key(&key);
                if hyprland_shortcut_rejects_duplicate(already) {
                    resource.post_error(
                        hyprland_global_shortcuts_manager_v1::Error::AlreadyTaken,
                        "app_id + id combination already registered",
                    );
                    return;
                }
                let sc = data_init.init(shortcut, key.clone());
                state
                    .hyprland
                    .shortcuts
                    .insert(key, sc.id().protocol_id());
            }
            hyprland_global_shortcuts_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandGlobalShortcutV1, String> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &HyprlandGlobalShortcutV1,
        request: hyprland_global_shortcut_v1::Request,
        key: &String,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_global_shortcut_v1::Request::Destroy => {
                state.hyprland.shortcuts.remove(key);
            }
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Lock notify
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandLockNotifierV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandLockNotifierV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandLockNotifierV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &HyprlandLockNotifierV1,
        request: hyprland_lock_notifier_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_lock_notifier_v1::Request::GetLockNotification { id } => {
                let n: HyprlandLockNotificationV1 = data_init.init(id, ());
                let nid = n.id().protocol_id();
                state.hyprland.lock_notifications.push(nid);
                if state.hyprland.session_locked {
                    n.locked();
                } else {
                    n.unlocked();
                }
            }
            hyprland_lock_notifier_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandLockNotificationV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &HyprlandLockNotificationV1,
        request: hyprland_lock_notification_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_lock_notification_v1::Request::Destroy => {
                let id = resource.id().protocol_id();
                state.hyprland.lock_notifications.retain(|n| *n != id);
            }
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Surface
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandSurfaceManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandSurfaceManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandSurfaceManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandSurfaceManagerV1,
        request: hyprland_surface_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_surface_manager_v1::Request::GetHyprlandSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _s = data_init.init(id, surface_id);
            }
            hyprland_surface_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandSurfaceV1, u32> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandSurfaceV1,
        request: hyprland_surface_v1::Request,
        _surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_surface_v1::Request::SetOpacity { .. } => {}
            hyprland_surface_v1::Request::SetVisibleRegion { .. } => {}
            hyprland_surface_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Toplevel export
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandToplevelExportManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandToplevelExportManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandToplevelExportManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandToplevelExportManagerV1,
        request: hyprland_toplevel_export_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_toplevel_export_manager_v1::Request::CaptureToplevel { frame, .. }
            | hyprland_toplevel_export_manager_v1::Request::CaptureToplevelWithWlrToplevelHandle {
                frame,
                ..
            } => {
                let frame_res: HyprlandToplevelExportFrameV1 = data_init.init(frame, ());
                // Without a host capture capability, fail the frame.
                frame_res.failed();
            }
            hyprland_toplevel_export_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandToplevelExportFrameV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandToplevelExportFrameV1,
        request: hyprland_toplevel_export_frame_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_toplevel_export_frame_v1::Request::Copy { .. } => {}
            hyprland_toplevel_export_frame_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// ---------------------------------------------------------------------------
// Toplevel mapping
// ---------------------------------------------------------------------------

impl GlobalDispatch<HyprlandToplevelMappingManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<HyprlandToplevelMappingManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<HyprlandToplevelMappingManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandToplevelMappingManagerV1,
        request: hyprland_toplevel_mapping_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_toplevel_mapping_manager_v1::Request::GetWindowForToplevel {
                handle,
                ..
            }
            | hyprland_toplevel_mapping_manager_v1::Request::GetWindowForToplevelWlr {
                handle,
                ..
            } => {
                let _h: HyprlandToplevelWindowMappingHandleV1 = data_init.init(handle, ());
            }
            hyprland_toplevel_mapping_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<HyprlandToplevelWindowMappingHandleV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &HyprlandToplevelWindowMappingHandleV1,
        request: hyprland_toplevel_window_mapping_handle_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            hyprland_toplevel_window_mapping_handle_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

/// Register Hyprland globals when the profile allows desktop extensions.
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_desktop_extensions(state.protocol_profile) {
        return;
    }
    dh.create_global::<CompositorState, HyprlandCtmControlManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandFocusGrabManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandGlobalShortcutsManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandLockNotifierV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandSurfaceManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandToplevelExportManagerV1, ()>(1, ());
    dh.create_global::<CompositorState, HyprlandToplevelMappingManagerV1, ()>(1, ());
    crate::wlog!(
        crate::util::logging::COMPOSITOR,
        "Registered Hyprland protocol globals"
    );
}

#[cfg(test)]
mod tests {
    use crate::core::wayland::protocol_proofs::hyprland_shortcut_rejects_duplicate;

    #[test]
    fn duplicate_shortcut_rejected() {
        assert!(hyprland_shortcut_rejects_duplicate(true));
        assert!(!hyprland_shortcut_rejects_duplicate(false));
    }
}
