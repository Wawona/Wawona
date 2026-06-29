//! XDG toplevel decoration (`zxdg_decoration_manager_v1` / `zxdg_toplevel_decoration_v1`).
//!
//! Smithay's `delegate_xdg_decoration!` dispatches client requests; this module
//! holds policy helpers and per-window bookkeeping.
//!
//! ## Negotiation flow
//!
//! 1. Client creates `zxdg_toplevel_decoration_v1` → [`extension_handlers::XdgDecorationHandler::new_decoration`]
//! 2. Compositor picks a mode via [`preferred_xdg_decoration_mode`] and writes it into the
//!    pending xdg toplevel state, then sends `xdg_toplevel.configure`.
//! 3. [`CompositorState::apply_decoration_mode_for_window`] updates the host `Window`
//!    record, emits `DecorationModeChanged` to the platform **once per mode change**, and
//!    re-sends configure so client and host agree on dimensions.
//! 4. Client `set_mode` / `unset_mode` requests go through [`request_mode`] /
//!    [`unset_mode`], which may override the client preference according to
//!    [`DecorationPolicy`] and weston-family rules below.
//!
//! ## Platform mapping (per window, never global)
//!
//! | XDG mode    | macOS                         | Linux GTK              |
//! |-------------|-------------------------------|------------------------|
//! | ServerSide  | titled/resizable NSWindow     | `gtk_window.set_decorated(true)` |
//! | ClientSide  | borderless NSWindow, transparent host chrome | `set_decorated(false)` |
//!
//! Host resize injection always uses **content** size (inside SSD chrome when present).
//! Decoration changes must resize before configure so nested compositors see matching
//! `wl_output.mode` and `xdg_toplevel` dimensions.
//!
//! ## Policy
//!
//! - `ForceServer` → always `Mode::ServerSide` (except weston-family uses dedicated rules).
//! - `PreferServer` / `PreferClient` → honour client `set_mode` for normal apps.
//! - Weston-family (`weston`, `weston-*`) → CSD when policy is not `ForceServer`, because
//!   demo clients paint titlebars into the buffer (waypipe, nested Weston, weston-terminal).

use wayland_protocols::xdg::decoration::zv1::server::{
    zxdg_toplevel_decoration_v1::{self, ZxdgToplevelDecorationV1, Mode},
};
use wayland_server::Resource;

use crate::core::state::{CompositorState, DecorationPolicy};
use crate::core::window::DecorationMode;
use smithay::wayland::shell::xdg::ToplevelSurface;
use std::collections::HashMap;

pub fn is_weston_family_app_id(app_id: &str) -> bool {
    app_id == "weston" || app_id.starts_with("weston-")
}

/// Weston demo clients that paint an in-buffer border even when SSD is negotiated.
pub fn is_weston_terminal_app_id(app_id: &str) -> bool {
    app_id.contains("wayland-terminal") || app_id.contains("weston-terminal")
}

/// Whether the compositor should crop presentation to `set_window_geometry`.
///
/// Under Force SSD we still crop when clients ignore server-side decoration and
/// keep painting CSD into the buffer (common for weston-terminal over waypipe).
pub fn should_crop_buffer_to_window_geometry(
    state: &CompositorState,
    decoration_mode: DecorationMode,
) -> bool {
    matches!(decoration_mode, DecorationMode::ClientSide)
        || matches!(state.decoration_policy, DecorationPolicy::ForceServer)
}

fn geometry_intersects_buffer(
    gx: i32,
    gy: i32,
    gw: i32,
    gh: i32,
    buf_w: i32,
    buf_h: i32,
) -> Option<(i32, i32, i32, i32)> {
    if gw <= 0 || gh <= 0 || buf_w <= 0 || buf_h <= 0 {
        return None;
    }
    let geom_x2 = gx.saturating_add(gw);
    let geom_y2 = gy.saturating_add(gh);
    let inter_x1 = gx.max(0);
    let inter_y1 = gy.max(0);
    let inter_x2 = geom_x2.min(buf_w);
    let inter_y2 = geom_y2.min(buf_h);
    let inter_w = (inter_x2 - inter_x1).max(0);
    let inter_h = (inter_y2 - inter_y1).max(0);
    if inter_w > 0 && inter_h > 0 {
        Some((inter_x1, inter_y1, inter_w, inter_h))
    } else {
        None
    }
}

fn geometry_covers_full_buffer(gx: i32, gy: i32, gw: i32, gh: i32, buf_w: i32, buf_h: i32) -> bool {
    gx <= 0 && gy <= 0 && gw >= buf_w && gh >= buf_h
}

/// Clients that paint in-buffer titlebar chrome even when SSD is negotiated.
fn force_ssd_csd_fallback_app(app_id: &str, decoration_mode: DecorationMode) -> bool {
    if is_weston_terminal_app_id(app_id) {
        return true;
    }
    // Nested compositor ("weston") is full-frame; do not guess a crop.
    if app_id == "weston" {
        return false;
    }
    // Other weston demos that rejected SSD and still draw CSD.
    matches!(decoration_mode, DecorationMode::ClientSide)
        && is_weston_family_app_id(app_id)
}

