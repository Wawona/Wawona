//! Bundled Wayland / wasm client catalog. Shared by Apple, Android, Linux.
//! Swift `ClientLauncher` and Darwin `--list-clients` read this list.

use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ClientPreset {
    pub id: &'static str,
    pub display_name: &'static str,
    pub executable: &'static str,
    pub requires_gpu: bool,
    pub requires_wasm: bool,
}

/// Full product catalog. Never include modeb-tty / igetty.
pub const ALL_PRESETS: &[ClientPreset] = &[
    ClientPreset {
        id: "weston-terminal",
        display_name: "Weston Terminal",
        executable: "weston-terminal",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "foot",
        display_name: "Foot Terminal",
        executable: "foot",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-simple-shm",
        display_name: "Weston Simple SHM",
        executable: "weston-simple-shm",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "wawona-wasm",
        display_name: "Hello WASI GUI / Runtime (.wasm)",
        executable: "wasm",
        requires_gpu: false,
        requires_wasm: true,
    },
    ClientPreset {
        id: "weston",
        display_name: "Weston",
        executable: "weston",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "niri",
        display_name: "Niri",
        executable: "niri",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-flower",
        display_name: "Weston Flower",
        executable: "weston-flower",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "kmscube",
        display_name: "KMS Cube",
        executable: "kmscube",
        requires_gpu: true,
        requires_wasm: false,
    },
    ClientPreset {
        id: "gbm-es2-demo",
        display_name: "GBM ES2 Demo",
        executable: "gbm-es2-demo",
        requires_gpu: true,
        requires_wasm: false,
    },
    ClientPreset {
        id: "opengl-cube",
        display_name: "OpenGL Cube",
        executable: "opengl-cube",
        requires_gpu: true,
        requires_wasm: false,
    },
    ClientPreset {
        id: "vkcube",
        display_name: "Vulkan Cube",
        executable: "vkcube",
        requires_gpu: true,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-simple-egl",
        display_name: "Weston Simple EGL",
        executable: "weston-simple-egl",
        requires_gpu: true,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-smoke",
        display_name: "Weston Smoke",
        executable: "weston-smoke",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-clickdot",
        display_name: "Weston Clickdot",
        executable: "weston-clickdot",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-eventdemo",
        display_name: "Weston Event Demo",
        executable: "weston-eventdemo",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-resizor",
        display_name: "Weston Resizor",
        executable: "weston-resizor",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-cliptest",
        display_name: "Weston Cliptest",
        executable: "weston-cliptest",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-transformed",
        display_name: "Weston Transformed",
        executable: "weston-transformed",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-stacking",
        display_name: "Weston Stacking",
        executable: "weston-stacking",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-dnd",
        display_name: "Weston DnD",
        executable: "weston-dnd",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-image",
        display_name: "Weston Image",
        executable: "weston-image",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-scaler",
        display_name: "Weston Scaler",
        executable: "weston-scaler",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-editor",
        display_name: "Weston Editor",
        executable: "weston-editor",
        requires_gpu: false,
        requires_wasm: false,
    },
    ClientPreset {
        id: "weston-constraints",
        display_name: "Weston Constraints",
        executable: "weston-constraints",
        requires_gpu: false,
        requires_wasm: false,
    },
];

pub const GLES_CLIENT_IDS: &[&str] = &[
    "kmscube",
    "gbm-es2-demo",
    "opengl-cube",
    "weston-simple-egl",
];

/// JSON array of `{id,display_name,executable,requires_gpu,requires_wasm}`.
pub fn catalog_json() -> String {
    #[derive(Serialize)]
    struct Row<'a> {
        id: &'a str,
        display_name: &'a str,
        executable: &'a str,
        requires_gpu: bool,
        requires_wasm: bool,
    }
    let rows: Vec<Row> = ALL_PRESETS
        .iter()
        .map(|p| Row {
            id: p.id,
            display_name: p.display_name,
            executable: p.executable,
            requires_gpu: p.requires_gpu,
            requires_wasm: p.requires_wasm,
        })
        .collect();
    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into())
}

pub fn display_name(id: &str) -> Option<&'static str> {
    let trimmed = id.trim();
    ALL_PRESETS
        .iter()
        .find(|p| p.id.eq_ignore_ascii_case(trimmed))
        .map(|p| p.display_name)
}
