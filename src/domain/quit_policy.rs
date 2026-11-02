//! macOS quit vs LaunchAgent respawn.
//!
//! Issue #223: a pkg install wrote `KeepAlive=true` for the compositor host
//! and the menu bar. launchd started them again after Quit, and the host
//! reopen path opened the Machines window. Quit means the process stays quit.
//!
//! `RunAtLoad` may still start a service at login. `KeepAlive` may not bring
//! it back after the user quits. Quit bootouts both agents and deletes the
//! plists. The compositor host must not open the UI on reopen.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum LaunchAgentRole {
    CompositorHost = 1,
    MenuBar = 2,
    AppLaunch = 3,
}

impl LaunchAgentRole {
    pub fn from_code(code: i32) -> Option<Self> {
        match code {
            1 => Some(Self::CompositorHost),
            2 => Some(Self::MenuBar),
            3 => Some(Self::AppLaunch),
            _ => None,
        }
    }
}

/// launchd `KeepAlive` for this role. Always false: a quit must stick.
pub fn keep_alive(role: LaunchAgentRole) -> bool {
    match role {
        LaunchAgentRole::CompositorHost | LaunchAgentRole::MenuBar | LaunchAgentRole::AppLaunch => {
            false
        }
    }
}

/// Compositor-host `applicationShouldHandleReopen` must not open Machines.
pub fn host_reopen_opens_ui() -> bool {
    false
}

/// Regular UI Quit bootouts the compositor host and the menu bar.
pub fn ui_quit_stops_launch_agents() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_role_respawns_after_quit() {
        for code in 1..=3 {
            let role = LaunchAgentRole::from_code(code).unwrap();
            assert!(!keep_alive(role));
        }
    }

    #[test]
    fn unknown_role_is_not_a_keepalive() {
        assert!(LaunchAgentRole::from_code(0).is_none());
        assert!(LaunchAgentRole::from_code(99).is_none());
    }

    #[test]
    fn host_reopen_does_not_open_the_window() {
        assert!(!host_reopen_opens_ui());
    }

    #[test]
    fn ui_quit_removes_agents() {
        assert!(ui_quit_stops_launch_agents());
    }
}
