//! XDG Decoration — Smithay `delegate_xdg_decoration!` owns dispatch.
//!
//! Data types and policy helpers used by [`super::extension_handlers`].

use wayland_protocols::xdg::decoration::zv1::server::{
    zxdg_toplevel_decoration_v1::{self, ZxdgToplevelDecorationV1, Mode},
};
use wayland_server::Resource;

use crate::core::state::{CompositorState, DecorationPolicy};
use crate::core::window::DecorationMode;
use smithay::wayland::shell::xdg::ToplevelSurface;
use std::collections::HashMap;

pub fn is_weston_family_app(state: &CompositorState, window_id: u32) -> bool {
    state
        .get_window(window_id)
        .and_then(|w| w.read().ok().map(|w| w.app_id.clone()))
        .map(|app_id| {
            app_id == "weston"
                || app_id.starts_with("weston-")
                || app_id.contains("weston")
        })
        .unwrap_or(false)
}

pub fn preferred_xdg_decoration_mode(
    state: &CompositorState,
    window_id: u32,
) -> Mode {
    let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
        .then_some(false)
        .unwrap_or_else(|| is_weston_family_app(state, window_id));
    if weston_family {
        Mode::ClientSide
    } else {
        match state.decoration_policy {
            DecorationPolicy::PreferClient => Mode::ClientSide,
            DecorationPolicy::PreferServer => Mode::ServerSide,
            DecorationPolicy::ForceServer => Mode::ServerSide,
        }
    }
}

pub fn decoration_mode_from_xdg(mode: Mode) -> DecorationMode {
    match mode {
        Mode::ServerSide => DecorationMode::ServerSide,
        Mode::ClientSide => DecorationMode::ClientSide,
        _ => DecorationMode::ClientSide,
    }
}

pub fn window_id_for_toplevel(state: &CompositorState, toplevel: &ToplevelSurface) -> Option<u32> {
    state
        .xdg_toplevel_key_for_surface(toplevel)
        .and_then(|key| state.xdg.toplevels.get(&key).map(|tl| tl.window_id))
}

/// Data stored with each toplevel decoration (FFI + KDE fallback bookkeeping).
#[derive(Debug, Clone)]
pub struct ToplevelDecorationData {
    pub window_id: u32,
    pub mode: Mode,
    pub resource: Option<ZxdgToplevelDecorationV1>,
    pub kde_resource: Option<
        crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration::OrgKdeKwinServerDecoration,
    >,
}

impl ToplevelDecorationData {
    pub fn new(window_id: u32, resource: Option<ZxdgToplevelDecorationV1>) -> Self {
        Self {
            window_id,
            mode: Mode::ClientSide,
            resource,
            kde_resource: None,
        }
    }

    pub fn new_kde(
        window_id: u32,
        resource: crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration::OrgKdeKwinServerDecoration,
    ) -> Self {
        Self {
            window_id,
            mode: Mode::ClientSide,
            resource: None,
            kde_resource: Some(resource),
        }
    }
}

unsafe impl Send for ToplevelDecorationData {}
unsafe impl Sync for ToplevelDecorationData {}

#[derive(Debug, Default)]
pub struct DecorationState {
    pub decorations: HashMap<(wayland_server::backend::ClientId, u32), ToplevelDecorationData>,
}

impl CompositorState {
    pub(crate) fn track_xdg_decoration(
        &mut self,
        client_id: wayland_server::backend::ClientId,
        decoration: &ZxdgToplevelDecorationV1,
        window_id: u32,
    ) {
        let data = ToplevelDecorationData::new(window_id, Some(decoration.clone()));
        self.xdg
            .decoration
            .decorations
            .insert((client_id, decoration.id().protocol_id()), data);
    }

    pub(crate) fn apply_decoration_mode_for_window(
        &mut self,
        window_id: u32,
        preferred: Mode,
    ) {
        if let Some(window) = self.get_window(window_id) {
            let mut window = window.write().unwrap();
            window.decoration_mode = decoration_mode_from_xdg(preferred);
        }
        self.reconfigure_window_decorations(window_id);
    }
}
