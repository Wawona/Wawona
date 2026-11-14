//! Launch policy: compositor backend + nested-cursor host flags.
//! Swift runners apply env / argv; they do not invent these rules.

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CompositorBackendMode {
    Auto,
    Wayland,
    Drm,
}

impl CompositorBackendMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::Wayland => "wayland",
            Self::Drm => "drm",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "auto" => Some(Self::Auto),
            "wayland" | "nested" => Some(Self::Wayland),
            "drm" | "tty" => Some(Self::Drm),
            _ => None,
        }
    }
}

/// Resolve Display Backend for Aqua (WindowServer up).
/// Classic own-display always uses DRM for the session compositor.
pub fn resolve_backend(
    pref: &str,
    classic_own_display: bool,
    cli_override: Option<&str>,
) -> CompositorBackendMode {
    if classic_own_display {
        return CompositorBackendMode::Drm;
    }
    if let Some(cli) = cli_override.and_then(CompositorBackendMode::parse) {
        return match cli {
            CompositorBackendMode::Auto => CompositorBackendMode::Wayland,
            other => other,
        };
    }
    match CompositorBackendMode::parse(pref).unwrap_or(CompositorBackendMode::Auto) {
        CompositorBackendMode::Auto => CompositorBackendMode::Wayland,
        other => other,
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct NestedCursorPolicy {
    /// Nested weston/niri draw their own pointer. Host overlay must hide.
    pub hide_host_cursor: bool,
    pub show_virtual_pointer: bool,
}

/// Nested compositor clients always hide the host cursor, even when
/// Show Virtual Cursor is on.
pub fn nested_cursor_policy(
    is_nested_compositor: bool,
    show_virtual_cursor_pref: bool,
) -> NestedCursorPolicy {
    if is_nested_compositor {
        NestedCursorPolicy {
            hide_host_cursor: true,
            show_virtual_pointer: false,
        }
    } else {
        NestedCursorPolicy {
            hide_host_cursor: false,
            show_virtual_pointer: show_virtual_cursor_pref,
        }
    }
}

/// Touch / pointer / grab resolution for Start and Focus.
/// Settings prefs are overrides; hosts must not invent a second table.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TouchMode {
    MultiTouch,
    SingleTouch,
    Pointer,
}

impl TouchMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::MultiTouch => "Multi-Touch",
            Self::SingleTouch => "Single Touch",
            Self::Pointer => "Touchpad",
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct SessionInputPolicy {
    pub touch_mode: TouchMode,
    pub hide_host_cursor: bool,
    pub show_virtual_pointer: bool,
    /// Relative pointer / cursor grab while focused on the surface.
    pub grab_cursor: bool,
}

/// Surface class the host reports (CarPlay / AirPlay / phone-as-remote / normal).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PresentSurfaceClass {
    /// Phone / pad / vision primary surface.
    Primary,
    /// CarPlay or other single-touch-limited external.
    LimitedTouch,
    /// AirPlay / phone-as-remote: pointer + soft keys, no fake Multi-Touch.
    PointerRemote,
}

/// Resolve touch, virtual cursor, and grab for a focused machine session.
///
/// Rules (plan P1):
/// - Nested compositor → Multi-Touch, hide host cursor, grab on.
/// - Normal client → host Touch Input Type override when set; else Multi-Touch.
/// - Virtual cursor off for nested compositor; else Show Virtual Cursor pref.
/// - LimitedTouch (CarPlay / external) → Single Touch.
/// - PointerRemote → Touchpad path, no Multi-Touch.
pub fn resolve_session_input(
    is_nested_compositor: bool,
    show_virtual_cursor_pref: bool,
    touch_input_override: Option<&str>,
    surface: PresentSurfaceClass,
) -> SessionInputPolicy {
    let cursor = nested_cursor_policy(is_nested_compositor, show_virtual_cursor_pref);
    let touch_mode = match surface {
        PresentSurfaceClass::PointerRemote => TouchMode::Pointer,
        PresentSurfaceClass::LimitedTouch => TouchMode::SingleTouch,
        PresentSurfaceClass::Primary => {
            if is_nested_compositor {
                TouchMode::MultiTouch
            } else if let Some(raw) = touch_input_override {
                parse_touch_override(raw).unwrap_or(TouchMode::MultiTouch)
            } else {
                TouchMode::MultiTouch
            }
        }
    };
    SessionInputPolicy {
        touch_mode,
        hide_host_cursor: cursor.hide_host_cursor,
        show_virtual_pointer: cursor.show_virtual_pointer,
        grab_cursor: is_nested_compositor
            || matches!(surface, PresentSurfaceClass::PointerRemote),
    }
}

