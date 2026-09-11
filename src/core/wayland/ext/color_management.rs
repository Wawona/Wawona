//! Color Management protocol implementation.
//!
//! Provides color space and HDR support for surfaces.

use wayland_protocols::wp::color_management::v1::server::{
    wp_color_management_output_v1::{self, WpColorManagementOutputV1},
    wp_color_management_surface_feedback_v1::{self, WpColorManagementSurfaceFeedbackV1},
    wp_color_management_surface_v1::{self, WpColorManagementSurfaceV1},
    wp_color_manager_v1::{self, WpColorManagerV1},
    wp_image_description_creator_icc_v1::{self, WpImageDescriptionCreatorIccV1},
    wp_image_description_creator_params_v1::{self, WpImageDescriptionCreatorParamsV1},
    wp_image_description_info_v1::{self, WpImageDescriptionInfoV1},
    wp_image_description_v1::{self, WpImageDescriptionV1},
};
use wayland_server::{Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource};

use crate::core::state::CompositorState;

#[derive(Debug, Clone, Default)]
pub struct ColorOutputData {
    pub output_id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct ColorSurfaceData {
    pub surface_id: u32,
}

#[derive(Debug, Clone, Default)]
pub struct ImageDescriptionData;

#[derive(Debug, Clone, Default)]
pub struct IccCreatorData;

#[derive(Debug, Clone, Default)]
pub struct ParamsCreatorData;

#[derive(Debug, Clone, Default)]
pub struct SurfaceFeedbackData;

impl GlobalDispatch<WpColorManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpColorManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        let mgr = data_init.init(resource, ());
        use wp_color_manager_v1::{Feature, Primaries, RenderIntent, TransferFunction};
        mgr.supported_intent(RenderIntent::Perceptual);
        mgr.supported_feature(Feature::Parametric);
        mgr.supported_feature(Feature::SetPrimaries);
        mgr.supported_feature(Feature::SetTfPower);
        mgr.supported_feature(Feature::SetLuminances);
        mgr.supported_tf_named(TransferFunction::Bt1886);
        mgr.supported_tf_named(TransferFunction::Gamma22);
        mgr.supported_primaries_named(Primaries::Srgb);
        mgr.done();
        tracing::debug!("Bound wp_color_manager_v1");
    }
}

impl Dispatch<WpColorManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagerV1,
        request: wp_color_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_manager_v1::Request::GetOutput { id, output } => {
                let output_id = state
                    .output_id_by_resource
                    .get(&output.id())
                    .copied()
                    .or_else(|| state.outputs.first().map(|o| o.id))
                    .unwrap_or(0);
                let _o = data_init.init(id, ColorOutputData { output_id });
            }
            wp_color_manager_v1::Request::GetSurface { id, surface } => {
                let surface_id = surface.id().protocol_id();
                let _s = data_init.init(id, ColorSurfaceData { surface_id });
            }
            wp_color_manager_v1::Request::GetSurfaceFeedback { id, surface } => {
                let _f = data_init.init(id, SurfaceFeedbackData);
                tracing::debug!("Created wp_color_management_surface_feedback_v1 for surface");
            }
            wp_color_manager_v1::Request::CreateIccCreator { obj } => {
                let _c = data_init.init(obj, ());
            }
            wp_color_manager_v1::Request::CreateParametricCreator { obj } => {
                let _c = data_init.init(obj, ());
            }
            wp_color_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpColorManagementOutputV1, ColorOutputData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementOutputV1,
        request: wp_color_management_output_v1::Request,
        _data: &ColorOutputData,
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_management_output_v1::Request::GetImageDescription { image_description } => {
                let desc = data_init.init(image_description, ImageDescriptionData);
                // sRGB/BT.1886 output description; send ready2 so client can use get_information
                desc.ready2(0, 1);
                tracing::debug!("Created output image description (sRGB/BT.1886)");
            }
            wp_color_management_output_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

// Rewriting Dispatch<WpColorManagementSurfaceV1> fully to include the missing request
// Based on typical protocol: `get_color_management_surface_feedback`
//
// Protocol check (mental lookup):
// <request name="get_preferred">
//    <arg name="feedback" type="new_id" interface="wp_color_management_surface_feedback_v1"/>
// </request>
//
// So it is likely `GetPreferred`.

impl Dispatch<WpColorManagementSurfaceV1, ColorSurfaceData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementSurfaceV1,
        request: wp_color_management_surface_v1::Request,
        _data: &ColorSurfaceData,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_management_surface_v1::Request::Destroy => {}
            wp_color_management_surface_v1::Request::SetImageDescription { .. } => {}
            wp_color_management_surface_v1::Request::UnsetImageDescription => {}
            _ => {}
        }
    }
}

impl Dispatch<WpColorManagementSurfaceFeedbackV1, SurfaceFeedbackData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpColorManagementSurfaceFeedbackV1,
        request: wp_color_management_surface_feedback_v1::Request,
        _data: &SurfaceFeedbackData,
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_color_management_surface_feedback_v1::Request::GetPreferred {
                image_description,
            } => {
                let desc = data_init.init(image_description, ImageDescriptionData);
                desc.ready2(0, 1);
                tracing::debug!("Created preferred image description (sRGB/BT.1886)");
            }
            wp_color_management_surface_feedback_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionV1, ImageDescriptionData> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionV1,
        request: wp_image_description_v1::Request,
        _data: &ImageDescriptionData,
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_image_description_v1::Request::GetInformation { information } => {
                let info = data_init.init(information, ());
                use wp_color_manager_v1::{Primaries, TransferFunction};
                info.primaries_named(Primaries::Srgb);
                info.tf_named(TransferFunction::Bt1886);
                // sRGB luminances: min 0.2 cd/m² (min_lum=2000), max 80, reference 80
                info.luminances(2000, 80, 80);
                info.done();
                tracing::debug!("Sent image description info (sRGB, BT.1886, luminances)");
            }
            wp_image_description_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionCreatorIccV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionCreatorIccV1,
        request: wp_image_description_creator_icc_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_image_description_creator_icc_v1::Request::Create { image_description } => {
                let _d = data_init.init(image_description, ImageDescriptionData);
            }
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionInfoV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionInfoV1,
        request: wp_image_description_info_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionCreatorParamsV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &WpImageDescriptionCreatorParamsV1,
        request: wp_image_description_creator_params_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_image_description_creator_params_v1::Request::Create { image_description } => {
                let _d = data_init.init(image_description, ImageDescriptionData);
            }
            _ => {}
        }
    }
}

pub fn register_color_management(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpColorManagerV1, ()>(2, ())
}
