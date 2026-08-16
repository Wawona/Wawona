//! Session Lock protocol implementation.
//!
//! This protocol allows clients to lock the user session and display a lock screen.
//! When locked, all other surfaces are hidden. Lock surfaces receive configure
//! events with the output dimensions. UnlockAndDestroy releases the lock.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::wayland::protocol::server::ext::session_lock::v1::server::{
    ext_session_lock_manager_v1::{self, ExtSessionLockManagerV1},
    ext_session_lock_v1::{self, ExtSessionLockV1},
    ext_session_lock_surface_v1::{self, ExtSessionLockSurfaceV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Lock surface data. Tracks which output and surface this covers
#[derive(Debug, Clone)]
pub struct SessionLockSurfaceData {
    pub output_id: u32,
    pub surface_id: u32,
    pub pending_serial: u32,
}

/// Compositor-wide session lock state
#[derive(Debug, Default)]
pub struct SessionLockState {
    /// Whether the session is currently locked
    pub locked: bool,
    /// Active lock surfaces (lock_surface_id → data)
    pub lock_surfaces: HashMap<u32, SessionLockSurfaceData>,
    /// Serial counter for lock surface configures
    pub next_serial: u32,
}

impl SessionLockState {
    fn next_serial(&mut self) -> u32 {
        self.next_serial = self.next_serial.wrapping_add(1);
        self.next_serial
    }
}

// ============================================================================
// ext_session_lock_manager_v1
// ============================================================================

impl GlobalDispatch<ExtSessionLockManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ExtSessionLockManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound ext_session_lock_manager_v1");
    }
}

impl Dispatch<ExtSessionLockManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtSessionLockManagerV1,
        request: ext_session_lock_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_session_lock_manager_v1::Request::Lock { id } => {
                let lock = data_init.init(id, ());

                state.ext.session_lock.locked = true;
                // Acknowledge the lock
                lock.locked();

                tracing::info!("Session locked");
            }
            ext_session_lock_manager_v1::Request::Destroy => {
                tracing::debug!("ext_session_lock_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// ext_session_lock_v1
// ============================================================================

impl Dispatch<ExtSessionLockV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ExtSessionLockV1,
        request: ext_session_lock_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            ext_session_lock_v1::Request::GetLockSurface { id, surface, output } => {
                let output_id = output.id().protocol_id();
                let surface_id = surface.id().protocol_id();
                let serial = state.ext.session_lock.next_serial();

                let lock_surface = data_init.init(id, output_id);
                let ls_id = lock_surface.id().protocol_id();

                state.ext.session_lock.lock_surfaces.insert(ls_id, SessionLockSurfaceData {
                    output_id,
                    surface_id,
                    pending_serial: serial,
                });

                // Send configure with the output dimensions
                let output = state.primary_output();
                lock_surface.configure(serial, output.width, output.height);

                tracing::debug!(
                    "Created lock surface {} for output {} (surface {}), configure {}x{} serial {}",
                    ls_id, output_id, surface_id, output.width, output.height, serial
                );
            }
            ext_session_lock_v1::Request::UnlockAndDestroy => {
                state.ext.session_lock.locked = false;
                state.ext.session_lock.lock_surfaces.clear();
                tracing::info!("Session unlocked");
            }
            ext_session_lock_v1::Request::Destroy => {
                state.ext.session_lock.locked = false;
                state.ext.session_lock.lock_surfaces.clear();
                tracing::debug!("ext_session_lock_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// ext_session_lock_surface_v1. User data is output_id: u32
// ============================================================================

impl Dispatch<ExtSessionLockSurfaceV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ExtSessionLockSurfaceV1,
        request: ext_session_lock_surface_v1::Request,
        _output_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ls_id = resource.id().protocol_id();
        match request {
            ext_session_lock_surface_v1::Request::AckConfigure { serial } => {
                if let Some(data) = state.ext.session_lock.lock_surfaces.get(&ls_id) {
                    if data.pending_serial == serial {
                        tracing::debug!("Lock surface {} ack configure serial {}", ls_id, serial);
                    }
                }
            }
            ext_session_lock_surface_v1::Request::Destroy => {
                state.ext.session_lock.lock_surfaces.remove(&ls_id);
                tracing::debug!("Lock surface {} destroyed", ls_id);
            }
            _ => {}
        }
    }
}

/// Register ext_session_lock_manager_v1 global
pub fn register_session_lock(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ExtSessionLockManagerV1, ()>(1, ())
}
