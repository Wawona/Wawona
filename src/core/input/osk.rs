//! Native OSK visibility. Host UI kits show the keyboard. Rust decides when.
//!
//! macOS and Linux never request a touch OSK. iOS / Android / watchOS / tvOS
//! / visionOS may, after committed `zwp_text_input_v3.enable` (or terminal
//! synthesis). Uncommitted `enable()` is not enough.

/// Host class for OSK policy. Not a Settings toggle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OskHost {
    /// iOS family + Android. Native UI-kit keyboard.
    TouchOsk,
    /// macOS and Linux GTK. Hardware keyboard / host IME only.
    Never,
}

/// Default host from the rustc target. visionOS uses the iOS target triple.
pub fn default_osk_host() -> OskHost {
    if cfg!(any(target_os = "macos", target_os = "linux")) {
        OskHost::Never
    } else {
        OskHost::TouchOsk
    }
}

/// Whether the native OSK should expand.
///
/// `wanted` is committed TI enable or terminal synthesis (`text_entry_wanted`).
/// `hardware_keyboard` collapses the OSK (iPad Magic Keyboard, Bluetooth).
/// `force` is a manual activate on OSK hosts only (Sxmo / KWin style).
pub fn osk_should_show(
    wanted: bool,
    host: OskHost,
    hardware_keyboard: bool,
    force: bool,
) -> bool {
    match host {
        OskHost::Never => false,
        OskHost::TouchOsk => force || (wanted && !hardware_keyboard),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn macos_never_requests_osk() {
        assert!(!osk_should_show(true, OskHost::Never, false, false));
        assert!(!osk_should_show(true, OskHost::Never, false, true));
    }

    #[test]
    fn uncommitted_wanted_false_hides() {
        assert!(!osk_should_show(false, OskHost::TouchOsk, false, false));
    }

    #[test]
    fn committed_wanted_shows_on_touch() {
        assert!(osk_should_show(true, OskHost::TouchOsk, false, false));
    }

    #[test]
    fn hardware_keyboard_collapses() {
        assert!(!osk_should_show(true, OskHost::TouchOsk, true, false));
        assert!(osk_should_show(true, OskHost::TouchOsk, true, true));
    }

    #[test]
    fn default_host_never_on_macos_linux() {
        if cfg!(any(target_os = "macos", target_os = "linux")) {
            assert_eq!(default_osk_host(), OskHost::Never);
        }
    }
}