fn parse_touch_override(raw: &str) -> Option<TouchMode> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "multi-touch" | "multitouch" | "multi" | "direct" => Some(TouchMode::MultiTouch),
        "single touch" | "single-touch" | "single" => Some(TouchMode::SingleTouch),
        "touchpad" | "pointer" | "trackpad" => Some(TouchMode::Pointer),
        _ => None,
    }
}

pub fn session_input_json(
    is_nested_compositor: bool,
    show_virtual_cursor_pref: bool,
    touch_input_override: Option<&str>,
    surface: PresentSurfaceClass,
) -> String {
    let p = resolve_session_input(
        is_nested_compositor,
        show_virtual_cursor_pref,
        touch_input_override,
        surface,
    );
    serde_json::to_string(&p).unwrap_or_else(|_| {
        r#"{"touch_mode":"multi_touch","hide_host_cursor":false,"show_virtual_pointer":false,"grab_cursor":false}"#
            .into()
    })
}

pub fn resolve_backend_json(
    pref: &str,
    classic_own_display: bool,
    cli_override: Option<&str>,
) -> String {
    let mode = resolve_backend(pref, classic_own_display, cli_override);
    format!(r#"{{"backend":"{}"}}"#, mode.as_str())
}

pub fn nested_cursor_json(is_nested_compositor: bool, show_virtual_cursor_pref: bool) -> String {
    let p = nested_cursor_policy(is_nested_compositor, show_virtual_cursor_pref);
    serde_json::to_string(&p)
        .unwrap_or_else(|_| r#"{"hide_host_cursor":false,"show_virtual_pointer":false}"#.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classic_forces_drm() {
        assert_eq!(
            resolve_backend("wayland", true, Some("auto")),
            CompositorBackendMode::Drm
        );
    }

    #[test]
    fn auto_is_wayland_on_aqua() {
        assert_eq!(
            resolve_backend("auto", false, None),
            CompositorBackendMode::Wayland
        );
    }

    #[test]
    fn nested_hides_host() {
        let p = nested_cursor_policy(true, true);
        assert!(p.hide_host_cursor);
        assert!(!p.show_virtual_pointer);
    }

    #[test]
    fn nested_session_forces_multitouch_and_grab() {
        let p = resolve_session_input(true, true, Some("Touchpad"), PresentSurfaceClass::Primary);
        assert_eq!(p.touch_mode, TouchMode::MultiTouch);
        assert!(p.hide_host_cursor);
        assert!(!p.show_virtual_pointer);
        assert!(p.grab_cursor);
    }

    #[test]
    fn normal_client_honours_touch_override() {
        let p = resolve_session_input(
            false,
            true,
            Some("Single Touch"),
            PresentSurfaceClass::Primary,
        );
        assert_eq!(p.touch_mode, TouchMode::SingleTouch);
        assert!(p.show_virtual_pointer);
        assert!(!p.grab_cursor);
    }

    #[test]
    fn carplay_is_single_touch() {
        let p = resolve_session_input(false, false, None, PresentSurfaceClass::LimitedTouch);
        assert_eq!(p.touch_mode, TouchMode::SingleTouch);
    }

    #[test]
    fn airplay_remote_is_pointer() {
        let p = resolve_session_input(false, true, Some("Multi-Touch"), PresentSurfaceClass::PointerRemote);
        assert_eq!(p.touch_mode, TouchMode::Pointer);
        assert!(p.grab_cursor);
    }
}
