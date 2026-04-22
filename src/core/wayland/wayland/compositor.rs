
use wayland_server::{
    protocol::{wl_compositor, wl_surface, wl_region},
    Dispatch, Resource, DisplayHandle, GlobalDispatch, WEnum,
};

use crate::core::state::CompositorState;
use crate::core::surface::buffer::{Buffer, BufferType, ShmBufferData, wl_shm_format_to_legacy_u32};
use crate::core::surface::Surface;
use smithay::wayland::shm::with_buffer_contents;

pub struct CompositorGlobal;

#[cfg(any())]
impl GlobalDispatch<wl_compositor::WlCompositor, ()> for CompositorState {
    #[allow(unreachable_code)]
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wl_compositor::WlCompositor>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "DEBUG: Compositor Bind Called");
    }
}

#[cfg(any())]
impl Dispatch<wl_compositor::WlCompositor, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_compositor::WlCompositor,
        request: wl_compositor::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_compositor::Request::CreateSurface { id } => {
                let internal_id = state.next_surface_id();
                let surface = data_init.init(id, internal_id);
                let protocol_id = surface.id().protocol_id();
                
                // Scoped by client ID to prevent collisions between clients
                let client_id = _client.id();
                state.protocol_to_internal_surface.insert((client_id.clone(), protocol_id), internal_id);
                
                state.add_surface(Surface::new(internal_id, Some(client_id), Some(surface.clone())));
            }
            wl_compositor::Request::CreateRegion { id } => {
                let region: wl_region::WlRegion = data_init.init(id, ());
                let region_id = region.id().protocol_id();
                let client_id = _client.id();
                state.regions.insert((client_id, region_id), Vec::new());
            }
            _ => {}
        }
    }
}

#[cfg(any())]
impl Dispatch<wl_surface::WlSurface, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_surface::WlSurface,
        request: wl_surface::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_surface::Request::Commit => {
                let id = *data;
                state.handle_surface_commit(id);
            }
            wl_surface::Request::Attach { buffer, x, y } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(buffer_res) = buffer {
                        let buffer_id = buffer_res.id().protocol_id();
                        let client_id = _client.id();
                        if let Some(b) = state.get_buffer(client_id, buffer_id) {
                            let mut b = b.write().unwrap();
                            // Reset released flag - client is reusing this buffer
                            b.released = false;
                            // Keep the resource handle fresh. Some clients destroy and recreate
                            // wl_buffer objects quickly during resize; stale handles later show up
                            // as "resource DEAD" at release time.
                            b.resource = Some(buffer_res.clone());
                            
                            let client_id = resource.client();
                            let client_outputs: Vec<_> = state.output_resources.values()
                                .filter(|o| o.client() == client_id)
                                .cloned()
                                .collect();

                            if !client_outputs.is_empty() {
                                let count = client_outputs.len();
                                for output in client_outputs {
                                    resource.enter(&output);
                                }
                                crate::wtrace!(crate::util::logging::COMPOSITOR, "Sent wl_surface.enter for surface {} to {} bound outputs for client {:?}", id, count, client_id.as_ref().map(|c| c.id()));
                            }

                            surface.pending.buffer = b.buffer_type.clone();
                            surface.pending.buffer_id = Some(buffer_id);
                            tracing::debug!("Surface {} attached buffer {} at ({}, {})", id, buffer_id, x, y);
                        } else if let Ok((width, height, stride, offset, fmt_u32)) =
                            with_buffer_contents(&buffer_res, |_, _, data| {
                                (
                                    data.width,
                                    data.height,
                                    data.stride,
                                    data.offset,
                                    wl_shm_format_to_legacy_u32(data.format),
                                )
                            })
                        {
                            // Smithay-managed wl_shm buffer (e.g. Weston): register for FFI + rendering.
                            let shm = ShmBufferData {
                                width,
                                height,
                                stride,
                                format: fmt_u32,
                                offset,
                                pool_id: 0,
                            };
                            state.add_buffer(
                                _client.id(),
                                Buffer::new(
                                    buffer_id,
                                    BufferType::Shm(shm.clone()),
                                    Some(buffer_res.clone()),
                                ),
                            );

                            let client_id_for_outputs = resource.client();
                            let client_outputs: Vec<_> = state
                                .output_resources
                                .values()
                                .filter(|o| o.client() == client_id_for_outputs)
                                .cloned()
                                .collect();
                            if !client_outputs.is_empty() {
                                let count = client_outputs.len();
                                for output in client_outputs {
                                    resource.enter(&output);
                                }
                                crate::wtrace!(
                                    crate::util::logging::COMPOSITOR,
                                    "Sent wl_surface.enter for surface {} to {} bound outputs for client {:?}",
                                    id,
                                    count,
                                    client_id_for_outputs
                                        .as_ref()
                                        .map(|c| c.id())
                                );
                            }

                            surface.pending.buffer = BufferType::Shm(shm);
                            surface.pending.buffer_id = Some(buffer_id);
                            tracing::debug!(
                                "Surface {} attached Smithay SHM buffer {} at ({}, {})",
                                id,
                                buffer_id,
                                x,
                                y
                            );
                        } else {
                            // If buffer not found (e.g. from another protocol), use a generic placeholder
                            surface.pending.buffer = crate::core::surface::BufferType::None;
                            surface.pending.buffer_id = Some(buffer_id); // Still track the ID
                        }
                    } else {

                        surface.pending.buffer = crate::core::surface::BufferType::None;
                        surface.pending.buffer_id = None;
                        tracing::debug!("Surface {} detached buffer", id);
                    }
                }
            }
            wl_surface::Request::Damage { x, y, width, height } => {
                let id = *data;
                crate::wtrace!(crate::util::logging::COMPOSITOR, "Surface {} damage (local): x={}, y={}, width={}, height={}", id, x, y, width, height);
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.damage.push(crate::core::surface::damage::DamageRegion {
                        x, y, width, height
                    });
                }
            }
            wl_surface::Request::DamageBuffer { x, y, width, height } => {
                let id = *data;
                crate::wtrace!(crate::util::logging::COMPOSITOR, "Surface {} damage (buffer): x={}, y={}, width={}, height={}", id, x, y, width, height);
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.buffer_damage.push(crate::core::surface::damage::DamageRegion {
                        x, y, width, height
                    });
                }
            }
            wl_surface::Request::Frame { callback } => {
                let surface_id = *data;
                let cb: wayland_server::protocol::wl_callback::WlCallback = data_init.init(callback, ());
                
                // Queue the callback to be sent after the next frame is rendered
                state.queue_frame_callback(surface_id, cb);
                tracing::debug!("wl_surface.frame: queued callback for surface {}", surface_id);
            }
            wl_surface::Request::SetInputRegion { region } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(region_res) = region {
                        let region_id = region_res.id().protocol_id();
                        let client_id = _client.id();
                        if let Some(rects) = state.regions.get(&(client_id, region_id)) {
                            surface.pending.input_region = Some(rects.clone());
                        }
                    } else {
                        surface.pending.input_region = None; // Infinite
                    }
                }
            }
            wl_surface::Request::SetOpaqueRegion { region } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(region_res) = region {
                        let region_id = region_res.id().protocol_id();
                        let client_id = _client.id();
                        if let Some(rects) = state.regions.get(&(client_id, region_id)) {
                            surface.pending.opaque_region = Some(rects.clone());
                        }
                    } else {
                        surface.pending.opaque_region = None; // Empty (transparent)
                    }
                }
            }
            wl_surface::Request::SetBufferTransform { transform } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    match transform {
                        wayland_server::WEnum::Value(t) => surface.pending.transform = t,
                        _ => {}
                    }
                }
            }
            wl_surface::Request::SetBufferScale { scale } => {
                if scale <= 0 {
                    resource.post_error(
                        wl_surface::Error::InvalidScale,
                        format!("buffer scale must be positive, got {}", scale),
                    );
                    return;
                }
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.scale = scale;
                }
            }
            wl_surface::Request::Offset { x, y } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.offset = (x, y);
                }
            }
            _ => {}
        }
    }
}

