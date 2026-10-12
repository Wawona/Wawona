//! Canonical bundled Wayland client catalog for Linux.
//!
//! Mirror of `kBundledClients` in
//! `src/platform/macos/ui/Machines/WWNMachinesViewModel.swift` and
//! `android/app/.../BundledClients.kt`. Keep the ids, display names, and
//! descriptions in sync across all platforms; the Linux CI gate
//! `verify-linux-bundled-clients.py` enforces this parity.

/// Picker section for native Wayland software (mirrors Apple
/// `BundledWaylandSoftwareKind`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum SoftwareKind {
    Compositor,
    Terminal,
    Graphics,
    Demo,
    Other,
}

impl SoftwareKind {
    pub fn section_title(self) -> &'static str {
        match self {
            Self::Compositor => "Compositors",
            Self::Terminal => "Terminals",
            Self::Graphics => "Graphics",
            Self::Demo => "Demos",
            Self::Other => "Other",
        }
    }

    pub fn for_client_id(id: &str) -> Self {
        match id {
            "weston" | "niri" => Self::Compositor,
            "weston-terminal" | "foot" | "wayland-terminal" => Self::Terminal,
            "kmscube" | "gbm-es2-demo" | "opengl-cube" | "vkcube" | "weston-simple-egl" => {
                Self::Graphics
            }
            "weston-simple-shm" | "wawona-shell" | "wawona-wasm" | "custom" => Self::Other,
            other if other.starts_with("weston-") => Self::Demo,
            _ => Self::Other,
        }
    }
}

/// A selectable bundled client (id + presentation metadata). `icon_name` is a
/// freedesktop/Adwaita symbolic icon used by the GTK picker.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BundledClient {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub icon_name: &'static str,
}

impl BundledClient {
    pub fn software_kind(self) -> SoftwareKind {
        SoftwareKind::for_client_id(self.id)
    }
}

/// Clients for the Wayland picker, grouped like the Apple editor (Compositors,
/// Terminals, Graphics, Demos, Other). Skips shell/wasm session entries.
pub fn wayland_picker_groups() -> Vec<(SoftwareKind, Vec<&'static BundledClient>)> {
    let kinds = [
        SoftwareKind::Compositor,
        SoftwareKind::Terminal,
        SoftwareKind::Graphics,
        SoftwareKind::Demo,
        SoftwareKind::Other,
    ];
    kinds
        .into_iter()
        .filter_map(|kind| {
            let mut group: Vec<&'static BundledClient> = BUNDLED_CLIENTS
                .iter()
                .filter(|c| c.id != "wawona-shell" && c.id != "wawona-wasm")
                .filter(|c| c.software_kind() == kind)
                .collect();
            if group.is_empty() {
                return None;
            }
            group.sort_by(|a, b| a.name.cmp(b.name));
            Some((kind, group))
        })
        .collect()
}

/// Product keep-set only (same order as Apple/Android catalogs). Nested
/// compositors and demos install later via `wpm` / apt.
pub const BUNDLED_CLIENTS: &[BundledClient] = &[
    BundledClient {
        id: "wawona-shell",
        name: "Native Shell",
        description: "zsh + uutils + fastfetch. Optional Wayland clients via wpm or apt",
        icon_name: "utilities-terminal-symbolic",
    },
    BundledClient {
        id: "wawona-wasm",
        name: "Wawona Runtime (.wasm)",
        description: "Relay WASI Runtime. Pick a .wasm module or wpm package path",
        icon_name: "application-x-executable-symbolic",
    },
];

/// Look up a bundled client by id.
pub fn bundled_client(id: &str) -> Option<&'static BundledClient> {
    BUNDLED_CLIENTS.iter().find(|c| c.id == id)
}

/// Display label for a client id, falling back to the raw id when unknown.
pub fn label_for(id: &str) -> String {
    bundled_client(id)
        .map(|c| c.name.to_string())
        .unwrap_or_else(|| id.to_string())
}

/// Terminals and nested compositors fill the host. Demos stay client-preferred
/// (`configure(0,0)`). Same set as macOS `WWNBundledClientFillsHost`.
pub fn fills_host(command_or_id: &str) -> bool {
    let token = command_or_id
        .split_whitespace()
        .next()
        .unwrap_or(command_or_id);
    let base = std::path::Path::new(token)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(token);
    matches!(
        base,
        "weston-terminal" | "wayland-terminal" | "foot" | "niri" | "weston"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_two_unique_product_clients() {
        assert_eq!(BUNDLED_CLIENTS.len(), 2);
        let mut ids: Vec<&str> = BUNDLED_CLIENTS.iter().map(|c| c.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), 2, "product client ids must be unique");
        assert_eq!(BUNDLED_CLIENTS[0].id, "wawona-shell");
        assert_eq!(BUNDLED_CLIENTS[1].id, "wawona-wasm");
    }

    #[test]
    fn lookup_and_label_work() {
        assert_eq!(bundled_client("wawona-shell").unwrap().name, "Native Shell");
        assert_eq!(label_for("wawona-wasm"), "Wawona Runtime (.wasm)");
        assert_eq!(label_for("does-not-exist"), "does-not-exist");
        // Installed optional debs still fill-host when launched by path/id.
        assert!(fills_host("niri"));
        assert!(fills_host("/usr/bin/weston --backend=wayland"));
        assert!(!fills_host("weston-flower"));
        assert!(!fills_host("weston-simple-egl"));
    }

    #[test]
    fn picker_groups_empty_without_optional_software() {
        let groups = wayland_picker_groups();
        assert!(groups.is_empty(), "product catalog has no Wayland picker rows");
        assert_eq!(
            SoftwareKind::for_client_id("weston-flower"),
            SoftwareKind::Demo
        );
        assert_eq!(
            SoftwareKind::for_client_id("kmscube"),
            SoftwareKind::Graphics
        );
    }
}
