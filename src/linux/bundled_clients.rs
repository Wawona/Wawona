//! Canonical bundled Wayland client catalog for Linux.
//!
//! Mirror of `kBundledClients` in
//! `src/platform/macos/ui/Machines/WWNMachinesViewModel.swift` and
//! `android/app/.../BundledClients.kt`. Keep the ids, display names, and
//! descriptions in sync across all platforms; the Linux CI gate
//! `verify-linux-bundled-clients.py` enforces this parity.

/// A selectable bundled client (id + presentation metadata). `icon_name` is a
/// freedesktop/Adwaita symbolic icon used by the GTK picker.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BundledClient {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub icon_name: &'static str,
}

/// The 19 canonical bundled clients, in the same order as the Apple/Android
/// catalogs.
pub const BUNDLED_CLIENTS: &[BundledClient] = &[
    BundledClient {
        id: "weston-simple-shm",
        name: "Weston Simple SHM",
        description: "Minimal shared-memory Wayland client",
        icon_name: "view-grid-symbolic",
    },
    BundledClient {
        id: "weston",
        name: "Weston",
        description: "Wayland reference compositor (nested compositor)",
        icon_name: "view-app-grid-symbolic",
    },
    BundledClient {
        id: "weston-terminal",
        name: "Weston Terminal",
        description: "Terminal emulator — uses host cursor",
        icon_name: "utilities-terminal-symbolic",
    },
    BundledClient {
        id: "foot",
        name: "Foot Terminal",
        description: "Lightweight Wayland terminal emulator",
        icon_name: "text-editor-symbolic",
    },
    BundledClient {
        id: "weston-flower",
        name: "Weston Flower",
        description: "Animated cairo demo (toytoolkit)",
        icon_name: "preferences-desktop-wallpaper-symbolic",
    },
    BundledClient {
        id: "kmscube",
        name: "KMS Cube",
        description: "Spinning GL cube via iland + ANGLE",
        icon_name: "view-paged-symbolic",
    },
    BundledClient {
        id: "weston-simple-egl",
        name: "Weston Simple EGL",
        description: "Wayland EGL demo client",
        icon_name: "weather-overcast-symbolic",
    },
    BundledClient {
        id: "weston-smoke",
        name: "Weston Smoke",
        description: "Smoke particle cairo demo",
        icon_name: "weather-fog-symbolic",
    },
    BundledClient {
        id: "weston-clickdot",
        name: "Weston Clickdot",
        description: "Pointer click visualization demo",
        icon_name: "input-touchpad-symbolic",
    },
    BundledClient {
        id: "weston-eventdemo",
        name: "Weston Event Demo",
        description: "Input event logging demo",
        icon_name: "view-list-symbolic",
    },
    BundledClient {
        id: "weston-resizor",
        name: "Weston Resizor",
        description: "Interactive resize demo",
        icon_name: "view-fullscreen-symbolic",
    },
    BundledClient {
        id: "weston-cliptest",
        name: "Weston Cliptest",
        description: "Clipping region demo",
        icon_name: "edit-cut-symbolic",
    },
    BundledClient {
        id: "weston-transformed",
        name: "Weston Transformed",
        description: "Buffer transform demo",
        icon_name: "object-rotate-right-symbolic",
    },
    BundledClient {
        id: "weston-stacking",
        name: "Weston Stacking",
        description: "Subsurface stacking demo",
        icon_name: "view-paged-symbolic",
    },
    BundledClient {
        id: "weston-dnd",
        name: "Weston DnD",
        description: "Drag-and-drop demo",
        icon_name: "edit-copy-symbolic",
    },
    BundledClient {
        id: "weston-image",
        name: "Weston Image",
        description: "PNG image loader demo",
        icon_name: "image-x-generic-symbolic",
    },
    BundledClient {
        id: "weston-scaler",
        name: "Weston Scaler",
        description: "Viewport scaler demo",
        icon_name: "zoom-in-symbolic",
    },
    BundledClient {
        id: "weston-editor",
        name: "Weston Editor",
        description: "Text editor demo",
        icon_name: "document-edit-symbolic",
    },
    BundledClient {
        id: "weston-constraints",
        name: "Weston Constraints",
        description: "Pointer constraints demo",
        icon_name: "view-continuous-symbolic",
    },
];

/// Look up a bundled client by id.
pub fn bundled_client(id: &str) -> Option<&'static BundledClient> {
    BUNDLED_CLIENTS.iter().find(|c| c.id == id)
}

/// Display label for a client id, falling back to the raw id when unknown.
pub fn label_for(id: &str) -> String {
    bundled_client(id).map(|c| c.name.to_string()).unwrap_or_else(|| id.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_nineteen_unique_clients() {
        assert_eq!(BUNDLED_CLIENTS.len(), 19);
        let mut ids: Vec<&str> = BUNDLED_CLIENTS.iter().map(|c| c.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), 19, "bundled client ids must be unique");
    }

    #[test]
    fn lookup_and_label_work() {
        assert_eq!(bundled_client("foot").unwrap().name, "Foot Terminal");
        assert_eq!(label_for("kmscube"), "KMS Cube");
        assert_eq!(label_for("does-not-exist"), "does-not-exist");
    }
}
