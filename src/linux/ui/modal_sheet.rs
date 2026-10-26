//! Modal presentation helper mirroring Apple/Android Settings cover motion.
//!
//! Uses `adw::Dialog` with `BottomSheet` so Settings (and machine editors)
//! slide up from the bottom on every Linux layout, matching the in-window
//! cover on Apple and `AnimatedVisibility` slide on Android.

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::ui_model::LayoutMode;

/// Present `content` as a bottom-sheet dialog (slide up from bottom).
pub fn present_sheet(
    parent: &impl IsA<gtk::Window>,
    title: &str,
    content: &impl IsA<gtk::Widget>,
    layout: LayoutMode,
) -> adw::Dialog {
    let dialog = adw::Dialog::new();
    dialog.set_title(title);
    dialog.set_child(Some(content));
    dialog.set_presentation_mode(adw::DialogPresentationMode::BottomSheet);

    match layout {
        LayoutMode::Compact => {
            dialog.set_content_width(360);
            dialog.set_content_height(520);
        }
        LayoutMode::Expanded => {
            dialog.set_content_width(720);
            dialog.set_content_height(640);
        }
    }

    dialog.present(Some(parent));
    dialog
}
