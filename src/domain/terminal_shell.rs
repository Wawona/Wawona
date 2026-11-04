//! Terminal shell backend resolver (Mode A Wawona PTY vs system login shell).
//!
//! Canonical matrix: `docs/agent-rules/wawona-terminal-shell-backend.md`.
//! Hosts call [`resolve`]; they must not hardcode `/bin/zsh`.

/// Product target family for shell policy.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalShellTarget {
    MacOs,
    Linux,
    Ios,
    IpadOs,
    TvOs,
    WatchOs,
    VisionOs,
    Android,
}

/// Store (Mode A) vs privileged (Mode B) product flavor.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalShellMode {
    /// App Store / TestFlight / Play / store-shaped.
    ModeA,
    /// TrollStore / Sileo / SIP-off desktop-host / root Android.
    ModeB,
}

/// Which backend Rust should attach for a Terminal tab.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalShellBackend {
    /// Spawn the user's login shell on a real pty (`-l`).
    SystemLoginShell,
    /// Attach in-process `wawona_zsh_main` + `wwn_pty` (no fork/exec).
    WawonaPtyShell,
}

/// Optional hint when Mode B has no bootstrap shell.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerminalShellFallback {
    None,
    /// TrollStore with no jailbreak bootstrap: use Wawona PTY.
    WawonaPtyWhenNoBootstrap,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TerminalShellPlan {
    pub backend: TerminalShellBackend,
    pub fallback: TerminalShellFallback,
}

/// Resolve shell backend for `(target, mode)`.
///
/// macOS and Linux always use the system login shell (Mode A or B).
/// Apple-mobile / Android Mode A use Wawona PTY. Mode B uses system shell
/// with an optional Wawona PTY fallback when no bootstrap exists.
pub fn resolve(target: TerminalShellTarget, mode: TerminalShellMode) -> TerminalShellPlan {
    match (target, mode) {
        (TerminalShellTarget::MacOs | TerminalShellTarget::Linux, _) => TerminalShellPlan {
            backend: TerminalShellBackend::SystemLoginShell,
            fallback: TerminalShellFallback::None,
        },
        (
            TerminalShellTarget::Ios
            | TerminalShellTarget::IpadOs
            | TerminalShellTarget::TvOs
            | TerminalShellTarget::WatchOs
            | TerminalShellTarget::VisionOs
            | TerminalShellTarget::Android,
            TerminalShellMode::ModeA,
        ) => TerminalShellPlan {
            backend: TerminalShellBackend::WawonaPtyShell,
            fallback: TerminalShellFallback::None,
        },
        (
            TerminalShellTarget::Ios | TerminalShellTarget::IpadOs | TerminalShellTarget::Android,
            TerminalShellMode::ModeB,
        ) => TerminalShellPlan {
            backend: TerminalShellBackend::SystemLoginShell,
            fallback: TerminalShellFallback::WawonaPtyWhenNoBootstrap,
        },
        // tvOS / watchOS / visionOS have no Mode B product shell path yet.
        (
            TerminalShellTarget::TvOs
            | TerminalShellTarget::WatchOs
            | TerminalShellTarget::VisionOs,
            TerminalShellMode::ModeB,
        ) => TerminalShellPlan {
            backend: TerminalShellBackend::WawonaPtyShell,
            fallback: TerminalShellFallback::None,
        },
    }
}

/// Default argv[0] hint for [`TerminalShellBackend::SystemLoginShell`] on macOS
/// when `getpwuid` is unavailable. Prefer the login shell from passwd.
pub fn macos_system_shell_fallback_path() -> &'static str {
    "/bin/zsh"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn macos_always_system() {
        let a = resolve(TerminalShellTarget::MacOs, TerminalShellMode::ModeA);
        let b = resolve(TerminalShellTarget::MacOs, TerminalShellMode::ModeB);
        assert_eq!(a.backend, TerminalShellBackend::SystemLoginShell);
        assert_eq!(b.backend, TerminalShellBackend::SystemLoginShell);
    }

    #[test]
    fn ios_mode_a_is_wawona_pty() {
        let p = resolve(TerminalShellTarget::Ios, TerminalShellMode::ModeA);
        assert_eq!(p.backend, TerminalShellBackend::WawonaPtyShell);
    }

    #[test]
    fn ios_mode_b_is_system_with_fallback() {
        let p = resolve(TerminalShellTarget::Ios, TerminalShellMode::ModeB);
        assert_eq!(p.backend, TerminalShellBackend::SystemLoginShell);
        assert_eq!(p.fallback, TerminalShellFallback::WawonaPtyWhenNoBootstrap);
    }

    #[test]
    fn android_play_is_wawona_pty() {
        let p = resolve(TerminalShellTarget::Android, TerminalShellMode::ModeA);
        assert_eq!(p.backend, TerminalShellBackend::WawonaPtyShell);
    }
}
