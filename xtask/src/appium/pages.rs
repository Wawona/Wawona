//! Wawona's host UI by wwn.* accessibility id: Machines, Settings, the
//! Wawona Terminal and the compositor surface.

use std::path::Path;
use std::thread::sleep;
use std::time::Duration;

use anyhow::{ensure, Result};
use serde_json::json;

use super::webdriver::Driver;

pub const ROOT: &str = "wwn.machines.root";
pub const ADD: &str = "wwn.machines.add";
pub const START: &str = "wwn.machines.start";
pub const START_TAB: &str = "wwn.machines.start.tab";
pub const START_WINDOW: &str = "wwn.machines.start.window";
pub const FOCUS: &str = "wwn.machines.focus";
pub const EDIT: &str = "wwn.machines.edit";
pub const SEARCH: &str = "wwn.machines.search";
pub const PIN: &str = "wwn.machines.pin";
pub const SIDEBAR: &str = "wwn.machines.sidebar";
pub const OVERVIEW: &str = "wwn.machines.overview";
pub const OVERVIEW_FOCUS: &str = "wwn.machines.overview.focus";
pub const OVERVIEW_TERMINATE: &str = "wwn.machines.overview.terminate";
pub const OVERVIEW_ADD: &str = "wwn.machines.overview.add";
pub const TAG_CREATE: &str = "wwn.machines.tag.create";
pub const IMPORT_FILE: &str = "wwn.machines.import.file";
pub const EDITOR: &str = "wwn.machines.editor";
pub const EDITOR_SAVE: &str = "wwn.machines.editor.save";
pub const EDITOR_NAME: &str = "wwn.machines.editor.name";
pub const EDITOR_WASM: &str = "wwn.machines.editor.wasm.command";
pub const TYPE_VM: &str = "wwn.machines.editor.type.virtual_machine";
pub const TYPE_CONTAINER: &str = "wwn.machines.editor.type.container";
pub const SETTINGS: &str = "wwn.machines.settings";
pub const SETTINGS_ROOT: &str = "wwn.settings.root";
pub const SETTINGS_DONE: &str = "wwn.settings.done";
pub const SETTINGS_SECTIONS: [&str; 5] =
    ["wwn.settings.display", "wwn.settings.input", "wwn.settings.ssh", "wwn.settings.waypipe", GRAPHICS];
pub const GRAPHICS: &str = "wwn.settings.graphics";
pub const APPLE_WATCH: &str = "wwn.settings.appleWatch";
pub const TERMINAL: &str = "wwn.terminal.root";
pub const SURFACE: &str = "wwn.compositor.surface";
pub const TOOLBAR: &str = "wwn.toolbar.root";
pub const TOOLBAR_CUSTOMIZE: &str = "wwn.toolbar.customize";
pub const KEYBOARD_DISMISS: &str = "wwn.keyboard.dismiss";

pub struct Ui {
    pub d: Driver,
    pub platform: String,
}

pub fn pause(ms: u64) {
    sleep(Duration::from_millis(ms));
}

impl Ui {
    pub fn exists(&self, id: &str) -> Result<bool> {
        self.d.exists(id)
    }

    pub fn tap(&self, id: &str) -> Result<()> {
        let e = self.d.wait_visible(id, None)?;
        self.d.click(&e)
    }

    pub fn tap_if(&self, id: &str) -> Result<bool> {
        let there = self.exists(id)?;
        if there {
            self.tap(id)?;
        }
        Ok(there)
    }

    pub fn type_into(&self, id: &str, text: &str) -> Result<()> {
        let e = self.d.wait_visible(id, None)?;
        self.d.click(&e)?;
        let _ = self.d.clear(&e);
        self.d.send_keys(&e, text)
    }

    pub fn assert_absent(&self, id: &str) -> Result<()> {
        ensure!(!self.exists(id)?, "{id} is present but its gate forbids it");
        Ok(())
    }

    pub fn screenshot(&self, path: &Path) -> Result<()> {
        crate::util::write(path, self.d.screenshot()?)
    }

    /// Bring Wawona forward on its Machines root. A cold Mac2 attach can land
    /// on Settings or Present; Global Settings replaces the Machines chrome.
    pub fn open_root(&self) -> Result<()> {
        if self.platform == "macos" {
            let _ = self.d.execute(
                "macos: activateApp",
                json!({ "bundleId": crate::util::env_or("WAWONA_BUNDLE_ID", "com.aspauldingcode.Wawona") }),
            );
            pause(500);
        }
        if self.tap_if("wwn.welcome.continue")? {
            pause(500);
        }
        if !self.exists(ROOT)? && self.exists(SETTINGS)? {
            let _ = self.d.execute("macos: keys", json!({ "keys": [{ "key": "XCUIKeyboardKeyEscape" }] }));
            pause(500);
        }
        self.d.wait_visible(ROOT, None).map(drop)
    }

