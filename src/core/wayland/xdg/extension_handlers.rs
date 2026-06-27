//! Smithay delegate handlers for XDG desktop extension protocols.

use smithay::reexports::wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode;
use smithay::reexports::wayland_server::protocol::wl_surface::WlSurface;
use smithay::reexports::wayland_server::Resource;
use smithay::wayland::shell::xdg::decoration::XdgDecorationHandler;
use smithay::wayland::shell::xdg::dialog::XdgDialogHandler;
use smithay::wayland::shell::xdg::ToplevelSurface;
use smithay::wayland::xdg_activation::{XdgActivationHandler, XdgActivationState, XdgActivationToken, XdgActivationTokenData};
use smithay::wayland::xdg_foreign::XdgForeignHandler;
use smithay::wayland::xdg_system_bell::XdgSystemBellHandler;
use smithay::wayland::xdg_toplevel_icon::XdgToplevelIconHandler;
use smithay::wayland::xdg_toplevel_tag::XdgToplevelTagHandler;

use crate::core::compositor::CompositorEvent;
use crate::core::state::CompositorState;
use crate::core::wayland::xdg::decoration::{
    preferred_xdg_decoration_mode, window_id_for_toplevel,
};

impl XdgDecorationHandler for CompositorState {
    fn new_decoration(&mut self, toplevel: ToplevelSurface) {
        let Some(window_id) = window_id_for_toplevel(self, &toplevel) else {
            tracing::warn!("new_decoration: no window for toplevel");
            return;
        };

        let preferred = preferred_xdg_decoration_mode(self, window_id);
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(preferred);
        });
        toplevel.send_pending_configure();
        self.apply_decoration_mode_for_window(window_id, preferred);

        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Smithay new_decoration window {} mode {:?}",
            window_id,
            preferred
        );
    }

    fn request_mode(&mut self, toplevel: ToplevelSurface, mode: Mode) {
        let Some(window_id) = window_id_for_toplevel(self, &toplevel) else {
            return;
        };

        let weston_family = !matches!(
            self.decoration_policy,
            crate::core::state::DecorationPolicy::ForceServer
        ) && crate::core::wayland::xdg::decoration::is_weston_family_app(self, window_id);

        let actual_mode = if weston_family {
            if crate::core::wayland::xdg::decoration::weston_family_prefers_client_decorations(self) {
                Mode::ClientSide
            } else {
                Mode::ServerSide
            }
        } else {
            match self.decoration_policy {
                crate::core::state::DecorationPolicy::ForceServer => Mode::ServerSide,
                crate::core::state::DecorationPolicy::PreferServer => mode,
                crate::core::state::DecorationPolicy::PreferClient => Mode::ClientSide,
            }
        };

        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(actual_mode);
        });
        toplevel.send_pending_configure();
        self.apply_decoration_mode_for_window(window_id, actual_mode);
    }

    fn unset_mode(&mut self, toplevel: ToplevelSurface) {
        let Some(window_id) = window_id_for_toplevel(self, &toplevel) else {
            return;
        };

        let preferred = preferred_xdg_decoration_mode(self, window_id);
        toplevel.with_pending_state(|state| {
            state.decoration_mode = Some(preferred);
        });
        toplevel.send_pending_configure();
        self.apply_decoration_mode_for_window(window_id, preferred);
    }
}

impl XdgForeignHandler for CompositorState {
    fn xdg_foreign_state(&mut self) -> &mut smithay::wayland::xdg_foreign::XdgForeignState {
        self.smithay_runtime
            .xdg_foreign
            .as_mut()
            .expect("xdg foreign state must be initialized before dispatch")
    }
}

impl XdgActivationHandler for CompositorState {
    fn activation_state(&mut self) -> &mut XdgActivationState {
        self.smithay_runtime
            .xdg_activation
            .as_mut()
            .expect("xdg activation state must be initialized before dispatch")
    }

    fn request_activation(
        &mut self,
        token: XdgActivationToken,
        _token_data: XdgActivationTokenData,
        surface: WlSurface,
    ) {
        let surface_id = surface.id().protocol_id();
        tracing::debug!(
            "Activate request for surface {} with token {}",
            surface_id,
            token.as_str()
        );

        let window_id = self.surface_to_window.get(&surface_id).copied();
        if let Some(wid) = window_id {
            tracing::info!(
                "Activating window {} via xdg_activation token {}",
                wid,
                token.as_str()
            );
            self.pending_compositor_events
                .push(CompositorEvent::WindowActivationRequested { window_id: wid });
            self.set_focused_window(Some(wid));

            if let Some((cid, tl_proto_id)) = self.xdg_toplevel_key_for_wl_surface(&surface) {
                if let Some(tl) = self.xdg.toplevels.get_mut(&(cid.clone(), tl_proto_id)) {
                    tl.activated = true;
                    let (w, h) = (tl.width, tl.height);
                    self.send_toplevel_configure(cid, tl_proto_id, w, h);
                }
            }
        } else {
            tracing::warn!("Activation: no window found for surface {}", surface_id);
        }
    }
}

impl XdgDialogHandler for CompositorState {
    fn modal_changed(&mut self, toplevel: ToplevelSurface, is_modal: bool) {
        let Some(window_id) = window_id_for_toplevel(self, &toplevel) else {
            return;
        };
        if let Some(window) = self.get_window(window_id) {
            if let Ok(mut w) = window.write() {
                w.modal = is_modal;
            }
        }
        tracing::debug!("Dialog modal={} for window {}", is_modal, window_id);
    }
}

impl XdgSystemBellHandler for CompositorState {
    fn ring(&mut self, surface: Option<WlSurface>) {
        let surface_id = surface.as_ref().map(|s| s.id().protocol_id()).unwrap_or(0);
        let client_id = surface
            .as_ref()
            .and_then(|s| s.client().map(|c| c.id()));
        tracing::debug!("System bell requested (surface={:?})", surface_id);
        if let Some(client_id) = client_id {
            self.pending_compositor_events.push(CompositorEvent::SystemBell {
                client_id,
                surface_id,
            });
        }
    }
}

impl XdgToplevelIconHandler for CompositorState {}

impl XdgToplevelTagHandler for CompositorState {}
