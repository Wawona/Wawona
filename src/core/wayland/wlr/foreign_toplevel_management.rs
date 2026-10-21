use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol::wlroots::wlr_foreign_toplevel_management_unstable_v1::{
    zwlr_foreign_toplevel_handle_v1, zwlr_foreign_toplevel_manager_v1,
};

type ForeignHandle = zwlr_foreign_toplevel_handle_v1::ZwlrForeignToplevelHandleV1;

pub struct ForeignToplevelManagerData;

impl GlobalDispatch<zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, ()>
    for CompositorState
{
    fn bind(
        state: &mut Self,
        handle: &DisplayHandle,
        client: &wayland_server::Client,
        resource: wayland_server::New<
            zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        >,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let manager: zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1 =
            data_init.init(resource, ());

        // Advertise all existing windows
        let window_ids: Vec<u32> = state.windows.keys().copied().collect();
        for window_id in window_ids {
            let Ok(handle_resource) = client
                .create_resource::<ForeignHandle, u32, CompositorState>(
                    handle,
                    manager.version(),
                    window_id,
                )
            else {
                continue;
            };
            manager.toplevel(&handle_resource);
            state.send_toplevel_info(&handle_resource, window_id);
            state
                .wlr
                .foreign_toplevel_handles
                .entry(window_id)
                .or_default()
                .push(handle_resource);
        }

        // Initial list complete for this bind (handles already sent .done).
        state.wlr.foreign_toplevel_managers.push(manager);
    }
}

impl Dispatch<zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, ()>
    for CompositorState
{
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1,
        request: zwlr_foreign_toplevel_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        if let zwlr_foreign_toplevel_manager_v1::Request::Stop = request {
            let id = resource.id();
            state.wlr.foreign_toplevel_managers.retain(|m| m.id() != id);
            resource.finished();
        }
    }
}

impl Dispatch<ForeignHandle, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &ForeignHandle,
        request: zwlr_foreign_toplevel_handle_v1::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        use crate::core::compositor::CompositorEvent;
        use zwlr_foreign_toplevel_handle_v1::Request;

        let window_id = *data;
        // A headless host has no platform window manager, so the core
        // applies requests itself. Otherwise maximize / activate / close go
        // through the host (fill-primary on iOS, AppKit zoom on macOS): do
        // not pre-configure here, that races the host resize.
        let headless = state.headless_host;
        let key = state.toplevel_key_for_window(window_id);
        match request {
            Request::SetMaximized => match key {
                Some(key) if headless => state.maximize_toplevel(key),
                _ => state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowMaximized {
                        window_id,
                        maximized: true,
                    }),
            },
            Request::UnsetMaximized => match key {
                Some(key) if headless => state.unmaximize_toplevel(key),
                _ => state
                    .pending_compositor_events
                    .push(CompositorEvent::WindowMaximized {
                        window_id,
                        maximized: false,
                    }),
            },
            Request::SetMinimized => {
                if let Some(key) = key {
                    state.minimize_toplevel(key);
                }
            }
            Request::UnsetMinimized => {
                if headless {
                    state.activate_window(window_id);
                } else {
                    state.unminimize_window(window_id);
                }
            }
            Request::Activate { seat: _ } => {
                if headless {
                    state.activate_window(window_id);
                } else {
                    state.set_focused_window(Some(window_id));
                    state
                        .pending_compositor_events
                        .push(CompositorEvent::WindowActivationRequested { window_id });
                }
            }
            Request::Close => {
                if headless {
                    state.close_window(window_id);
                } else {
                    state
                        .pending_compositor_events
                        .push(CompositorEvent::WindowCloseRequested { window_id });
                }
            }
            Request::SetRectangle { .. } => {
                // Informational hint for animations
            }
            Request::Destroy => {
                if let Some(handles) = state.wlr.foreign_toplevel_handles.get_mut(&window_id) {
                    handles.retain(|h| h.id() != resource.id());
                }
            }
            Request::SetFullscreen { output } => {
                if let Some(key) = key {
                    state.fullscreen_toplevel(key, output);
                }
            }
            Request::UnsetFullscreen => {
                if let Some(key) = key {
                    state.unfullscreen_toplevel(key);
                }
            }
            _ => {}
        }
    }
}

