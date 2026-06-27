
//! Legacy compositor dispatch — core wl_compositor/wl_surface/wl_region owned by Smithay `delegate_compositor!`.
//!
//! wl_buffer destroy bookkeeping remains here until fully migrated to Smithay buffer handlers.

use wayland_server::{
    protocol::wl_buffer,
    Dispatch, DisplayHandle, Resource,
};

use crate::core::state::CompositorState;

impl Dispatch<wl_buffer::WlBuffer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_buffer::WlBuffer,
        request: wl_buffer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_buffer::Request::Destroy => {
                let id = resource.id().protocol_id();
                let client_id = _client.id();
                state.remove_buffer(client_id, id);
                tracing::debug!("wl_buffer.destroy: removed buffer {}", id);
            }
            _ => {}
        }
    }
}
