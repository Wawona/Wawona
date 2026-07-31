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
    // The weston toy-toolkit (clients/window.c) doesn't app_id its clients
    // as bare "weston"/"weston-*" — e.g. weston-terminal registers as
    // "org.freedesktop.weston.wayland-terminal" (see clients/terminal.c
    // window_set_appid). Matching only the exact/prefix forms above missed
    // every real weston-family client, silently disabling CSD-crop fallback
    // policy selection. `.contains("weston")` matches both forms; mirrors
    // the equivalent check in ffi/api.rs.
    //
    // Do NOT use this helper for host-lock/kiosk fill: auto-locking all
    // weston-family app_ids stretched fixed-size demos (flower/smoke
    // 200×200) into the output. Host-lock is fullscreen_shell / explicit
    // only — see `state/host_lock.rs`.
    app_id == "weston" || app_id.starts_with("weston-") || app_id.contains("weston")
}

fn app_id_matches_bundled_client(app_id: &str, client_id: &str) -> bool {
    if app_id == client_id || app_id.contains(client_id) {
        return true;
    }
    // org.freedesktop.weston.wayland-simple-shm → weston-simple-shm
    if let Some(suffix) = client_id.strip_prefix("weston-") {
        return app_id.contains(suffix);
    }
    false
}

/// Weston toy/demo clients that initiate `xdg_toplevel.move` from the whole
/// surface (no real titlebar). On macOS the host must start an AppKit window
/// drag from content clicks — not only from SSD chrome or xdg move round-trips.
///
/// Do **not** broaden this to nested compositors (niri/weston) or terminals:
/// `NSWindow.movableByWindowBackground` / whole-surface `performWindowDrag`
/// steals click-drag text selection and compositor pointer gestures.
pub fn prefers_macos_surface_window_drag(app_id: &str) -> bool {
    if app_id.is_empty() {
        return false;
    }
    if is_weston_terminal_app_id(app_id) || app_id == "weston" || app_id == "foot" {
        return false;
    }
    const EXCLUDE: &[&str] = &[
        "weston-dnd",
        "weston-constraints",
        "weston-resizor",
        "weston-eventdemo",
        "weston-clickdot",
    ];
    if EXCLUDE
        .iter()
        .any(|id| app_id_matches_bundled_client(app_id, id))
    {
        return false;
    }
    const INCLUDE: &[&str] = &[
        "weston-simple-shm",
        "weston-flower",
        "weston-smoke",
        "weston-simple-egl",
        "weston-image",
        "weston-transformed",
        "weston-stacking",
        "weston-scaler",
        "weston-cliptest",
        "weston-editor",
    ];
    INCLUDE
        .iter()
        .any(|id| app_id_matches_bundled_client(app_id, id))
}

/// Loose tolerance for “is this commit related to the last configure?” checks
/// (CSD chrome / geometry insets). **Not** used to drive host window sizing —
/// see [`committed_size_authorizes_host_sync`] (#111).
pub const COMMIT_SIZE_TOLERANCE: i32 = 64;

/// Strict tolerance when adopting a commit as the host window’s size.
/// Near-miss accepts (tens of px) during live host resize let nested
/// compositors (niri/weston) yank `window.width` backward and flash the
/// framebuffer between before/after sizes (#111).
pub const HOST_SYNC_SIZE_TOLERANCE: i32 = 1;

/// Whether a client-committed buffer size satisfies the compositor's last
/// configure expectation (loose).
///
/// First-commit trust (see `shell_handler::new_toplevel`, which sends a 0x0
/// initial configure) means a commit with no known expectation is always the
/// client's own preferred size, and is accepted. After that, a commit is
/// accepted when it is within [`COMMIT_SIZE_TOLERANCE`] of the configured
/// size. There is deliberately no per-app allowlist here.
pub fn committed_size_matches_expected(
    committed_w: i32,
    committed_h: i32,
    expected_toplevel: Option<(i32, i32)>,
) -> bool {
    if committed_w <= 0 || committed_h <= 0 {
        return false;
    }
    match expected_toplevel {
        Some((expected_w, expected_h)) if expected_w > 0 && expected_h > 0 => {
            (committed_w - expected_w).abs() <= COMMIT_SIZE_TOLERANCE
                && (committed_h - expected_h).abs() <= COMMIT_SIZE_TOLERANCE
        }
        // No (or zero) configured size: the client is choosing freely.
        _ => true,
    }
}

