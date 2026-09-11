//! `zwp_primary_selection_device_manager_v1` is owned by Smithay
//! (`delegate_primary_selection!`) on desktop / privileged-wlr profiles.
//! Do not `create_global` that interface here.

/// Leftover bookkeeping type. Smithay owns the protocol now.
#[derive(Debug, Default, Clone)]
pub struct PrimarySelectionState {}

/// Smithay registers the global from `register_core_shell`.
pub fn register_primary_selection(
    _display: &wayland_server::DisplayHandle,
) -> Option<wayland_server::backend::GlobalId> {
    None
}