/// Fallback content rect when Force SSD is active but the client still reports
/// (or paints) full-surface CSD chrome.
pub fn force_ssd_fallback_geometry(
    app_id: &str,
    decoration_mode: DecorationMode,
    buf_w: i32,
    buf_h: i32,
) -> Option<(i32, i32, i32, i32)> {
    if !force_ssd_csd_fallback_app(app_id, decoration_mode) {
        return None;
    }
    const INSET: i32 = 5;
    if buf_w > INSET * 2 && buf_h > INSET * 2 {
        Some((INSET, INSET, buf_w - INSET * 2, buf_h - INSET * 2))
    } else {
        None
    }
}

/// Resolve the buffer region that should be visible to the user.
pub fn resolve_window_content_geometry(
    state: &CompositorState,
    app_id: &str,
    decoration_mode: DecorationMode,
    surface_width: i32,
    surface_height: i32,
    xdg_geometry: Option<(i32, i32, i32, i32)>,
) -> Option<(i32, i32, i32, i32)> {
    if !should_crop_buffer_to_window_geometry(state, decoration_mode) {
        return None;
    }

    let mut candidate = xdg_geometry.filter(|(_, _, gw, gh)| *gw > 0 && *gh > 0);

    if matches!(state.decoration_policy, DecorationPolicy::ForceServer) {
        let covers_full = candidate
            .map(|(gx, gy, gw, gh)| geometry_covers_full_buffer(gx, gy, gw, gh, surface_width, surface_height))
            .unwrap_or(true);
        if covers_full {
            candidate = force_ssd_fallback_geometry(
                app_id,
                decoration_mode,
                surface_width,
                surface_height,
            );
        }
    }

    candidate.and_then(|(gx, gy, gw, gh)| {
        geometry_intersects_buffer(gx, gy, gw, gh, surface_width, surface_height)
    })
}

pub fn is_weston_family_app(state: &CompositorState, window_id: u32) -> bool {
    state
        .get_window(window_id)
        .and_then(|w| w.read().ok().map(|w| w.app_id.clone()))
        .map(|app_id| is_weston_family_app_id(&app_id))
        .unwrap_or(false)
}

/// Weston-family clients (weston-terminal, nested Weston, etc.) draw CSD in their
/// own buffer when the host is not forcing server-side decorations. Same policy
/// for in-process mobile clients and Linux clients forwarded over waypipe.
pub(crate) fn weston_family_prefers_client_decorations(state: &CompositorState) -> bool {
    !matches!(state.decoration_policy, DecorationPolicy::ForceServer)
}

pub fn preferred_xdg_decoration_mode(
    state: &CompositorState,
    window_id: u32,
) -> Mode {
    let weston_family = matches!(state.decoration_policy, DecorationPolicy::ForceServer)
        .then_some(false)
        .unwrap_or_else(|| is_weston_family_app(state, window_id));
    if weston_family {
        if weston_family_prefers_client_decorations(state) {
            Mode::ClientSide
        } else {
            Mode::ServerSide
        }
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
        let new_mode = decoration_mode_from_xdg(preferred);
        let changed = if let Some(window) = self.get_window(window_id) {
            let mut window = window.write().unwrap();
            let changed = window.decoration_mode != new_mode;
            if changed {
                window.decoration_mode = new_mode;
            }
            changed
        } else {
            false
        };

        if changed {
            self.pending_compositor_events.push(
                crate::core::compositor::CompositorEvent::DecorationModeChanged {
                    window_id,
                    mode: new_mode,
                },
            );
        }
        self.reconfigure_window_decorations(window_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::compositor::CompositorConfig;
    use crate::core::window::DecorationMode;

    #[test]
    fn force_ssd_strips_weston_terminal_fallback_csd() {
        let config = CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        let geom = resolve_window_content_geometry(
            &state,
            "org.freedesktop.weston.wayland-terminal",
            DecorationMode::ServerSide,
            800,
            600,
            None,
        );
        assert_eq!(geom, Some((5, 5, 790, 590)));
    }

    #[test]
    fn force_ssd_skips_nested_weston_compositor_crop() {
        let config = CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        let geom = resolve_window_content_geometry(
            &state,
            "weston",
            DecorationMode::ServerSide,
            800,
            600,
            None,
        );
        assert_eq!(geom, None);
    }

    #[test]
    fn force_ssd_uses_client_geometry_when_inset() {
        let config = CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        let geom = resolve_window_content_geometry(
            &state,
            "org.freedesktop.weston.wayland-terminal",
            DecorationMode::ServerSide,
            800,
            600,
            Some((10, 8, 780, 584)),
        );
        assert_eq!(geom, Some((10, 8, 780, 584)));
    }

    #[test]
    fn csd_mode_without_geometry_keeps_full_buffer() {
        let state = CompositorState::new(None);
        let geom = resolve_window_content_geometry(
            &state,
            "org.freedesktop.weston.wayland-terminal",
            DecorationMode::ClientSide,
            800,
            600,
            None,
        );
        assert_eq!(geom, None);
    }
}