#[cfg(any())]
impl Dispatch<wl_region::WlRegion, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_region::WlRegion,
        request: wl_region::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let region_id = resource.id().protocol_id();
        let client_id = _client.id();
        match request {
            wl_region::Request::Add { x, y, width, height } => {
                if let Some(region) = state.regions.get_mut(&(client_id, region_id)) {
                    region.push(crate::core::surface::damage::DamageRegion::new(x, y, width, height));
                }
            }
            wl_region::Request::Subtract { x: sx, y: sy, width: sw, height: sh } => {
                if let Some(region) = state.regions.get_mut(&(client_id, region_id)) {
                    // Subtract rect (sx,sy,sw,sh) from each existing rect in the region.
                    // Each rect that intersects the subtract area is split into up to 4 pieces.
                    let sub = crate::core::surface::damage::DamageRegion::new(sx, sy, sw, sh);
                    let mut new_rects = Vec::new();
                    for rect in region.drain(..) {
                        // Compute intersection
                        let ix1 = rect.x.max(sub.x);
                        let iy1 = rect.y.max(sub.y);
                        let ix2 = (rect.x + rect.width).min(sub.x + sub.width);
                        let iy2 = (rect.y + rect.height).min(sub.y + sub.height);
                        if ix1 >= ix2 || iy1 >= iy2 {
                            // No intersection — keep the rect unchanged
                            new_rects.push(rect);
                            continue;
                        }
                        let rx2 = rect.x + rect.width;
                        let ry2 = rect.y + rect.height;
                        // Top strip
                        if rect.y < iy1 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, rect.y, rect.width, iy1 - rect.y,
                            ));
                        }
                        // Bottom strip
                        if ry2 > iy2 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, iy2, rect.width, ry2 - iy2,
                            ));
                        }
                        // Left strip (between top and bottom)
                        if rect.x < ix1 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, iy1, ix1 - rect.x, iy2 - iy1,
                            ));
                        }
                        // Right strip (between top and bottom)
                        if rx2 > ix2 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                ix2, iy1, rx2 - ix2, iy2 - iy1,
                            ));
                        }
                    }
                    *region = new_rects;
                }
            }
            wl_region::Request::Destroy => {
                state.regions.remove(&(client_id, region_id));
            }
            _ => {}
        }
    }
}

impl Dispatch<wayland_server::protocol::wl_buffer::WlBuffer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wayland_server::protocol::wl_buffer::WlBuffer,
        request: wayland_server::protocol::wl_buffer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wayland_server::protocol::wl_buffer::Request::Destroy => {
                let id = resource.id().protocol_id();
                let client_id = _client.id();
                state.remove_buffer(client_id, id);
                tracing::debug!("wl_buffer.destroy: removed buffer {}", id);
            }
            _ => {}
        }
    }
}

#[cfg(any())]
impl Dispatch<wayland_server::protocol::wl_callback::WlCallback, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wayland_server::protocol::wl_callback::WlCallback,
        _request: wayland_server::protocol::wl_callback::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        // Callbacks don't have requests, they're one-shot events
    }
}
