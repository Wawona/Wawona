//! `wl_fixes` — core Wayland registry lifecycle helpers.
//!
//! Smithay 0.7 (`wayland_frontend` only) has no `smithay::wayland::fixes`
//! module yet; this matches the upstream Smithay master handler shape so a
//! future crate bump can swap in `FixesState` without protocol churn.
//!
//! Runtime gate: store-safe-core. Advertised for every `protocol_profile`
//! (no `allow_*` desktop/privileged filter).

use wayland_server::{
    protocol::wl_fixes::{self, WlFixes},
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};

use crate::core::state::CompositorState;

impl GlobalDispatch<WlFixes, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WlFixes>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<WlFixes, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WlFixes,
        request: wl_fixes::Request,
        _data: &(),
        dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wl_fixes::Request::DestroyRegistry { registry } => {
                if let Err(err) = dhandle.backend_handle().destroy_object::<CompositorState>(&registry.id())
                {
                    tracing::error!(?err, "wl_fixes.destroy_registry failed");
                }
            }
            wl_fixes::Request::Destroy => {}
            _ => unreachable!(),
        }
    }
}

/// Advertise `wl_fixes` v1.
pub fn register_wl_fixes(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WlFixes, ()>(1, ())
}