    /// `kind`: native, virtual_machine or container.
    pub fn add_machine(&self, name: &str, kind: &str) -> Result<()> {
        self.tap(ADD)?;
        self.d.wait_visible(EDITOR, None)?;
        let type_id = format!("wwn.machines.editor.type.{kind}");
        if !self.tap_if(&type_id)? {
            self.tap_if("wwn.machines.editor.type")?;
        }
        if self.exists(EDITOR_NAME)? {
            self.type_into(EDITOR_NAME, name)?;
        }
        self.tap(EDITOR_SAVE)?;
        pause(500);
        Ok(())
    }

    fn tap_displayed(&self, using: &str, value: &str) -> bool {
        for e in self.d.find_all(using, value).unwrap_or_default() {
            if self.d.displayed(&e).unwrap_or(false) && self.d.click(&e).is_ok() {
                return true;
            }
        }
        false
    }

    /// `placement`: tab or window. Toolbar Start needs a selected card, so
    /// on-card Start controls come first, keep-set profiles before others.
    pub fn start(&self, placement: &str) -> Result<()> {
        let explicit = if placement == "window" { START_WINDOW } else { START_TAB };
        if self.tap_if(explicit)? || self.tap_displayed("accessibility id", START) {
            return Ok(());
        }
        for label in ["Start Weston Terminal. Weston Terminal", "Start Native Shell Terminal thing?. Wawona Terminal"] {
            if self.tap_displayed("name", label) {
                return Ok(());
            }
        }
        if let Ok(card) = self.d.find("accessibility id", "wwn.machines.card.1") {
            self.d.click(&card)?;
            pause(300);
        }
        self.tap(START)
    }

    pub fn open_settings(&self) -> Result<()> {
        self.tap(SETTINGS)?;
        self.d.wait_visible(SETTINGS_ROOT, None).map(drop)
    }

    pub fn run_in_terminal(&self, command: &str) -> Result<()> {
        let e = self.d.wait_visible(TERMINAL, None)?;
        let typed = self.d.click(&e).and_then(|_| self.d.send_keys(&e, &format!("{command}\n")));
        if typed.is_err() {
            self.d.send_keys(&self.d.active()?, &format!("{command}\n"))?;
        }
        pause(800);
        Ok(())
    }

    pub fn surface_rect(&self) -> Result<[i64; 4]> {
        let e = self.d.wait_visible(SURFACE, None)?;
        self.d.rect(&e)
    }

    /// The compositor surface element, not the desktop. SwiftUI once exposed
    /// a 1x1 accessibility wrapper, so a tiny element shot falls back to the
    /// app screenshot.
    pub fn screenshot_surface(&self, path: &Path) -> Result<()> {
        let e = self.d.wait_visible(SURFACE, None)?;
        let [_, _, w, h] = self.d.rect(&e)?;
        if w >= 32 && h >= 32 {
            if let Ok(png) = self.d.element_screenshot(&e) {
                if png.len() >= 12_000 {
                    return crate::util::write(path, png);
                }
            }
        }
        self.screenshot(path)
    }

    pub fn assert_resized(&self, before: [i64; 4]) -> Result<()> {
        pause(1000);
        let after = self.surface_rect()?;
        let moved = (after[2] - before[2]).abs() >= 8 || (after[3] - before[3]).abs() >= 8;
        ensure!(moved, "surface did not resize: before {before:?} after {after:?}");
        Ok(())
    }

    pub fn dismiss_keyboard(&self) -> Result<()> {
        if !self.tap_if(KEYBOARD_DISMISS)? {
            let _ = self.d.hide_keyboard();
        }
        Ok(())
    }

    /// On macOS, Start presents the Wawona Terminal window; closing it shows
    /// the session surface.
    pub fn close_terminal_windows(&self) {
        let xpath = "//XCUIElementTypeWindow[contains(@title,'Terminal')]/XCUIElementTypeButton[@identifier='_XCUI:CloseWindow']";
        for b in self.d.find_all("xpath", xpath).unwrap_or_default() {
            let _ = self.d.click(&b);
        }
        pause(1500);
    }
}
