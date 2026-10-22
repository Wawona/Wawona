//! Stable `wwn.*` accessibility identifiers for the Linux GTK host shell.
//! Keep in sync with Apple `WWNA11y` and Android `WawonaTestTags`.
//!
//! Contract: `gtk::Widget::set_widget_name` (AT-SPI / inspector) plus tooltip
//! or visible label text for human-facing names.

use gtk::prelude::*;
use gtk4 as gtk;

pub mod id {
    pub const WELCOME_ROOT: &str = "wwn.welcome.root";
    pub const WELCOME_CONTINUE: &str = "wwn.welcome.continue";

    pub const MACHINES_ROOT: &str = "wwn.machines.root";
    pub const MACHINES_SETTINGS: &str = "wwn.machines.settings";
    pub const MACHINES_ADD: &str = "wwn.machines.add";
    pub const MACHINES_START: &str = "wwn.machines.start";
    pub const MACHINES_START_TAB: &str = "wwn.machines.start.tab";
    pub const MACHINES_START_WINDOW: &str = "wwn.machines.start.window";
    pub const MACHINES_STOP: &str = "wwn.machines.stop";
    pub const MACHINES_FOCUS: &str = "wwn.machines.focus";
    pub const MACHINES_EDIT: &str = "wwn.machines.edit";
    pub const MACHINES_DELETE: &str = "wwn.machines.delete";
    pub const MACHINES_SEARCH: &str = "wwn.machines.search";
    pub const MACHINES_PIN: &str = "wwn.machines.pin";
    pub const MACHINES_SIDEBAR: &str = "wwn.machines.sidebar";
    pub const MACHINES_SIDEBAR_RESIZER: &str = "wwn.machines.sidebar.resizer";
    pub const MACHINES_OVERVIEW: &str = "wwn.machines.overview";
    pub const MACHINES_OVERVIEW_FOCUS: &str = "wwn.machines.overview.focus";
    pub const MACHINES_OVERVIEW_TERMINATE: &str = "wwn.machines.overview.terminate";
    pub const MACHINES_OVERVIEW_ADD: &str = "wwn.machines.overview.add";
    pub const MACHINES_TAG_CREATE: &str = "wwn.machines.tag.create";
    pub const MACHINES_TAG_NAME: &str = "wwn.machines.tag.name";
    pub const MACHINES_TAG_COLOR: &str = "wwn.machines.tag.color";
    pub const MACHINES_TAG_FILTER: &str = "wwn.machines.tag.filter";
    pub const MACHINES_IMPORT_FILE: &str = "wwn.machines.import.file";
    pub const MACHINES_EDITOR: &str = "wwn.machines.editor";
    pub const MACHINES_EDITOR_SAVE: &str = "wwn.machines.editor.save";
    pub const MACHINES_EDITOR_CANCEL: &str = "wwn.machines.editor.cancel";
    pub const MACHINES_EDITOR_NAME: &str = "wwn.machines.editor.name";
    pub const MACHINES_EDITOR_TYPE: &str = "wwn.machines.editor.type";
    pub const MACHINES_EDITOR_TYPE_NATIVE: &str = "wwn.machines.editor.type.native";
    pub const MACHINES_EDITOR_TYPE_VM: &str = "wwn.machines.editor.type.virtual_machine";
    pub const MACHINES_EDITOR_TYPE_CONTAINER: &str = "wwn.machines.editor.type.container";

    pub const SETTINGS_ROOT: &str = "wwn.settings.root";
    pub const SETTINGS_DONE: &str = "wwn.settings.done";
    pub const SETTINGS_DISPLAY: &str = "wwn.settings.display";
    pub const SETTINGS_INPUT: &str = "wwn.settings.input";
    pub const SETTINGS_GRAPHICS: &str = "wwn.settings.graphics";
    pub const SETTINGS_SSH: &str = "wwn.settings.ssh";
    pub const SETTINGS_WAYPIPE: &str = "wwn.settings.waypipe";
    pub const SETTINGS_ENVIRONMENT: &str = "wwn.settings.environment";
    pub const SETTINGS_COPY_LOGS: &str = "wwn.settings.copyRecentLogs";
    pub const SETTINGS_REPORT_BUG: &str = "wwn.settings.reportBug";

    pub const COMPOSITOR_SURFACE: &str = "wwn.compositor.surface";
    pub const CLIENT_TABS: &str = "wwn.client.tabs";
    pub const TERMINAL_ROOT: &str = "wwn.terminal.root";
    pub const TERMINAL_DONE: &str = "wwn.terminal.done";
    pub const TOOLBAR_ROOT: &str = "wwn.toolbar.root";
    pub const TOOLBAR_CUSTOMIZE: &str = "wwn.toolbar.customize";
    pub const KEYBOARD_DISMISS: &str = "wwn.keyboard.dismiss";
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
