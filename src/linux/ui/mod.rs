//! GTK4/libadwaita shell for the Linux Wawona launcher UI.

pub mod a11y;
mod adaptive;
pub mod editor;
pub mod env_vars;
mod home;
pub mod modal_sheet;
mod settings;
mod tab_overview;
mod terminal;
pub mod work_status;

pub use adaptive::{
    bind_content_sidebar_toggle, clamp_content, ensure_adaptive_css, install_adaptive_split_view,
    install_breakpoint, is_touchscreen_active, make_resizable_sidebar, scrollable_sidebar,
    sidebar_column_with_toggle, LayoutBinding,
};
pub use editor::{build_editor_view, show_editor};
pub use env_vars::build_env_vars_view;
pub use home::{
    build_home_shell, color_dot, maybe_show_welcome, rebuild_home, show_edit_tag_dialog,
    show_new_tag_dialog, HomeShell, MachineSessions, RebuildHome,
};
pub use modal_sheet::present_sheet;
pub use settings::{build_settings_view, ensure_settings_css, show_settings};
pub use tab_overview::{build_tab_overview_view, show_tab_overview};
pub use terminal::{
    build_terminal_view, launch_subtitle, open_launched, open_shell, shell_command, start_shell,
    start_terminal, terminal_launch, TerminalLaunch,
};
pub use work_status::build_work_status_view;

use std::cell::RefCell;
use std::rc::Rc;

use crate::linux::config::LinuxSettings;
use crate::linux::profile_store::ProfileStore;
use crate::linux::tag_store::TagStore;

/// Combined canonical profile store, tags store, and Linux-only app settings.
#[derive(Debug, Clone)]
pub struct AppState {
    pub store: ProfileStore,
    pub settings: LinuxSettings,
    pub tags: TagStore,
}

impl AppState {
    pub fn load() -> Self {
        let store = ProfileStore::load().unwrap_or_default();
        let settings = crate::linux::config::load_or_default()
            .map(|c| c.settings)
            .unwrap_or_default();
        let tags = TagStore::load();
        Self { store, settings, tags }
    }

    pub fn persist_settings(&self) {
        let mut cfg = crate::linux::config::load_or_default().unwrap_or_default();
        cfg.settings = self.settings.clone();
        let _ = crate::linux::config::save(&cfg);
    }

    pub fn persist_tags(&self) {
        let _ = self.tags.save();
    }
}

pub type SharedAppState = Rc<RefCell<AppState>>;
