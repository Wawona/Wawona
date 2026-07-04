
use super::buffer::BufferType;
use super::role::SurfaceRole;
use super::damage::DamageRegion;
use wayland_server::backend::ClientId;

/// Represents the state of a surface at a point in time.
/// Used for double-buffering (pending vs current).
#[derive(Debug, Clone)]
pub struct SurfaceState {
    pub buffer: BufferType,
    pub buffer_id: Option<u32>,
    pub width: i32,
    pub height: i32,
    pub offset: (i32, i32),
    pub damage: Vec<DamageRegion>,
    pub buffer_damage: Vec<DamageRegion>,
    pub input_region: Option<Vec<crate::core::surface::damage::DamageRegion>>, // Using DamageRegion as Rect equivalent for now
    pub opaque_region: Option<Vec<crate::core::surface::damage::DamageRegion>>,
    pub opaque: bool,
    pub scale: i32,
    pub transform: wayland_server::protocol::wl_output::Transform, // Using the protocol enum directly
}

/// Represents a Wayland Surface.
pub struct Surface {
    pub id: u32,
    pub client_id: Option<ClientId>,
    pub role: SurfaceRole,
    
    /// The Wayland resource handle
    pub resource: Option<wayland_server::protocol::wl_surface::WlSurface>,
    
    /// The state currently visible to the compositor
    pub current: SurfaceState,
    /// The state being built by client requests, to be applied on commit.
    /// Sync-subsurface caching lives in smithay; by the time Wawona's commit
    /// handler runs, the state has already been applied protocol-side.
    pub pending: SurfaceState,
}

impl Surface {
    pub fn new(id: u32, client_id: Option<ClientId>, resource: Option<wayland_server::protocol::wl_surface::WlSurface>) -> Self {
        Self {
            id,
            client_id,
            role: SurfaceRole::None,
            resource,
            current: SurfaceState::default(),
            pending: SurfaceState::default(),
        }
    }

    /// Set the surface role. Returns error if role is already set to something else.
    pub fn set_role(&mut self, role: SurfaceRole) -> std::result::Result<(), String> {
        if self.role != SurfaceRole::None && self.role != role {
            return Err(format!(
                "Surface {} has role {:?}, cannot change to {:?}",
                self.id, self.role, role
            ));
        }
        self.role = role;
        Ok(())
    }

    /// Commit the pending state to current
    /// Returns the ID of the buffer to release, if any.
    pub fn commit(&mut self) -> Option<u32> {
        let release_id = super::commit::apply_commit(&mut self.pending, &mut self.current);
        
        tracing::debug!(
            "Surface {} committed: {}x{}, buffer={:?}",
            self.id, self.current.width, self.current.height, self.current.buffer
        );
        
        release_id
    }

}

impl Default for SurfaceState {
    fn default() -> Self {
        Self {
            buffer: BufferType::default(),
            buffer_id: None,
            width: 0,
            height: 0,
            offset: (0, 0),
            damage: Vec::new(),
            buffer_damage: Vec::new(),
            input_region: None, // None means infinite (accept all input)
            opaque_region: None, // None means empty (fully transparent)
            opaque: false, // Legacy field, might be redundant with opaque_region but kept for now
            scale: 1,
            transform: wayland_server::protocol::wl_output::Transform::Normal,
        }
    }
}
