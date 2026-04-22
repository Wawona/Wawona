pub mod plasma;
pub mod kde_decoration;

use wayland_server::DisplayHandle;
use crate::core::state::CompositorState;
use crate::core::wayland::policy;

/// Register KDE/Plasma protocols
pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {
    if !policy::allow_plasma_extensions(state.protocol_profile) {
        crate::wlog!(
            crate::util::logging::COMPOSITOR,
            "Skipping Plasma globals for profile {}",
            state.protocol_profile.as_str()
        );
        return;
    }

    use crate::core::wayland::plasma::kde_decoration::KdeDecorationManagerGlobal;
    use crate::core::wayland::plasma::plasma::{BlurManagerGlobal, ContrastManagerGlobal, ShadowManagerGlobal};
    use crate::core::wayland::protocol::server::org_kde_kwin_server_decoration::org_kde_kwin_server_decoration_manager::OrgKdeKwinServerDecorationManager;
    use crate::core::wayland::protocol::server::plasma::{
        blur::server::org_kde_kwin_blur_manager::OrgKdeKwinBlurManager,
        contrast::server::org_kde_kwin_contrast_manager::OrgKdeKwinContrastManager,
        shadow::server::org_kde_kwin_shadow_manager::OrgKdeKwinShadowManager,
        dpms::server::org_kde_kwin_dpms_manager::OrgKdeKwinDpmsManager,
        idle::server::org_kde_kwin_idle_timeout::OrgKdeKwinIdleTimeout,
        slide::server::org_kde_kwin_slide_manager::OrgKdeKwinSlideManager,
    };

    dh.create_global::<CompositorState, OrgKdeKwinServerDecorationManager, KdeDecorationManagerGlobal>(1, KdeDecorationManagerGlobal);
    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered org_kde_kwin_server_decoration_manager (KDE fallback)");
    
    dh.create_global::<CompositorState, OrgKdeKwinBlurManager, BlurManagerGlobal>(1, BlurManagerGlobal);
    dh.create_global::<CompositorState, OrgKdeKwinContrastManager, ContrastManagerGlobal>(1, ContrastManagerGlobal);
    dh.create_global::<CompositorState, OrgKdeKwinShadowManager, ShadowManagerGlobal>(1, ShadowManagerGlobal);
    dh.create_global::<CompositorState, OrgKdeKwinDpmsManager, _>(1, ());
    dh.create_global::<CompositorState, OrgKdeKwinIdleTimeout, _>(1, ());
    dh.create_global::<CompositorState, OrgKdeKwinSlideManager, _>(1, ());

    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered KDE/Plasma globals (blur, contrast, shadow, dpms, idle, slide)");
}
