//! WP Pointer Constraints protocol implementation.
//!
//! This protocol allows clients to lock or confine the pointer:
//! - Lock: Pointer is hidden and all motion is relative
//! - Confine: Pointer is constrained to a region


use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::pointer_constraints::zv1::server::{
    zwp_pointer_constraints_v1::{self, ZwpPointerConstraintsV1, Lifetime},
    zwp_locked_pointer_v1::{self, ZwpLockedPointerV1},
    zwp_confined_pointer_v1::{self, ZwpConfinedPointerV1},
};


use crate::core::state::CompositorState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with locked pointer
#[derive(Debug, Clone)]
pub struct LockedPointerData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
    pub resource: ZwpLockedPointerV1,
    /// Optional constraint region (None means entire surface)
    pub region: Option<Vec<crate::core::surface::damage::DamageRegion>>,
}

/// Data stored with confined pointer
#[derive(Debug, Clone)]
pub struct ConfinedPointerData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
    pub resource: ZwpConfinedPointerV1,
    /// Optional constraint region (None means entire surface)
    pub region: Option<Vec<crate::core::surface::damage::DamageRegion>>,
}

/// Constraint lifetime
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConstraintLifetime {
    /// Constraint is persistent until explicitly destroyed
    Persistent,
    /// Constraint deactivates when pointer leaves surface
    Oneshot,
}

/// State for pointer constraints
#[derive(Debug, Default)]
pub struct PointerConstraintsState {
    pub locked_pointers: HashMap<(wayland_server::backend::ClientId, u32), LockedPointerData>,
    pub confined_pointers: HashMap<(wayland_server::backend::ClientId, u32), ConfinedPointerData>,
}

impl PointerConstraintsState {
    pub fn activate_constraints(&mut self, client_id: wayland_server::backend::ClientId, surface_id: u32) {
        for locked in self.locked_pointers.values_mut() {
            if locked.surface_id == surface_id && !locked.active {
                locked.active = true;
                locked.resource.locked();
            }
        }
        for confined in self.confined_pointers.values_mut() {
            if confined.surface_id == surface_id && !confined.active {
                confined.active = true;
                confined.resource.confined();
            }
        }
    }

    pub fn deactivate_constraints(&mut self, client_id: wayland_server::backend::ClientId, surface_id: u32) {
        for locked in self.locked_pointers.values_mut() {
            if locked.surface_id == surface_id && locked.active {
                locked.active = false;
                locked.resource.unlocked();
            }
        }
        for confined in self.confined_pointers.values_mut() {
            if confined.surface_id == surface_id && confined.active {
                confined.active = false;
                confined.resource.unconfined();
            }
        }
    }

    pub fn is_pointer_locked(&self, client_id: wayland_server::backend::ClientId, surface_id: u32) -> bool {
        self.locked_pointers.iter().any(|((cid, _), l)| *cid == client_id && l.surface_id == surface_id && l.active)
    }
}


impl From<Lifetime> for ConstraintLifetime {
    fn from(l: Lifetime) -> Self {
        match l {
            Lifetime::Persistent => Self::Persistent,
            Lifetime::Oneshot => Self::Oneshot,
            _ => Self::Oneshot,
        }
    }
}

impl From<wayland_server::WEnum<Lifetime>> for ConstraintLifetime {
    fn from(l: wayland_server::WEnum<Lifetime>) -> Self {
        match l {
            wayland_server::WEnum::Value(Lifetime::Persistent) => Self::Persistent,
            wayland_server::WEnum::Value(Lifetime::Oneshot) => Self::Oneshot,
            _ => Self::Oneshot,
        }
    }
}

// ============================================================================
// zwp_pointer_constraints_v1
// ============================================================================

impl GlobalDispatch<ZwpPointerConstraintsV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpPointerConstraintsV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_pointer_constraints_v1");
    }
}

