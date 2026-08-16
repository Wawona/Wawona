//! wlr-output-management-unstable-v1 protocol implementation.
//!
//! This protocol allows clients to read and modify the compositor's output configuration.


use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};
use crate::core::wayland::protocol::wlroots::wlr_output_management_unstable_v1::{
    zwlr_output_manager_v1, zwlr_output_head_v1, zwlr_output_mode_v1,
    zwlr_output_configuration_v1, zwlr_output_configuration_head_v1,
};

use crate::core::state::CompositorState;

// ============================================================================
// Output Manager Global
// ============================================================================

pub struct OutputManagerGlobal;

impl GlobalDispatch<zwlr_output_manager_v1::ZwlrOutputManagerV1, ()> for CompositorState {
    fn bind(
        state: &mut Self,
        handle: &DisplayHandle,
        client: &wayland_server::Client,
        resource: wayland_server::New<zwlr_output_manager_v1::ZwlrOutputManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let manager = data_init.init(resource, ());
        let version = manager.version();
        
        // Advertise all current heads
        // Advertise all current heads
        for output in &state.outputs {
            // Correct order: <Resource, UserData, State>
            let head = client.create_resource::<zwlr_output_head_v1::ZwlrOutputHeadV1, (), CompositorState>(
                handle,
                version,
                (),
            ).expect("Failed to create zwlr_output_head_v1");
            
            manager.head(&head);
            
            // Send head metadata
            head.name(output.name.clone());
            head.description(output.description.clone());
            head.make(output.make.clone());
            head.model(output.model.clone());
            head.serial_number(output.serial_number.clone());
            head.physical_size(output.physical_width as i32, output.physical_height as i32);
            
            // Advertise modes for this head
            for (_i, mode_state) in output.modes.iter().enumerate() {
                let mode = client.create_resource::<zwlr_output_mode_v1::ZwlrOutputModeV1, (), CompositorState>(
                    handle,
                    head.version(),
                    (),
                ).expect("Failed to create zwlr_output_mode_v1");
                
                head.mode(&mode);
                
                mode.size(mode_state.width as i32, mode_state.height as i32);
                mode.refresh(mode_state.refresh as i32);
                if mode_state.preferred {
                    mode.preferred();
                }
            }
            
            // Current state
            head.enabled(1);
            head.position(output.x, output.y);
            
            // scale expects f64 in high-level wayland-rs 0.31
            head.scale(output.scale as f64);
            
            use wayland_server::protocol::wl_output;
            head.transform(wl_output::Transform::Normal);
        }
        
        manager.done(state.wlr.last_output_manager_serial);
        tracing::debug!("Bound zwlr_output_manager_v1 and advertised heads");
    }
}

impl Dispatch<zwlr_output_manager_v1::ZwlrOutputManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_output_manager_v1::ZwlrOutputManagerV1,
        request: zwlr_output_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_manager_v1::Request::CreateConfiguration { id, serial } => {
                data_init.init(id, ());
                tracing::debug!("Created zwlr_output_configuration_v1 with serial {}", serial);
            }
            zwlr_output_manager_v1::Request::Stop => {
                tracing::debug!("zwlr_output_manager_v1 stopped by client");
            }
            _ => {}
        }
    }
}

// ============================================================================
// Output Head
// ============================================================================

impl Dispatch<zwlr_output_head_v1::ZwlrOutputHeadV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_output_head_v1::ZwlrOutputHeadV1,
        request: zwlr_output_head_v1::Request,
        _output_id: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_head_v1::Request::Release => {
                tracing::debug!("zwlr_output_head_v1 released");
            }
            _ => {}
        }
    }
}

// ============================================================================
// Output Mode
// ============================================================================

impl Dispatch<zwlr_output_mode_v1::ZwlrOutputModeV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_output_mode_v1::ZwlrOutputModeV1,
        request: zwlr_output_mode_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_mode_v1::Request::Release => {
                tracing::debug!("zwlr_output_mode_v1 released");
            }
            _ => {}
        }
    }
}

// ============================================================================
// Output Configuration
// ============================================================================

impl Dispatch<zwlr_output_configuration_v1::ZwlrOutputConfigurationV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwlr_output_configuration_v1::ZwlrOutputConfigurationV1,
        request: zwlr_output_configuration_v1::Request,
        _serial: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_configuration_v1::Request::EnableHead { id, head: _ } => {
                data_init.init(id, ());
                tracing::debug!("zwlr_output_configuration_v1.enable_head");
            }
            zwlr_output_configuration_v1::Request::DisableHead { head: _ } => {
                tracing::debug!("zwlr_output_configuration_v1.disable_head");
            }
            zwlr_output_configuration_v1::Request::Apply => {
                tracing::info!("zwlr_output_configuration_v1.apply. Accepting configuration");
                // In a nested compositor, we accept the configuration and notify clients.
                // Platform-level changes (resolution, etc.) are managed by the host compositor.
                resource.succeeded();
            }
            zwlr_output_configuration_v1::Request::Test => {
                tracing::info!("zwlr_output_configuration_v1.test. All configurations valid");
                resource.succeeded();
            }
            zwlr_output_configuration_v1::Request::Destroy => {
                tracing::debug!("zwlr_output_configuration_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// Output Configuration Head
// ============================================================================

impl Dispatch<zwlr_output_configuration_head_v1::ZwlrOutputConfigurationHeadV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwlr_output_configuration_head_v1::ZwlrOutputConfigurationHeadV1,
        request: zwlr_output_configuration_head_v1::Request,
        _head: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwlr_output_configuration_head_v1::Request::SetMode { mode: _ } => {
                tracing::debug!("zwlr_output_configuration_head_v1.set_mode");
            }
            zwlr_output_configuration_head_v1::Request::SetCustomMode { width, height, refresh } => {
                tracing::debug!("zwlr_output_configuration_head_v1.set_custom_mode: {}x{}@{}", width, height, refresh);
            }
            zwlr_output_configuration_head_v1::Request::SetPosition { x, y } => {
                tracing::debug!("zwlr_output_configuration_head_v1.set_position: ({}, {})", x, y);
            }
            zwlr_output_configuration_head_v1::Request::SetTransform { transform: _ } => {
                tracing::debug!("zwlr_output_configuration_head_v1.set_transform");
            }
            zwlr_output_configuration_head_v1::Request::SetScale { scale: _ } => {
                tracing::debug!("zwlr_output_configuration_head_v1.set_scale");
            }
            _ => {}
        }
    }
}

/// Register zwlr_output_manager_v1 global
pub fn register_output_management(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwlr_output_manager_v1::ZwlrOutputManagerV1, ()>(1, ())
}
