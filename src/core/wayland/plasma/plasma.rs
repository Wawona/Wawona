//! KDE/Plasma protocol implementations for Wawona.
//!
//! Effect / DPMS / idle / slide state lives in Rust core. Hosts apply blur,
//! contrast, shadow, and DPMS via capability hooks.

use std::collections::HashMap;

use wayland_server::{Dispatch, DisplayHandle, GlobalDispatch, Resource};

use crate::core::wayland::protocol::server::plasma::{
    blur::server::{
        org_kde_kwin_blur::{self, OrgKdeKwinBlur},
        org_kde_kwin_blur_manager::{self, OrgKdeKwinBlurManager},
    },
    contrast::server::{
        org_kde_kwin_contrast::{self, OrgKdeKwinContrast},
        org_kde_kwin_contrast_manager::{self, OrgKdeKwinContrastManager},
    },
    dpms::server::{
        org_kde_kwin_dpms::{self, OrgKdeKwinDpms},
        org_kde_kwin_dpms_manager::{self, OrgKdeKwinDpmsManager},
    },
    idle::server::{
        org_kde_kwin_idle::{self, OrgKdeKwinIdle},
        org_kde_kwin_idle_timeout::{self, OrgKdeKwinIdleTimeout},
    },
    shadow::server::{
        org_kde_kwin_shadow::{self, OrgKdeKwinShadow},
        org_kde_kwin_shadow_manager::{self, OrgKdeKwinShadowManager},
    },
    slide::server::{
        org_kde_kwin_slide::{self, OrgKdeKwinSlide},
        org_kde_kwin_slide_manager::{self, OrgKdeKwinSlideManager},
    },
};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct SurfaceBlurState {
    pub enabled: bool,
}

#[derive(Debug, Clone, Default)]
pub struct SurfaceContrastState {
    pub contrast: f64,
    pub intensity: f64,
    pub saturation: f64,
}

#[derive(Debug, Clone, Default)]
pub struct SurfaceShadowState {
    pub enabled: bool,
}

#[derive(Debug, Clone, Default)]
pub struct SurfaceSlideState {
    pub location: u32,
    pub offset: i32,
}

#[derive(Debug, Default)]
pub struct PlasmaEffectsState {
    pub blur: HashMap<u32, SurfaceBlurState>,
    pub contrast: HashMap<u32, SurfaceContrastState>,
    pub shadow: HashMap<u32, SurfaceShadowState>,
    pub slide: HashMap<u32, SurfaceSlideState>,
    /// idle timeout resource id → timeout msec
    pub idle_timeouts: HashMap<u32, u32>,
}

// ============================================================================
// Blur
// ============================================================================

pub struct BlurManagerGlobal;

impl GlobalDispatch<OrgKdeKwinBlurManager, BlurManagerGlobal> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinBlurManager>,
        _global_data: &BlurManagerGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound org_kde_kwin_blur_manager");
    }
}

impl Dispatch<OrgKdeKwinBlurManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinBlurManager,
        request: org_kde_kwin_blur_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_blur_manager::Request::Create { id, surface } => {
                let surface_id = surface.id().protocol_id();
                data_init.init(id, surface_id);
                state
                    .plasma
                    .effects
                    .blur
                    .insert(surface_id, SurfaceBlurState { enabled: true });
            }
            org_kde_kwin_blur_manager::Request::Unset { surface } => {
                state
                    .plasma
                    .effects
                    .blur
                    .remove(&surface.id().protocol_id());
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinBlur, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinBlur,
        request: org_kde_kwin_blur::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_blur::Request::Commit => {
                state
                    .plasma
                    .effects
                    .blur
                    .entry(*surface_id)
                    .or_default()
                    .enabled = true;
            }
            org_kde_kwin_blur::Request::SetRegion { .. } => {}
            org_kde_kwin_blur::Request::Release => {
                state.plasma.effects.blur.remove(surface_id);
            }
            _ => {}
        }
    }
}

// ============================================================================
// Contrast
// ============================================================================

pub struct ContrastManagerGlobal;

impl GlobalDispatch<OrgKdeKwinContrastManager, ContrastManagerGlobal> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinContrastManager>,
        _global_data: &ContrastManagerGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<OrgKdeKwinContrastManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinContrastManager,
        request: org_kde_kwin_contrast_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_contrast_manager::Request::Create { id, surface } => {
                let surface_id = surface.id().protocol_id();
                data_init.init(id, surface_id);
                state
                    .plasma
                    .effects
                    .contrast
                    .insert(surface_id, SurfaceContrastState::default());
            }
            org_kde_kwin_contrast_manager::Request::Unset { surface } => {
                state
                    .plasma
                    .effects
                    .contrast
                    .remove(&surface.id().protocol_id());
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinContrast, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinContrast,
        request: org_kde_kwin_contrast::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let entry = state.plasma.effects.contrast.entry(*surface_id).or_default();
        match request {
            org_kde_kwin_contrast::Request::SetContrast { contrast } => {
                entry.contrast = contrast;
            }
            org_kde_kwin_contrast::Request::SetIntensity { intensity } => {
                entry.intensity = intensity;
            }
            org_kde_kwin_contrast::Request::SetSaturation { saturation } => {
                entry.saturation = saturation;
            }
            org_kde_kwin_contrast::Request::Commit => {}
            org_kde_kwin_contrast::Request::SetRegion { .. } => {}
            org_kde_kwin_contrast::Request::Release => {
                state.plasma.effects.contrast.remove(surface_id);
            }
            _ => {}
        }
    }
}

