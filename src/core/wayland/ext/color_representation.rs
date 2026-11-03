//! Color Representation protocol implementation.
//!
//! Provides color representation hints for surfaces (alpha mode, YCbCr
//! coefficients/range, chroma location). State lives in Rust core; hosts
//! consume it when presenting buffers.

use std::collections::HashMap;

use wayland_protocols::wp::color_representation::v1::server::{
    wp_color_representation_manager_v1::{self, WpColorRepresentationManagerV1},
    wp_color_representation_surface_v1::{self, WpColorRepresentationSurfaceV1},
};
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource, WEnum,
};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol_proofs::{
    color_representation_alpha_mode_supported, color_representation_rejects_duplicate_surface,
};

/// Pending (double-buffered until commit semantics are applied by the host)
/// color representation for a surface.
#[derive(Debug, Clone, Default)]
pub struct ColorRepresentationSurfaceState {
    pub alpha_mode: Option<u32>,
    pub coefficients: Option<u32>,
    pub range: Option<u32>,
    pub chroma_location: Option<u32>,
}

#[derive(Debug, Default)]
pub struct ColorRepresentationState {
    /// surface_id → pending metadata
    pub surfaces: HashMap<u32, ColorRepresentationSurfaceState>,
}

#[derive(Debug, Clone)]
pub struct ColorRepresentationSurfaceData {
    pub surface_id: u32,
}

impl GlobalDispatch<WpColorRepresentationManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpColorRepresentationManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        use wp_color_representation_surface_v1::{AlphaMode, Coefficients, Range};
        let mgr = data_init.init(resource, ());
        mgr.supported_alpha_mode(AlphaMode::PremultipliedElectrical);
        mgr.supported_alpha_mode(AlphaMode::PremultipliedOptical);
        mgr.supported_alpha_mode(AlphaMode::Straight);
        mgr.supported_coefficients_and_ranges(Coefficients::Identity, Range::Full);
        mgr.supported_coefficients_and_ranges(Coefficients::Bt709, Range::Full);
        mgr.supported_coefficients_and_ranges(Coefficients::Bt709, Range::Limited);
        mgr.supported_coefficients_and_ranges(Coefficients::Bt2020, Range::Full);
        mgr.done();
        tracing::debug!("Bound wp_color_representation_manager_v1");
    }
}

impl Dispatch<WpColorRepresentationManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpColorRepresentationManagerV1,
        request: wp_color_representation_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_representation_manager_v1::Request::GetSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let already = state
                    .ext
                    .color_representation
                    .surfaces
                    .contains_key(&surface_id);
                if color_representation_rejects_duplicate_surface(already) {
                    resource.post_error(
                        wp_color_representation_manager_v1::Error::SurfaceExists,
                        "color representation surface already exists for this wl_surface",
                    );
                    return;
                }
                data_init.init(id, ColorRepresentationSurfaceData { surface_id });
                state
                    .ext
                    .color_representation
                    .surfaces
                    .insert(surface_id, ColorRepresentationSurfaceState::default());
                tracing::debug!("Created color representation for surface {}", surface_id);
            }
            wp_color_representation_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpColorRepresentationSurfaceV1, ColorRepresentationSurfaceData> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpColorRepresentationSurfaceV1,
        request: wp_color_representation_surface_v1::Request,
        data: &ColorRepresentationSurfaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_representation_surface_v1::Request::SetAlphaMode { alpha_mode } => {
                let raw = match alpha_mode {
                    WEnum::Value(m) => m as u32,
                    WEnum::Unknown(v) => v,
                };
                if !color_representation_alpha_mode_supported(raw) {
                    resource.post_error(
                        wp_color_representation_surface_v1::Error::AlphaMode,
                        "unsupported alpha mode",
                    );
                    return;
                }
                if let Some(s) = state
                    .ext
                    .color_representation
                    .surfaces
                    .get_mut(&data.surface_id)
                {
                    s.alpha_mode = Some(raw);
                }
            }
            wp_color_representation_surface_v1::Request::SetCoefficientsAndRange {
                coefficients,
                range,
            } => {
                let coeffs = match coefficients {
                    WEnum::Value(c) => c as u32,
                    WEnum::Unknown(v) => v,
                };
                let rng = match range {
                    WEnum::Value(r) => r as u32,
                    WEnum::Unknown(v) => v,
                };
                // Identity(1)+Full(1), Bt709(2)+Full/Limited, Bt2020(6)+Full
                let ok = matches!(
                    (coeffs, rng),
                    (1, 1) | (2, 1) | (2, 2) | (6, 1)
                );
                if !ok {
                    resource.post_error(
                        wp_color_representation_surface_v1::Error::Coefficients,
                        "unsupported coefficients/range combination",
                    );
                    return;
                }
                if let Some(s) = state
                    .ext
                    .color_representation
                    .surfaces
                    .get_mut(&data.surface_id)
                {
                    s.coefficients = Some(coeffs);
                    s.range = Some(rng);
                }
            }
            wp_color_representation_surface_v1::Request::SetChromaLocation { chroma_location } => {
                let loc = match chroma_location {
                    WEnum::Value(c) => c as u32,
                    WEnum::Unknown(v) => v,
                };
                if loc == 0 || loc > 6 {
                    resource.post_error(
                        wp_color_representation_surface_v1::Error::ChromaLocation,
                        "invalid chroma location",
                    );
                    return;
                }
                if let Some(s) = state
                    .ext
                    .color_representation
                    .surfaces
                    .get_mut(&data.surface_id)
                {
                    s.chroma_location = Some(loc);
                }
            }
            wp_color_representation_surface_v1::Request::Destroy => {
                state
                    .ext
                    .color_representation
                    .surfaces
                    .remove(&data.surface_id);
            }
            _ => {}
        }
    }
}

pub fn register_color_representation(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpColorRepresentationManagerV1, ()>(1, ())
}

#[cfg(test)]
mod tests {
    use crate::core::wayland::protocol_proofs::{
        color_representation_alpha_mode_supported, color_representation_rejects_duplicate_surface,
    };

    #[test]
    fn alpha_modes_0_1_2() {
        assert!(color_representation_alpha_mode_supported(0));
        assert!(color_representation_alpha_mode_supported(2));
        assert!(!color_representation_alpha_mode_supported(3));
    }

    #[test]
    fn duplicate_surface_rejected() {
        assert!(color_representation_rejects_duplicate_surface(true));
        assert!(!color_representation_rejects_duplicate_surface(false));
    }
}
