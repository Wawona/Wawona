//! XDG Foreign — dispatch owned by Smithay `delegate_xdg_foreign!`.
//!
//! Legacy Wawona-side export/import tracking (unused after Smithay cutover).

use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct ExportedToplevelData {
    pub toplevel_id: u32,
    pub handle: String,
}

#[derive(Debug, Clone)]
pub struct ImportedToplevelData {
    pub handle: String,
}

#[derive(Debug, Default)]
pub struct WawonaForeignTracking {
    pub exported_toplevels: HashMap<u32, ExportedToplevelData>,
    pub imported_toplevels: HashMap<u32, ImportedToplevelData>,
}
