//! WP Pointer Constraints protocol implementation.
//!
//! This protocol allows clients to lock or confine the pointer:
//! - Lock: Pointer is hidden and all motion is relative
//! - Confine: Pointer is constrained to a region

use wayland_protocols::wp::pointer_constraints::zv1::server::{
    zwp_confined_pointer_v1::{self, ZwpConfinedPointerV1},
    zwp_locked_pointer_v1::{self, ZwpLockedPointerV1},
    zwp_pointer_constraints_v1::{self, Lifetime, ZwpPointerConstraintsV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

/// Data stored with locked pointer
#[derive(Debug, Clone)]
pub struct LockedPointerData {
    /// Internal compositor surface id (not the client's protocol id).
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
    /// Oneshot constraint that was deactivated; it never reactivates.
    pub defunct: bool,
    pub resource: ZwpLockedPointerV1,
    /// Optional constraint region (None means entire surface)
    pub region: Option<Vec<crate::core::surface::damage::DamageRegion>>,
}

/// Data stored with confined pointer
#[derive(Debug, Clone)]
pub struct ConfinedPointerData {
    /// Internal compositor surface id (not the client's protocol id).
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
    /// Oneshot constraint that was deactivated; it never reactivates.
    pub defunct: bool,
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

/// The one activation policy: a constraint is in effect only while its
/// surface holds both keyboard focus and pointer focus, and a oneshot
/// constraint that was deactivated stays dead.
pub(crate) fn constraint_should_be_active(
    surface_id: u32,
    keyboard_focus: Option<u32>,
    pointer_focus: Option<u32>,
    defunct: bool,
) -> bool {
    !defunct && keyboard_focus == Some(surface_id) && pointer_focus == Some(surface_id)
}

/// Clamp a global pointer position into a confinement rectangle
/// `(x, y, width, height)`. The far edge is inclusive of the last pixel
/// (`x + width - 1`). Non-finite input pins to the rectangle origin.
pub(crate) fn clamp_to_confinement(px: f64, py: f64, rect: (i32, i32, i32, i32)) -> (f64, f64) {
    let (rx, ry, w, h) = rect;
    let (rx, ry) = (f64::from(rx), f64::from(ry));
    let max_x = rx + f64::from(w.max(1) - 1);
    let max_y = ry + f64::from(h.max(1) - 1);
    let clamp = |v: f64, lo: f64, hi: f64| if v.is_finite() { v.clamp(lo, hi) } else { lo };
    (clamp(px, rx, max_x), clamp(py, ry, max_y))
}

/// Effect of the active constraint on the focused surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActiveConstraint {
    Locked,
    Confined,
}

impl PointerConstraintsState {
    /// Apply [`constraint_should_be_active`] to every constraint, sending
    /// locked/unlocked and confined/unconfined on each transition.
    pub fn sync_activation(&mut self, keyboard_focus: Option<u32>, pointer_focus: Option<u32>) {
        for c in self.locked_pointers.values_mut() {
            let want =
                constraint_should_be_active(c.surface_id, keyboard_focus, pointer_focus, c.defunct);
            if want && !c.active {
                c.active = true;
                c.resource.locked();
            } else if !want && c.active {
                c.active = false;
                c.defunct = c.lifetime == ConstraintLifetime::Oneshot;
                c.resource.unlocked();
            }
        }
        for c in self.confined_pointers.values_mut() {
            let want =
                constraint_should_be_active(c.surface_id, keyboard_focus, pointer_focus, c.defunct);
            if want && !c.active {
                c.active = true;
                c.resource.confined();
            } else if !want && c.active {
                c.active = false;
                c.defunct = c.lifetime == ConstraintLifetime::Oneshot;
                c.resource.unconfined();
            }
        }
    }

    /// Active constraint on `surface_id`, lock taking precedence.
    pub fn active_on(&self, surface_id: u32) -> Option<ActiveConstraint> {
        if self
            .locked_pointers
            .values()
            .any(|c| c.surface_id == surface_id && c.active)
        {
            Some(ActiveConstraint::Locked)
        } else if self
            .confined_pointers
            .values()
            .any(|c| c.surface_id == surface_id && c.active)
        {
            Some(ActiveConstraint::Confined)
        } else {
            None
        }
    }

    pub fn is_pointer_locked(
        &self,
        client_id: wayland_server::backend::ClientId,
        surface_id: u32,
    ) -> bool {
        self.locked_pointers
            .iter()
            .any(|((cid, _), l)| *cid == client_id && l.surface_id == surface_id && l.active)
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
                let client_id = _client.id();
                let surface_protocol_id = surface.id().protocol_id();
                let surface_id = state
                    .protocol_to_internal_surface
                    .get(&(client_id.clone(), surface_protocol_id))
                    .copied()
                    .unwrap_or(surface_protocol_id);
                let pointer_id = pointer.id().protocol_id();

                let locked = data_init.init(id, ());
                let locked_id = locked.id().protocol_id();

                // Extract region data if provided
                let constraint_region = region.as_ref().and_then(|r| {
                    state
                        .regions
                        .get(&(client_id.clone(), r.id().protocol_id()))
                        .cloned()
                });

                let data = LockedPointerData {
                    surface_id,
                    pointer_id,
                    lifetime: lifetime.into(),
                    active: false,
                    defunct: false,
                    resource: locked.clone(),
                    region: constraint_region.clone(),
                };

                state
                    .ext
                    .pointer_constraints
                    .locked_pointers
                    .insert((client_id.clone(), locked_id), data);

                state.sync_pointer_constraints();

                tracing::debug!(
                    "Created locked pointer for surface {} (lifetime={:?}, region={:?})",
                    surface_id,
                    lifetime,
                    constraint_region.as_ref().map(|r| r.len())
                );
            }
            zwp_pointer_constraints_v1::Request::ConfinePointer {
                id,
                surface,
                pointer,
                region,
                lifetime,
            } => {
                let client_id = _client.id();
                let surface_protocol_id = surface.id().protocol_id();
                let surface_id = state
                    .protocol_to_internal_surface
                    .get(&(client_id.clone(), surface_protocol_id))
                    .copied()
                    .unwrap_or(surface_protocol_id);
                let pointer_id = pointer.id().protocol_id();

                let confined = data_init.init(id, ());
                let confined_id = confined.id().protocol_id();

                // Extract region data if provided
                let constraint_region = region.as_ref().and_then(|r| {
                    state
                        .regions
                        .get(&(client_id.clone(), r.id().protocol_id()))
                        .cloned()
                });

                let data = ConfinedPointerData {
                    surface_id,
                    pointer_id,
                    lifetime: lifetime.into(),
                    active: false,
                    defunct: false,
                    resource: confined.clone(),
                    region: constraint_region.clone(),
                };

                state
                    .ext
                    .pointer_constraints
                    .confined_pointers
                    .insert((client_id.clone(), confined_id), data);

                state.sync_pointer_constraints();

                tracing::debug!(
                    "Created confined pointer for surface {} (lifetime={:?}, region={:?})",
                    surface_id,
                    lifetime,
                    constraint_region.as_ref().map(|r| r.len())
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
            zwp_locked_pointer_v1::Request::SetCursorPositionHint {
                surface_x,
                surface_y,
            } => {
                tracing::debug!("Locked pointer cursor hint: ({}, {})", surface_x, surface_y);
            }
            zwp_locked_pointer_v1::Request::SetRegion { region } => {
                tracing::debug!("Locked pointer region updated");
                let _ = region;
            }
            zwp_locked_pointer_v1::Request::Destroy => {
                state
                    .ext
                    .pointer_constraints
                    .locked_pointers
                    .remove(&(_client.id(), resource.id().protocol_id()));
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
                state
                    .ext
                    .pointer_constraints
                    .confined_pointers
                    .remove(&(_client.id(), resource.id().protocol_id()));
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

#[cfg(test)]
mod tests {
    use super::{clamp_to_confinement, constraint_should_be_active};

    #[test]
    fn constraint_active_only_with_keyboard_and_pointer_focus() {
        assert!(constraint_should_be_active(7, Some(7), Some(7), false));
    }

    #[test]
    fn constraint_inactive_without_keyboard_focus() {
        assert!(!constraint_should_be_active(7, Some(3), Some(7), false));
    }

    #[test]
    fn constraint_inactive_without_pointer_focus() {
        assert!(!constraint_should_be_active(7, Some(7), None, false));
    }

    #[test]
    fn defunct_oneshot_never_reactivates() {
        assert!(!constraint_should_be_active(7, Some(7), Some(7), true));
    }

    #[test]
    fn confinement_clamps_to_last_pixel() {
        assert_eq!(
            clamp_to_confinement(500.0, 500.0, (0, 0, 100, 100)),
            (99.0, 99.0)
        );
    }

    #[test]
    fn confinement_clamps_to_origin() {
        assert_eq!(
            clamp_to_confinement(-50.0, 7.0, (10, 0, 100, 100)),
            (10.0, 7.0)
        );
    }

    #[test]
    fn confinement_non_finite_pins_to_origin() {
        assert_eq!(
            clamp_to_confinement(f64::NAN, f64::INFINITY, (5, 6, 100, 100)),
            (5.0, 6.0)
        );
    }

    #[test]
    fn confinement_degenerate_rect_is_single_pixel() {
        assert_eq!(clamp_to_confinement(40.0, 40.0, (5, 6, 0, -3)), (5.0, 6.0));
    }
}
