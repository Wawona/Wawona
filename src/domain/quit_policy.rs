//! macOS LaunchAgent vs the Machines window.
//!
//! Issue #223: the compositor host is a LaunchAgent so the Wayland socket
//! stays up when Wawona.app is closed. `KeepAlive` restarts that host if it
//! dies. It must not start the Machines GUI.
//!
//! The host's reopen handler used to call `NSWorkspace.openApplication` on
//! Wawona.app. Launch Services delivered that open back to the same bundle,
//! which reopened, which opened the app again. The window kept coming back.
//!
//! The optional login agent starts the GUI executable with `KeepAlive` false.
//! It does not use `/usr/bin/open`. That tool exits immediately, so KeepAlive
//! would open Wawona.app again on every restart.

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

/// launchd `KeepAlive` for this role.
///
/// The compositor host and the menu bar stay up so Wayland clients can
/// connect without the Machines window. The login `open` job must not
/// respawn.
pub fn keep_alive(role: LaunchAgentRole) -> bool {
    match role {
        LaunchAgentRole::CompositorHost | LaunchAgentRole::MenuBar => true,
        LaunchAgentRole::AppLaunch => false,
    }
}

/// Compositor-host `applicationShouldHandleReopen` must not open Machines.
pub fn host_reopen_opens_ui() -> bool {
    false
}

/// Quitting the Machines window leaves the compositor host running.
pub fn ui_quit_stops_compositor() -> bool {
    false
}

/// True when a peer accepts a connect on this Unix socket path.
///
/// The Machines UI and the compositor-host LaunchAgent share one runtime
/// dir. Binding must never `unlink` a live host socket: that orphans the
/// host listen fd and waypipe/SSH clients get `ENOENT` (#223).
pub fn wayland_socket_is_live(path: &std::path::Path) -> bool {
    std::os::unix::net::UnixStream::connect(path).is_ok()
}

/// Whether `bind_primary` may remove an existing socket path before bind.
///
/// Stale paths (inode present, connect fails) may be removed. A live peer
/// must be left alone.
pub fn may_unlink_wayland_socket(path: &std::path::Path) -> bool {
    if !path.exists() {
        return false;
    }
    !wayland_socket_is_live(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::net::UnixListener;

    #[test]
    fn socket_agents_stay_up_and_login_open_does_not() {
        assert!(keep_alive(LaunchAgentRole::CompositorHost));
        assert!(keep_alive(LaunchAgentRole::MenuBar));
        assert!(!keep_alive(LaunchAgentRole::AppLaunch));
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
    fn quitting_the_window_leaves_the_socket() {
        assert!(!ui_quit_stops_compositor());
    }

    #[test]
    fn live_socket_must_not_be_unlinked() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("wayland-0");
        let _listener = UnixListener::bind(&path).expect("bind");
        assert!(wayland_socket_is_live(&path));
        assert!(!may_unlink_wayland_socket(&path));
    }

    #[test]
    fn stale_socket_path_may_be_unlinked() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("wayland-0");
        {
            let mut f = std::fs::File::create(&path).expect("create");
            f.write_all(b"not-a-socket").ok();
        }
        assert!(!wayland_socket_is_live(&path));
        assert!(may_unlink_wayland_socket(&path));
    }

    #[test]
    fn missing_path_is_not_unlink_target() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("wayland-missing");
        assert!(!may_unlink_wayland_socket(&path));
    }
}
