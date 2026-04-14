//! XDG Surface protocol implementation.
//!
//! This implements the xdg_surface protocol from the xdg-shell extension.
//! It provides the base interface for creating toplevel and popup windows.

use wayland_server::{
    Dispatch, DisplayHandle, Resource,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_surface;

use crate::core::state::{CompositorState, XdgToplevelData, XdgPopupData};
use crate::core::window::Window;

impl Dispatch<xdg_surface::XdgSurface, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &xdg_surface::XdgSurface,
        request: xdg_surface::Request,
        _data: &u32,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let xdg_surface_id = resource.id().protocol_id();
        let client_id = _client.id();
        let data = state.xdg.surfaces.get(&(client_id.clone(), xdg_surface_id)).cloned();
        
        match request {
            xdg_surface::Request::GetToplevel { id } => {
                crate::wlog!(crate::util::logging::COMPOSITOR, "xdg_surface.get_toplevel for surface {}", xdg_surface_id);
                if let Some(data) = data {
                    // Create a new window for this toplevel
                    let window_id = state.next_window_id();
                    let mut window = Window::new(window_id, data.surface_id);
                    
                    // Get output dimensions for initial size (already logical)
                    let (initial_width, initial_height) = {
                        let output = state.primary_output();
                        (output.width, output.height)
                    };

                    window.width = initial_width as i32;
                    window.height = initial_height as i32;
                    
                    // Create toplevel data (wl_surface_id, xdg_surface_id)
                    let mut toplevel_data = XdgToplevelData::new(window_id, data.surface_id, xdg_surface_id);
                    toplevel_data.width = initial_width;
                    toplevel_data.height = initial_height;
                    // Store the window ID (u32) as user data for the toplevel resource
                    let toplevel: wayland_protocols::xdg::shell::server::xdg_toplevel::XdgToplevel = data_init.init(id, window_id);
                    toplevel_data.resource = Some(toplevel.clone());
                    
                    state.xdg.toplevels.insert((client_id.clone(), toplevel.id().protocol_id()), toplevel_data);
                    
                    // Update surface data with window_id
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                        surface_data.window_id = Some(window_id);
                    }
                    
                    // Add window to state
                    state.add_window(window);
                    
                    // Send initial configure.
                    // When Force SSD is active the platform window has a native
                    // titlebar that reduces the usable content area below the
                    // full output size.  Sending (0, 0) here defers the size
                    // decision to the client and avoids the nested compositor
                    // latching onto the raw output dimensions before the correct
                    // content-area size arrives via the subsequent injectWindowResize
                    // that handleWindowCreated: fires after NSWindow is created.
                    //
                    // For non-SSD (CSD) windows we continue to send the output
                    // size as a hint so the client can size itself reasonably.
                    let serial = state.next_serial();
                    
                    let mut states: Vec<u8> = vec![];
                    states.extend_from_slice(&((wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated as u32).to_ne_bytes()));
                    
                    let (configure_w, configure_h) = match state.decoration_policy {
                        crate::core::state::DecorationPolicy::ForceServer => (0u32, 0u32),
                        _ => (initial_width, initial_height),
                    };

                    crate::wlog!(crate::util::logging::COMPOSITOR, 
                        "Configuring xdg_toplevel: window={} surface={} size={}x{} (force_ssd={}) states={:?} serial={}", 
                        window_id, data.surface_id, configure_w, configure_h,
                        matches!(state.decoration_policy, crate::core::state::DecorationPolicy::ForceServer),
                        states, serial);

                    toplevel.configure(configure_w as i32, configure_h as i32, states);
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                        surface_data.pending_serial = serial;
                    }
                    resource.configure(serial);
                    
                    // Set surface role
                    if let Some(surface) = state.get_surface(data.surface_id) {
                        let mut surface = surface.write().unwrap();
                        if let Err(e) = surface.set_role(crate::core::surface::SurfaceRole::Toplevel) {
                            tracing::error!("Failed to set role for surface {}: {}", data.surface_id, e);
                        }
                    }
                    
                    tracing::info!(
                        "Created xdg_toplevel: window_id={}, surface_id={}, size={}x{}",
                        window_id, data.surface_id, initial_width, initial_height
                    );
                    

                    // CRITICAL: Push WindowCreated event for FFI layer to create platform window
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowCreated {
                            client_id: client_id.clone(),
                            window_id,
                            surface_id: data.surface_id,
                            title: String::new(),  // Title will be set via set_title later
                            width: initial_width,
                            height: initial_height,
                            decoration_mode: state.decoration_mode_for_new_window(),
                            fullscreen_shell: false,
                        }
                    );
                }
            }
            xdg_surface::Request::GetPopup { id, parent, positioner } => {
                if let Some(data) = data {
                    let wl_surface_id = data.surface_id;
                    // Set surface role
                    if let Some(surface) = state.get_surface(wl_surface_id) {
                        let mut surface = surface.write().unwrap();
                        if let Err(e) = surface.set_role(crate::core::surface::SurfaceRole::Popup) {
                            tracing::error!("Failed to set role for surface {}: {}", wl_surface_id, e);
                            return;
                        }
                    }

                    // Get positioner data
                    let positioner_data = state.xdg.positioners
                        .remove(&(client_id.clone(), positioner.id().protocol_id()))
                        .unwrap_or_default();

                    // Get output dimensions for initial size
                    let (ox, oy, initial_width, initial_height, _scale) = {
                        let output = state.primary_output();
                        (output.x, output.y, output.width, output.height, output.scale)
                    };
                    
                    let output_rect = crate::util::geometry::Rect::new(ox, oy, initial_width, initial_height);
                    
                    // Calculate position using anchor/gravity rules
                    let (px, py) = positioner_data.calculate_position(output_rect);
                    
                    // Create popup state
                    let window_id = state.next_window_id();
                    let parent_window_id = if let Some(parent_obj) = parent.as_ref() {
                        state
                            .xdg
                            .surfaces
                            .get(&(client_id.clone(), parent_obj.id().protocol_id()))
                            .and_then(|d| d.window_id)
                    } else {
                        None
                    };
                    let popup_data = XdgPopupData {
                        surface_id: wl_surface_id,
                        xdg_surface_id,
                        window_id,
                        parent_id: parent_window_id,
                        geometry: (px, py, positioner_data.width, positioner_data.height),
                        anchor_rect: positioner_data.anchor_rect,
                        grabbed: false,
                        repositioned_token: None,
                        resource: None,
                    };
                    
                    // Initialize the popup with window_id (u32)
                    let popup: wayland_protocols::xdg::shell::server::xdg_popup::XdgPopup = data_init.init(id, window_id);
                    
                    let mut popup_data = popup_data;
                    popup_data.resource = Some(popup.clone());
                    
                    state.xdg.popups.insert((client_id.clone(), popup.id().protocol_id()), popup_data);
                    
                    // CRITICAL: Register in surface_to_window for buffer routing
                    state.surface_to_window.insert(wl_surface_id, window_id);
                    
                    // Update surface data with window_id
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                        surface_data.window_id = Some(window_id);
                    }
                    
                    tracing::debug!("Created xdg_popup for surface {}, window_id={}", wl_surface_id, window_id);

                    // Send enter events for all bound outputs
                    let surface_res = if let Some(s) = state.get_surface(wl_surface_id) {
                        s.read().unwrap().resource.clone()
                    } else {
                        None
                    };

                    if let Some(surface_res) = surface_res {
                        for output in state.output_resources.values() {
                            // Only send enter event if output belongs to the same client
                            if surface_res.client() == output.client() {
                                surface_res.enter(output);
                            }
                        }
                    }

                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::PopupCreated {
                            client_id: client_id.clone(),
                            window_id,
                            surface_id: wl_surface_id,
                            parent_id: parent_window_id.unwrap_or(0),
                            x: px,
                            y: py,
                            width: positioner_data.width.max(1) as u32,
                            height: positioner_data.height.max(1) as u32,
                        }
                    );

                    // Send initial configure
                        let next_serial = state.next_serial();
                        crate::wlog!(crate::util::logging::COMPOSITOR, "Configuring xdg_popup: window={} surface={} x={} y={} w={} h={} serial={}", 
                            window_id, wl_surface_id, px, py, positioner_data.width, positioner_data.height, next_serial);

                        popup.configure(px, py, positioner_data.width, positioner_data.height);
                        
                        // Send surface configure
                        if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                            surface_data.pending_serial = next_serial;
                        }
                        resource.configure(next_serial);
                        return;
                }
            }
            xdg_surface::Request::AckConfigure { serial } => {
                crate::wlog!(crate::util::logging::COMPOSITOR, "Client acked configure serial {}", serial);
                if let Some(data) = data {
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                        surface_data.configured = true;
                        // Clear pending only when the latest serial is acked;
                        // older serials are valid per xdg-shell protocol.
                        if serial == surface_data.pending_serial {
                            surface_data.pending_serial = 0;
                        }
                    }

                    // Mark the window as configured
                    if let Some(window_id) = data.window_id {
                        if let Some(window) = state.get_window(window_id) {
                            // Window is now ready
                            tracing::debug!("Window {} is now configured", window_id);
                            
                            // Check for toplevel state transitions
                            let mut to_finalize = None;
                            for ((cid, tl_proto_id), tl_data) in state.xdg.toplevels.iter() {
                                if *cid == client_id && tl_data.xdg_surface_id == xdg_surface_id && tl_data.pending_serial == serial {
                                    to_finalize = Some((cid.clone(), *tl_proto_id));
                                    break;
                                }
                            }
                            
                            if let Some(key) = to_finalize {
                                let mut window = window.write().unwrap();
                                if let Some(tl_data) = state.xdg.toplevels.get_mut(&key) {
                                    tl_data.maximized = tl_data.pending_maximized;
                                    tl_data.fullscreen = tl_data.pending_fullscreen;
                                    
                                    // Mirror to window state
                                    window.maximized = tl_data.maximized;
                                    window.fullscreen = tl_data.fullscreen;
                                    
                                    tracing::info!("Finalized state for window {}: maximized={}, fullscreen={}", 
                                        window_id, tl_data.maximized, tl_data.fullscreen);
                                }
                            }
                        }
                    }
                }
            }
            xdg_surface::Request::SetWindowGeometry { x, y, width, height } => {
                tracing::debug!(
                    "xdg_surface.set_window_geometry: ({}, {}) {}x{}",
                    x, y, width, height
                );
                if let Some(surface_data) = state.xdg.surfaces.get_mut(&(client_id.clone(), xdg_surface_id)) {
                    surface_data.geometry = Some((x, y, width, height));
                }
            }
            xdg_surface::Request::Destroy => {
                state.xdg.surfaces.remove(&(client_id, xdg_surface_id));
                tracing::debug!("xdg_surface destroyed");
            }
            _ => {}
        }
    }
}
