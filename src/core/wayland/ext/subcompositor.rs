//! `wl_subsurface` bookkeeping on top of Smithay's subcompositor.
//!
//! Smithay owns the protocol objects and the surface tree (stacking order,
//! sync/desync transactions). It caches `set_position` on the child, so a
//! desynchronized child only moves when the child itself commits. The core
//! spec applies the position when the parent's state is applied, so the
//! position is also recorded in `CompositorState::subsurfaces` and promoted
//! on the parent's commit.

use smithay::reexports::wayland_server::{
    backend::ClientId,
    protocol::wl_subsurface::{self, WlSubsurface},
    Client, DataInit, Dispatch, DisplayHandle,
};
use smithay::wayland::compositor::SubsurfaceUserData;

use crate::core::state::CompositorState;

type SmithayCompositor = smithay::wayland::compositor::CompositorState;

impl Dispatch<WlSubsurface, SubsurfaceUserData> for CompositorState {
    fn request(
        state: &mut Self,
        client: &Client,
        resource: &WlSubsurface,
        request: wl_subsurface::Request,
        data: &SubsurfaceUserData,
        dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        if let wl_subsurface::Request::SetPosition { x, y } = request {
            if let Some(surface_id) = state.internal_surface_id(data.surface()) {
                state.set_subsurface_position(surface_id, x, y);
            }
        }
        <SmithayCompositor as Dispatch<WlSubsurface, SubsurfaceUserData, Self>>::request(
            state, client, resource, request, data, dhandle, data_init,
        );
    }

    fn destroyed(
        state: &mut Self,
        client: ClientId,
        resource: &WlSubsurface,
        data: &SubsurfaceUserData,
    ) {
        if let Some(surface_id) = state.internal_surface_id(data.surface()) {
            state.remove_subsurface(surface_id);
        }
        <SmithayCompositor as Dispatch<WlSubsurface, SubsurfaceUserData, Self>>::destroyed(
            state, client, resource, data,
        );
    }
}
