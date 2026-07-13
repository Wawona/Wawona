//! Modal presentation helper mirroring `WawonaModalSheet` semantics.

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

use crate::linux::ui_model::LayoutMode;

/// Present `content` as a modal sheet: bottom-anchored on compact layouts,
/// centered dialog on expanded layouts.
pub fn present_sheet(
    parent: &impl IsA<gtk::Window>,
    title: &str,
    content: &impl IsA<gtk::Widget>,
    layout: LayoutMode,
) -> adw::Window {
    let dialog = adw::Window::builder()
        .transient_for(parent)
        .modal(true)
        .title(title)
        .build();

    match layout {
        LayoutMode::Compact => {
            dialog.set_default_width(360);
            dialog.set_default_height(520);
            dialog.set_resizable(true);
        }
        LayoutMode::Expanded => {
            dialog.set_default_width(720);
            dialog.set_default_height(640);
            dialog.set_resizable(true);
        }
    }

    dialog.set_content(Some(content));
    dialog.present();
    dialog
}
