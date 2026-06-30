//! GTK4/libadwaita shell for the Linux Wawona launcher UI.

mod adaptive;
mod editor;
mod home;
mod modal_sheet;
mod settings;

pub use adaptive::{clamp_content, install_breakpoint, LayoutBinding};
pub use editor::show_editor;
pub use home::{build_home_shell, rebuild_home, HomeShell, MachineSessions, RebuildHome};
pub use modal_sheet::present_sheet;
pub use settings::show_settings;

use std::cell::RefCell;
use std::rc::Rc;

use crate::linux::config::LinuxSettings;
use crate::linux::profile_store::ProfileStore;

/// Combined canonical profile store + Linux-only app settings.
#[derive(Debug, Clone)]
pub struct AppState {
    pub store: ProfileStore,
    pub settings: LinuxSettings,
}

impl AppState {
    pub fn load() -> Self {
        let store = ProfileStore::load().unwrap_or_default();
        let settings = crate::linux::config::load_or_default()
            .map(|c| c.settings)
            .unwrap_or_default();
        Self { store, settings }
    }

    pub fn persist_settings(&self) {
        let mut cfg = crate::linux::config::load_or_default().unwrap_or_default();
        cfg.settings = self.settings.clone();
        let _ = crate::linux::config::save(&cfg);
    }
}

pub type SharedAppState = Rc<RefCell<AppState>>;
