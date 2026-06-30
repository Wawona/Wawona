//! Session-exit preference resolution (mirrors Android `SessionExitSettings`).
//!
//! Global defaults live in `LinuxSettings`; per-machine overrides come from
//! `MachineRuntimeOverrides` on the canonical profile.

use crate::linux::config::LinuxSettings;
use crate::linux::machine_profile::{MachineProfile, MachineRuntimeOverrides};

/// Resolved shake-to-close preference for a session.
pub fn shake_to_close_enabled(_settings: &LinuxSettings, profile: Option<&MachineProfile>) -> bool {
    profile
        .and_then(|p| p.runtime_overrides.shake_to_close_enabled)
        .unwrap_or(true)
}

/// Resolved swipe-back-to-close preference for a session.
pub fn swipe_back_to_close_enabled(
    settings: &LinuxSettings,
    profile: Option<&MachineProfile>,
) -> bool {
    let _ = settings;
    profile
        .and_then(|p| p.runtime_overrides.swipe_back_to_close_enabled)
        .unwrap_or(true)
}

/// Whether machine thumbnails should be captured/shown for this profile.
pub fn thumbnails_enabled(_settings: &LinuxSettings, profile: Option<&MachineProfile>) -> bool {
    // Linux does not yet persist a global thumbnail toggle; default on unless
    // a per-machine override disables it via runtime overrides in the future.
    profile.is_some()
}

/// Apply session-exit toggles from editor widgets into runtime overrides.
pub fn write_session_exit_overrides(
    overrides: &mut MachineRuntimeOverrides,
    shake: bool,
    swipe_back: bool,
) {
    overrides.shake_to_close_enabled = Some(shake);
    overrides.swipe_back_to_close_enabled = Some(swipe_back);
}
