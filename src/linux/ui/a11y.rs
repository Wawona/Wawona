//! Stable `wwn.*` accessibility identifiers for the Linux GTK host shell.
//! Keep in sync with Apple `WWNA11y` and Android `WawonaTestTags`.
//!
//! Contract: `gtk::Widget::set_widget_name` (AT-SPI / inspector) plus tooltip
//! or visible label text for human-facing names.

use gtk4 as gtk;
use gtk::prelude::*;

pub mod id {
    pub const MACHINES_ROOT: &str = "wwn.machines.root";
    pub const MACHINES_SETTINGS: &str = "wwn.machines.settings";
    pub const MACHINES_ADD: &str = "wwn.machines.add";
    pub const MACHINES_START: &str = "wwn.machines.start";
    pub const MACHINES_STOP: &str = "wwn.machines.stop";
    pub const MACHINES_FOCUS: &str = "wwn.machines.focus";
    pub const MACHINES_EDIT: &str = "wwn.machines.edit";
    pub const MACHINES_DELETE: &str = "wwn.machines.delete";

    pub const SETTINGS_ROOT: &str = "wwn.settings.root";
    pub const SETTINGS_DONE: &str = "wwn.settings.done";
    pub const SETTINGS_DISPLAY: &str = "wwn.settings.display";

    pub const COMPOSITOR_SURFACE: &str = "wwn.compositor.surface";
}

/// Attach a stable widget name for AT-SPI / agent tooling.
pub fn set_wwn_a11y(widget: &impl IsA<gtk::Widget>, id: &str, label: Option<&str>) {
    widget.set_widget_name(id);
    if let Some(label) = label {
        // Prefer tooltip so icon-only controls stay discoverable without
        // overriding a more specific accessible name set by GTK.
        if widget.tooltip_text().is_none() {
            widget.set_tooltip_text(Some(label));
        }
    }
}

pub fn settings_section_id(section: &str) -> String {
    let slug = section
        .to_ascii_lowercase()
        .replace(' ', ".")
        .replace('&', "and");
    format!("wwn.settings.{slug}")
}
