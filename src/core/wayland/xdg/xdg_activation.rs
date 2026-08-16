//! XDG Activation. Dispatch owned by Smithay `delegate_xdg_activation!`.

use std::collections::HashMap;

#[derive(Debug, Clone, Default)]
pub struct ActivationTokenData {
    pub token: String,
    pub app_id: Option<String>,
    pub serial: Option<u32>,
    pub surface_id: Option<u32>,
}

#[derive(Debug, Default)]
pub struct ActivationState {
    pub tokens: HashMap<(wayland_server::backend::ClientId, u32), ActivationTokenData>,
}
