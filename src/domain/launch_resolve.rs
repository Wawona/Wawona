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
pub fn nested_cursor_policy(is_nested_compositor: bool, show_virtual_cursor_pref: bool) -> NestedCursorPolicy {
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
    serde_json::to_string(&p).unwrap_or_else(|_| {
        r#"{"hide_host_cursor":false,"show_virtual_pointer":false}"#.into()
    })
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
}
