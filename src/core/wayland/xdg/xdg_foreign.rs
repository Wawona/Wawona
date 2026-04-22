//! XDG Foreign protocol implementation.
//!
//! This protocol allows clients to embed windows from other clients,
//! enabling cross-client window embedding scenarios.


use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::foreign::zv2::server::{
    zxdg_exporter_v2::{self, ZxdgExporterV2},
    zxdg_exported_v2::{self, ZxdgExportedV2},
    zxdg_importer_v2::{self, ZxdgImporterV2},
    zxdg_imported_v2::{self, ZxdgImportedV2},
};

use crate::core::state::CompositorState;
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
pub struct XdgForeignState {
    pub exported_toplevels: HashMap<u32, ExportedToplevelData>,
    pub imported_toplevels: HashMap<u32, ImportedToplevelData>,
}


// ============================================================================
// zxdg_exporter_v2
// ============================================================================

impl GlobalDispatch<ZxdgExporterV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZxdgExporterV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zxdg_exporter_v2");
    }
}

impl Dispatch<ZxdgExporterV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZxdgExporterV2,
        request: zxdg_exporter_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_exporter_v2::Request::ExportToplevel { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let handle = format!("wawona-export:{:x}-{}", surface_id, 
                    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos());
                
                let exported_data = ExportedToplevelData {
                    toplevel_id: surface_id,
                    handle: handle.clone(),
                };
                
                let exported = data_init.init(id, ());
                exported.handle(handle.clone());
                
                state.xdg.foreign.exported_toplevels.insert(exported.id().protocol_id(), exported_data);
                
                tracing::debug!("Exported surface {} with handle {}", surface_id, handle);
            }
            zxdg_exporter_v2::Request::Destroy => {
                tracing::debug!("zxdg_exporter_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zxdg_importer_v2
// ============================================================================

impl GlobalDispatch<ZxdgImporterV2, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZxdgImporterV2>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zxdg_importer_v2");
    }
}

impl Dispatch<ZxdgImporterV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZxdgImporterV2,
        request: zxdg_importer_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_importer_v2::Request::ImportToplevel { id, handle } => {
                let imported_data = ImportedToplevelData {
                    handle: handle.clone(),
                };
                
                let imported = data_init.init(id, ());

                state.xdg.foreign.imported_toplevels.insert(imported.id().protocol_id(), imported_data);

                
                tracing::debug!("Imported toplevel with handle {}", handle);
            }
            zxdg_importer_v2::Request::Destroy => {
                tracing::debug!("zxdg_importer_v2 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zxdg_exported_v2
// ============================================================================

impl Dispatch<ZxdgExportedV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZxdgExportedV2,
        request: zxdg_exported_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_exported_v2::Request::Destroy => {
                state.xdg.foreign.exported_toplevels.remove(&resource.id().protocol_id());
                tracing::debug!("zxdg_exported_v2 destroyed");
            }

            _ => {}
        }
    }
}

// ============================================================================
// zxdg_imported_v2
// ============================================================================

impl Dispatch<ZxdgImportedV2, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZxdgImportedV2,
        request: zxdg_imported_v2::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_imported_v2::Request::SetParentOf { surface } => {
                let child_surface_id = surface.id().protocol_id();
                let imported_id = resource.id().protocol_id();
                
                // Look up the imported handle
                if let Some(imported_data) = state.xdg.foreign.imported_toplevels.get(&imported_id) {
                    let handle = imported_data.handle.clone();
                    
                    // Find the exported toplevel matching this handle
                    let parent_surface_id = state.xdg.foreign.exported_toplevels.values()
                        .find(|e| e.handle == handle)
                        .map(|e| e.toplevel_id);
                    
                    if let Some(parent_sid) = parent_surface_id {
                        // Find the window IDs for both surfaces
                        let parent_wid = state.surface_to_window.get(&parent_sid).copied();
                        let child_wid = state.surface_to_window.get(&child_surface_id).copied();
                        
                        if let (Some(pwid), Some(cwid)) = (parent_wid, child_wid) {
                            // Set parent on the xdg_toplevel data
                            for tl_data in state.xdg.toplevels.values_mut() {
                                if tl_data.window_id == cwid {
                                    tl_data.parent = Some(pwid);
                                    tracing::info!(
                                        "SetParentOf: window {} is now child of window {} (handle={})",
                                        cwid, pwid, handle
                                    );
                                    break;
                                }
                            }
                        } else {
                            tracing::warn!("SetParentOf: could not find windows for surfaces (parent={}, child={})", parent_sid, child_surface_id);
                        }
                    } else {
                        tracing::warn!("SetParentOf: no exported toplevel with handle {}", handle);
                        // Per spec, send destroyed event if handle is invalid
                        resource.destroyed();
                    }
                }
            }
            zxdg_imported_v2::Request::Destroy => {
                state.xdg.foreign.imported_toplevels.remove(&resource.id().protocol_id());
                tracing::debug!("zxdg_imported_v2 destroyed");
            }

            _ => {}
        }
    }
}

/// Register zxdg_exporter_v2 global
pub fn register_xdg_exporter(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZxdgExporterV2, ()>(1, ())
}