/// Advertise a newly mapped toplevel to every bound foreign-toplevel manager.
pub fn notify_toplevel_created(state: &mut CompositorState, window_id: u32) {
    let Some(dhandle) = state.smithay_runtime.display_handle.clone() else {
        return;
    };
    let managers: Vec<_> = state.wlr.foreign_toplevel_managers.clone();
    for manager in managers {
        let Some(client) = manager.client() else {
            continue;
        };
        let Ok(handle_resource) = client.create_resource::<ForeignHandle, u32, CompositorState>(
            &dhandle,
            manager.version(),
            window_id,
        ) else {
            continue;
        };
        manager.toplevel(&handle_resource);
        state.send_toplevel_info(&handle_resource, window_id);
        state
            .wlr
            .foreign_toplevel_handles
            .entry(window_id)
            .or_default()
            .push(handle_resource);
    }
}

/// Notify managers that a toplevel was destroyed.
pub fn notify_toplevel_destroyed(state: &mut CompositorState, window_id: u32) {
    if let Some(handles) = state.wlr.foreign_toplevel_handles.remove(&window_id) {
        for handle in handles {
            if handle.is_alive() {
                handle.closed();
            }
        }
    }
}

/// `zwlr_foreign_toplevel_handle_v1.state` array for the given flags.
pub fn foreign_state_array(
    maximized: bool,
    minimized: bool,
    activated: bool,
    fullscreen: bool,
) -> Vec<u8> {
    use zwlr_foreign_toplevel_handle_v1::State;
    [
        (maximized, State::Maximized),
        (minimized, State::Minimized),
        (activated, State::Activated),
        (fullscreen, State::Fullscreen),
    ]
    .into_iter()
    .filter(|(set, _)| *set)
    .flat_map(|(_, state)| (state as u32).to_ne_bytes())
    .collect()
}

impl CompositorState {
    /// Send title, app_id, state and `done` for `window_id` on one handle.
    fn send_toplevel_info(&self, handle: &ForeignHandle, window_id: u32) {
        let Some(window) = self.get_window(window_id) else {
            return;
        };
        let Ok(window) = window.read() else {
            return;
        };
        handle.title(window.title.clone());
        handle.app_id(window.app_id.clone());
        handle.state(foreign_state_array(
            window.maximized,
            window.minimized,
            window.activated,
            window.fullscreen,
        ));
        handle.done();
    }

    /// Re-publish a toplevel's title, app_id and state to every handle.
    pub(crate) fn refresh_foreign_toplevel(&self, window_id: u32) {
        let Some(handles) = self.wlr.foreign_toplevel_handles.get(&window_id) else {
            return;
        };
        for handle in handles.iter().filter(|h| h.is_alive()) {
            self.send_toplevel_info(handle, window_id);
        }
    }
}

/// Register zwlr_foreign_toplevel_manager_v1 global
pub fn register_foreign_toplevel_management(
    display: &DisplayHandle,
) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1, ()>(3, ())
}

#[cfg(test)]
mod tests {
    use super::foreign_state_array;

    #[test]
    fn foreign_state_array_should_encode_each_set_flag_as_native_u32() {
        let bytes = foreign_state_array(true, false, true, true);
        let states: Vec<u32> = bytes
            .chunks_exact(4)
            .map(|c| u32::from_ne_bytes([c[0], c[1], c[2], c[3]]))
            .collect();
        assert_eq!(states, vec![0, 2, 3]);
    }

    #[test]
    fn foreign_state_array_should_be_empty_without_flags() {
        assert!(foreign_state_array(false, false, false, false).is_empty());
    }
}