// ============================================================================
// Shadow
// ============================================================================

pub struct ShadowManagerGlobal;

impl GlobalDispatch<OrgKdeKwinShadowManager, ShadowManagerGlobal> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinShadowManager>,
        _global_data: &ShadowManagerGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<OrgKdeKwinShadowManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinShadowManager,
        request: org_kde_kwin_shadow_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_shadow_manager::Request::Create { id, surface } => {
                let surface_id = surface.id().protocol_id();
                data_init.init(id, surface_id);
                state
                    .plasma
                    .effects
                    .shadow
                    .insert(surface_id, SurfaceShadowState { enabled: true });
            }
            org_kde_kwin_shadow_manager::Request::Unset { surface } => {
                state
                    .plasma
                    .effects
                    .shadow
                    .remove(&surface.id().protocol_id());
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinShadow, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinShadow,
        request: org_kde_kwin_shadow::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_shadow::Request::Commit => {
                state
                    .plasma
                    .effects
                    .shadow
                    .entry(*surface_id)
                    .or_default()
                    .enabled = true;
            }
            org_kde_kwin_shadow::Request::Destroy => {
                state.plasma.effects.shadow.remove(surface_id);
            }
            _ => {}
        }
    }
}

// ============================================================================
// DPMS
// ============================================================================

impl GlobalDispatch<OrgKdeKwinDpmsManager, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinDpmsManager>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<OrgKdeKwinDpmsManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinDpmsManager,
        request: org_kde_kwin_dpms_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_dpms_manager::Request::Get { id, output: _ } => {
                let dpms = data_init.init(id, ());
                // Nested / portable hosts: DPMS not supported; still advertise On.
                dpms.supported(0);
                dpms.mode(org_kde_kwin_dpms::Mode::On as u32);
                dpms.done();
                let _ = state;
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinDpms, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &OrgKdeKwinDpms,
        request: org_kde_kwin_dpms::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_dpms::Request::Set { mode } => {
                // Protocol uses raw u32 Mode values (On=0 … Off=3).
                if let Some(out) = state.outputs.first_mut() {
                    out.power_mode = if mode == 0 { 1 } else { 0 };
                }
                resource.mode(mode);
                resource.done();
            }
            org_kde_kwin_dpms::Request::Release => {}
            _ => {}
        }
    }
}

// ============================================================================
// Idle (manager global is org_kde_kwin_idle)
// ============================================================================

impl GlobalDispatch<OrgKdeKwinIdle, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinIdle>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<OrgKdeKwinIdle, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinIdle,
        request: org_kde_kwin_idle::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_idle::Request::GetIdleTimeout {
                id,
                seat: _,
                timeout,
            } => {
                let timeout_res = data_init.init(id, ());
                state
                    .plasma
                    .effects
                    .idle_timeouts
                    .insert(timeout_res.id().protocol_id(), timeout);
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinIdleTimeout, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &OrgKdeKwinIdleTimeout,
        request: org_kde_kwin_idle_timeout::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_idle_timeout::Request::SimulateUserActivity => {
                // Host idle clock reset is a capability; protocol accepts the request.
                tracing::debug!("plasma idle simulate_user_activity");
            }
            org_kde_kwin_idle_timeout::Request::Release => {
                state
                    .plasma
                    .effects
                    .idle_timeouts
                    .remove(&resource.id().protocol_id());
            }
            _ => {}
        }
    }
}

// ============================================================================
// Slide
// ============================================================================

impl GlobalDispatch<OrgKdeKwinSlideManager, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<OrgKdeKwinSlideManager>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<OrgKdeKwinSlideManager, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinSlideManager,
        request: org_kde_kwin_slide_manager::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            org_kde_kwin_slide_manager::Request::Create { id, surface } => {
                let surface_id = surface.id().protocol_id();
                data_init.init(id, surface_id);
                state
                    .plasma
                    .effects
                    .slide
                    .insert(surface_id, SurfaceSlideState::default());
            }
            org_kde_kwin_slide_manager::Request::Unset { surface } => {
                state
                    .plasma
                    .effects
                    .slide
                    .remove(&surface.id().protocol_id());
            }
            _ => {}
        }
    }
}

impl Dispatch<OrgKdeKwinSlide, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &OrgKdeKwinSlide,
        request: org_kde_kwin_slide::Request,
        surface_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let entry = state.plasma.effects.slide.entry(*surface_id).or_default();
        match request {
            org_kde_kwin_slide::Request::SetLocation { location } => {
                entry.location = location;
            }
            org_kde_kwin_slide::Request::SetOffset { offset } => {
                entry.offset = offset;
            }
            org_kde_kwin_slide::Request::Commit => {}
            org_kde_kwin_slide::Request::Release => {
                state.plasma.effects.slide.remove(surface_id);
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plasma_effects_default_empty() {
        let e = PlasmaEffectsState::default();
        assert!(e.blur.is_empty());
        assert!(e.idle_timeouts.is_empty());
    }
}
