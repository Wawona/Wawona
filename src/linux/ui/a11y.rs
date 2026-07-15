//! Stable `wwn.*` accessibility identifiers for the Linux GTK host shell.
//! Keep in sync with Apple `WWNA11y` and Android `WawonaTestTags`.
//!
//! Primary contract: `gtk::Widget::set_widget_name` (exposed to AT-SPI tooling).
//! Accessible labels are also set when the gtk4 Accessible API is available.

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

/// Attach a stable widget name + accessible label for AT-SPI / agent tooling.
pub fn set_wwn_a11y(widget: &impl IsA<gtk::Widget>, id: &str, label: Option<&str>) {
    widget.set_widget_name(id);
    if let Some(label) = label {
        // gtk4 AccessibleProperty::Label (AT-SPI name). Widget name remains the id.
        widget.update_property(&[gtk::accessible::Property::Label(label)]);
    }
}

pub fn settings_section_id(section: &str) -> String {
    let slug = section
        .to_ascii_lowercase()
        .replace(' ', ".")
        .replace('&', "and");
    format!("wwn.settings.{slug}")
}
