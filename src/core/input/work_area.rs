//! Map native OSK occlusion into compositor usable height.
//!
//! iOS and Android already shrink `wl_output` / the present plate when
//! `resizeDisplayForVirtualKeyboard` is on. This is the Rust policy those
//! hosts share. macOS and Linux never shrink for a Wawona touch OSK.

use super::osk::OskHost;

/// Remaining output height after keyboard overlap.
///
/// `keyboard_overlap` is the host IME occluded height in the same units as
/// `output_height` (pixels or points; caller keeps them consistent).
pub fn usable_output_height(output_height: i32, keyboard_overlap: i32, host: OskHost) -> i32 {
    match host {
        OskHost::Never => output_height,
        OskHost::TouchOsk => (output_height - keyboard_overlap.max(0)).max(1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn macos_never_shrinks() {
        assert_eq!(usable_output_height(800, 300, OskHost::Never), 800);
    }

    #[test]
    fn touch_osk_shrinks() {
        assert_eq!(usable_output_height(800, 300, OskHost::TouchOsk), 500);
    }

    #[test]
    fn zero_overlap_keeps_height() {
        assert_eq!(usable_output_height(800, 0, OskHost::TouchOsk), 800);
    }

    #[test]
    fn default_host_never_shrinks_on_macos_linux() {
        if cfg!(any(target_os = "macos", target_os = "linux")) {
            assert_eq!(
                usable_output_height(800, 300, super::super::osk::default_osk_host()),
                800
            );
        }
    }
}