impl Dispatch<ZwpPointerConstraintsV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpPointerConstraintsV1,
        request: zwp_pointer_constraints_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_pointer_constraints_v1::Request::LockPointer {
                id,
                surface,
                pointer,
                region,
                lifetime,
            } => {
                let surface_id = surface.id().protocol_id();
                let pointer_id = pointer.id().protocol_id();
                let client_id = _client.id();
                
                let locked = data_init.init(id, ());
                let locked_id = locked.id().protocol_id();
                
                // Extract region data if provided
                let constraint_region = region.as_ref().and_then(|r| {
                    state.regions.get(&(client_id.clone(), r.id().protocol_id())).cloned()
                });

                let data = LockedPointerData {
                    surface_id,
                    pointer_id,
                    lifetime: lifetime.into(),
                    active: false,
                    resource: locked.clone(),
                    region: constraint_region.clone(),
                };
                
                state.ext.pointer_constraints.locked_pointers.insert((client_id.clone(), locked_id), data);
                
                // If the surface already has focus, activate immediately
                if state.seat.pointer.focus == Some(surface_id) {
                     state.ext.pointer_constraints.activate_constraints(client_id, surface_id);
                }

                tracing::debug!(
                    "Created locked pointer for surface {} (lifetime={:?}, region={:?})",
                    surface_id, lifetime, constraint_region.as_ref().map(|r| r.len())
                );
            }
            zwp_pointer_constraints_v1::Request::ConfinePointer {
                id,
                surface,
                pointer,
                region,
                lifetime,
            } => {
                let surface_id = surface.id().protocol_id();
                let pointer_id = pointer.id().protocol_id();
                let client_id = _client.id();
                
                let confined = data_init.init(id, ());
                let confined_id = confined.id().protocol_id();

                // Extract region data if provided
                let constraint_region = region.as_ref().and_then(|r| {
                    state.regions.get(&(client_id.clone(), r.id().protocol_id())).cloned()
                });

                let data = ConfinedPointerData {
                    surface_id,
                    pointer_id,
                    lifetime: lifetime.into(),
                    active: false,
                    resource: confined.clone(),
                    region: constraint_region.clone(),
                };
                
                state.ext.pointer_constraints.confined_pointers.insert((client_id.clone(), confined_id), data);
                
                // If the surface already has focus, activate immediately
                if state.seat.pointer.focus == Some(surface_id) {
                     state.ext.pointer_constraints.activate_constraints(client_id, surface_id);
                }

                tracing::debug!(
                    "Created confined pointer for surface {} (lifetime={:?}, region={:?})",
                    surface_id, lifetime, constraint_region.as_ref().map(|r| r.len())
                );
            }
            zwp_pointer_constraints_v1::Request::Destroy => {
                tracing::debug!("zwp_pointer_constraints_v1 destroyed");
            }
            _ => {}
        }
        let _ = resource;
    }
}

// ============================================================================
// zwp_locked_pointer_v1
// ============================================================================

impl Dispatch<ZwpLockedPointerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpLockedPointerV1,
        request: zwp_locked_pointer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_locked_pointer_v1::Request::SetCursorPositionHint { surface_x, surface_y } => {
                tracing::debug!(
                    "Locked pointer cursor hint: ({}, {})",
                    surface_x, surface_y
                );
            }
            zwp_locked_pointer_v1::Request::SetRegion { region } => {
                tracing::debug!("Locked pointer region updated");
                let _ = region;
            }
            zwp_locked_pointer_v1::Request::Destroy => {
                state.ext.pointer_constraints.locked_pointers.remove(&(_client.id(), resource.id().protocol_id()));
                tracing::debug!("Locked pointer destroyed");
            }

            _ => {}
        }
        let _ = resource;
    }
}

// ============================================================================
// zwp_confined_pointer_v1
// ============================================================================

impl Dispatch<ZwpConfinedPointerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpConfinedPointerV1,
        request: zwp_confined_pointer_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_confined_pointer_v1::Request::SetRegion { region } => {
                tracing::debug!("Confined pointer region updated");
                let _ = region;
            }
            zwp_confined_pointer_v1::Request::Destroy => {
                state.ext.pointer_constraints.confined_pointers.remove(&(_client.id(), resource.id().protocol_id()));
                tracing::debug!("Confined pointer destroyed");
            }

            _ => {}
        }
        let _ = resource;
    }
}

/// Register zwp_pointer_constraints_v1 global
pub fn register_pointer_constraints(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpPointerConstraintsV1, ()>(1, ())
}
