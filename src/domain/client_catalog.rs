//! Product keep-set client catalog. Shared by Apple, Android, Linux.
//! Swift `ClientLauncher` and Darwin `--list-clients` read this list.
//! Optional Wayland clients (weston/niri/foot/cubes) install later via
//! `wpm` / apt and appear under InstalledOptionalSoftware, not here.

use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct ClientPreset {
    pub id: &'static str,
    pub display_name: &'static str,
    pub executable: &'static str,
    pub requires_gpu: bool,
    pub requires_wasm: bool,
}

/// Product keep-set only. Never include modeb-tty / igetty / weston / niri.
pub const ALL_PRESETS: &[ClientPreset] = &[
    ClientPreset {
        id: "wawona-shell",
        display_name: "Native Shell",
        executable: "wawona-shell",
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
];

/// GLES demo ids (optional-software). Empty keep-set; gate still named for
/// PlatformCapabilities mirrors that classify installed clients.
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