/// Whether a commit may update the core/host window size.
///
/// When the compositor has advertised a positive toplevel size (host live
/// resize, etc.), only near-exact commits may move `window.width/height`.
/// Loose [`COMMIT_SIZE_TOLERANCE`] matching is intentionally **not** used
/// here — it caused nested niri/weston framebuffer ping-pong (#111).
pub fn committed_size_authorizes_host_sync(
    committed_w: i32,
    committed_h: i32,
    expected_toplevel: Option<(i32, i32)>,
) -> bool {
    if committed_w <= 0 || committed_h <= 0 {
        return false;
    }
    match expected_toplevel {
        Some((expected_w, expected_h)) if expected_w > 0 && expected_h > 0 => {
            (committed_w - expected_w).abs() <= HOST_SYNC_SIZE_TOLERANCE
                && (committed_h - expected_h).abs() <= HOST_SYNC_SIZE_TOLERANCE
        }
        _ => true,
    }
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
    policy: DecorationPolicy,
    decoration_mode: DecorationMode,
) -> bool {
    matches!(decoration_mode, DecorationMode::ClientSide)
        || matches!(policy, DecorationPolicy::ForceServer)
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

/// Resolve the buffer region that should be visible to the user.
///
/// Only the client's own `xdg_surface.set_window_geometry` is trusted; there
/// is no guessed inset for clients that keep painting CSD chrome under Force
/// SSD (the old 5px inset produced content/window misalignment and cursor
/// offset for every client that did not match the guess).
pub fn resolve_window_content_geometry(
    policy: DecorationPolicy,
    _app_id: &str,
    decoration_mode: DecorationMode,
    surface_width: i32,
    surface_height: i32,
    xdg_geometry: Option<(i32, i32, i32, i32)>,
) -> Option<(i32, i32, i32, i32)> {
    if !should_crop_buffer_to_window_geometry(policy, decoration_mode) {
        return None;
    }

    let candidate = xdg_geometry
        .filter(|(_, _, gw, gh)| *gw > 0 && *gh > 0)
        // A geometry covering the whole buffer needs no crop.
        .filter(|(gx, gy, gw, gh)| {
            !geometry_covers_full_buffer(*gx, *gy, *gw, *gh, surface_width, surface_height)
        });

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
pub(crate) fn weston_family_prefers_client_decorations(policy: DecorationPolicy) -> bool {
    !matches!(policy, DecorationPolicy::ForceServer)
}

pub fn preferred_xdg_decoration_mode(
    state: &CompositorState,
    window_id: u32,
) -> Mode {
    // Force SSD per-machine (#120): resolve against this window's client policy.
    let policy = state.window_decoration_policy(window_id);
    let weston_family = matches!(policy, DecorationPolicy::ForceServer)
        .then_some(false)
        .unwrap_or_else(|| is_weston_family_app(state, window_id));
    if weston_family {
        if weston_family_prefers_client_decorations(policy) {
            Mode::ClientSide
        } else {
            Mode::ServerSide
        }
    } else {
        match policy {
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
    fn force_ssd_never_invents_inset_geometry() {
        // Without client-provided window geometry there is no crop, even for
        // clients historically known to paint CSD chrome under Force SSD.
        let config = CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        let geom = resolve_window_content_geometry(
            state.decoration_policy,
            "org.freedesktop.weston.wayland-terminal",
            DecorationMode::ServerSide,
            800,
            600,
            None,
        );
        assert_eq!(geom, None);
    }

    #[test]
    fn force_ssd_skips_nested_weston_compositor_crop() {
        let config = CompositorConfig {
            force_ssd: true,
            ..Default::default()
        };
        let state = CompositorState::new(Some(config));
        let geom = resolve_window_content_geometry(
            state.decoration_policy,
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
            state.decoration_policy,
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
            state.decoration_policy,
            "org.freedesktop.weston.wayland-terminal",
            DecorationMode::ClientSide,
            800,
            600,
            None,
        );
        assert_eq!(geom, None);
    }

    #[test]
    fn macos_surface_drag_policy_for_demo_clients() {
        assert!(prefers_macos_surface_window_drag(
            "org.freedesktop.weston.wayland-simple-shm"
        ));
        assert!(prefers_macos_surface_window_drag("weston-flower"));
        assert!(prefers_macos_surface_window_drag("weston-simple-egl"));
        assert!(!prefers_macos_surface_window_drag(
            "org.freedesktop.weston.wayland-terminal"
        ));
        assert!(!prefers_macos_surface_window_drag("weston-dnd"));
        assert!(!prefers_macos_surface_window_drag("weston-clickdot"));
        assert!(!prefers_macos_surface_window_drag("weston"));
        // Nested compositors / interactive shells must not steal click-drags.
        assert!(!prefers_macos_surface_window_drag("niri"));
        assert!(!prefers_macos_surface_window_drag(""));
    }

    #[test]
    fn committed_size_matching_is_app_id_agnostic() {
        // No configured expectation: the client picks its own size.
        assert!(committed_size_matches_expected(200, 200, None));
        assert!(committed_size_matches_expected(200, 200, Some((0, 0))));
        // Within tolerance of the configured size.
        assert!(committed_size_matches_expected(800, 570, Some((800, 600))));
        // Far from the configured size: not a match, regardless of app id.
        assert!(!committed_size_matches_expected(200, 200, Some((1680, 1050))));
        // Degenerate commits never match.
        assert!(!committed_size_matches_expected(0, 200, None));
    }

    #[test]
    fn host_sync_rejects_near_miss_during_configured_resize() {
        // #111: loose CSD tolerance must not authorize host size rollback.
        assert!(committed_size_matches_expected(870, 600, Some((900, 600))));
        assert!(!committed_size_authorizes_host_sync(870, 600, Some((900, 600))));
        assert!(committed_size_authorizes_host_sync(900, 600, Some((900, 600))));
        assert!(committed_size_authorizes_host_sync(200, 200, None));
    }

    #[test]
    fn no_guessed_inset_without_client_geometry() {
        // Force SSD without client-provided window geometry must not invent
        // a crop (the old 5px inset hack).
        assert!(resolve_window_content_geometry(
            CompositorState::new(Some(CompositorConfig {
                force_ssd: true,
                ..Default::default()
            }))
            .decoration_policy,
            "org.freedesktop.weston.wayland-smoke",
            DecorationMode::ClientSide,
            200,
            200,
            None,
        )
        .is_none());
    }
}
