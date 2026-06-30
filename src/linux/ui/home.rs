//! Machines home: card grid, search, scope segmented control.

use std::cell::RefCell;
use std::collections::HashMap;
use std::process::Child;
use std::rc::Rc;

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

use crate::linux::launcher;
use crate::linux::machine_profile::MachineProfile;
use crate::linux::runtime;
use crate::linux::thumbnail_store;
use crate::linux::ui::{editor, SharedAppState};
use crate::linux::ui_model::{empty_state_text, visible_machines, LayoutMode, MachineScope};
use crate::wlog;

pub type MachineSessions = Rc<RefCell<HashMap<String, Child>>>;

pub struct HomeShell {
    pub root: gtk::Box,
    pub search: gtk::SearchEntry,
    pub flow: gtk::FlowBox,
    pub scope: Rc<RefCell<MachineScope>>,
    pub query: Rc<RefCell<String>>,
}

pub struct RebuildHome<'a> {
    pub shell: &'a HomeShell,
    pub state: &'a SharedAppState,
    pub parent: &'a adw::ApplicationWindow,
    pub sessions: MachineSessions,
    pub layout: LayoutMode,
}

pub fn build_scope_row(scope: Rc<RefCell<MachineScope>>, on_change: Rc<dyn Fn()>) -> gtk::Box {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    row.set_halign(gtk::Align::Center);
    row.set_margin_top(8);
    row.set_margin_bottom(4);
    row.add_css_class("linked");

    for filter in MachineScope::all() {
        let btn = gtk::ToggleButton::with_label(filter.title());
        btn.set_hexpand(true);
        btn.set_active(*scope.borrow() == *filter);
        let scope_c = scope.clone();
        let on_change_c = on_change.clone();
        let filter = *filter;
        btn.connect_toggled(move |b| {
            if b.is_active() {
                *scope_c.borrow_mut() = filter;
                on_change_c();
            }
        });
        row.append(&btn);
    }
    row
}

pub fn build_home_shell(on_rebuild: Rc<dyn Fn()>) -> HomeShell {
    let search = gtk::SearchEntry::builder()
        .placeholder_text("Search machines")
        .hexpand(true)
        .build();

    let flow = gtk::FlowBox::new();
    flow.set_selection_mode(gtk::SelectionMode::None);
    flow.set_homogeneous(true);
    flow.set_max_children_per_line(3);
    flow.set_min_children_per_line(1);
    flow.set_column_spacing(12);
    flow.set_row_spacing(12);
    flow.set_margin_start(12);
    flow.set_margin_end(12);
    flow.set_margin_bottom(12);

    let scope = Rc::new(RefCell::new(MachineScope::All));
    let query = Rc::new(RefCell::new(String::new()));

    let scope_row = build_scope_row(scope.clone(), on_rebuild.clone());
    let on_rebuild_search = on_rebuild.clone();
    let query_search = query.clone();
    search.connect_search_changed(move |entry| {
        *query_search.borrow_mut() = entry.text().to_string();
        on_rebuild_search();
    });

    let scroll = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vexpand(true)
        .child(&flow)
        .build();

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&scope_row);
    root.append(&scroll);

    HomeShell {
        root,
        search,
        flow,
        scope,
        query,
    }
}

pub fn rebuild_home(ctx: RebuildHome<'_>) {
    while let Some(child) = ctx.shell.flow.first_child() {
        ctx.shell.flow.remove(&child);
    }

    prune_dead_sessions(&ctx.sessions);

    let app = ctx.state.borrow();
    let scope = *ctx.shell.scope.borrow();
    let query = ctx.shell.query.borrow().clone();
    let active_id = app.store.active_machine_id.clone();
    let visible: Vec<MachineProfile> = visible_machines(&app.store.profiles, &query, scope)
        .into_iter()
        .cloned()
        .collect();
    let has_any = !app.store.profiles.is_empty();
    let has_query = !query.trim().is_empty();
    drop(app);

    if visible.is_empty() {
        let (title, subtitle) = empty_state_text(scope, has_any, has_query);
        let empty = adw::StatusPage::builder()
            .icon_name("computer-symbolic")
            .title(title)
            .description(subtitle)
            .build();
        ctx.shell.flow.insert(&empty, -1);
        return;
    }

    for profile in visible {
        let card = build_machine_card(
            &profile,
            active_id.as_deref() == Some(profile.id.as_str()),
            &ctx.sessions,
        );
        let root = card.root.clone();
        attach_card_actions(
            card,
            &profile,
            ctx.state.clone(),
            ctx.parent.clone(),
            ctx.shell.clone(),
            ctx.sessions.clone(),
            ctx.layout,
        );
        ctx.shell.flow.insert(&root, -1);
    }
}

struct MachineCard {
    root: gtk::Box,
    run_btn: gtk::Button,
    stop_btn: gtk::Button,
    edit_btn: gtk::Button,
    delete_btn: gtk::Button,
}

fn build_machine_card(
    profile: &MachineProfile,
    is_active: bool,
    sessions: &MachineSessions,
) -> MachineCard {
    let frame = gtk::Frame::new(None);
    frame.add_css_class("card");
    frame.set_width_request(240);

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 8);
    vbox.set_margin_top(12);
    vbox.set_margin_bottom(12);
    vbox.set_margin_start(12);
    vbox.set_margin_end(12);

    // Thumbnail or type icon placeholder
    let thumb_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    thumb_box.add_css_class("card");
    thumb_box.set_height_request(120);
    if let Ok(path) = thumbnail_store::thumbnail_path(&profile.id) {
        if path.is_file() {
            let pic = gtk::Picture::for_filename(&path);
            pic.set_can_shrink(true);
            pic.set_hexpand(true);
            pic.set_vexpand(true);
            thumb_box.append(&pic);
        } else {
            let icon = gtk::Image::from_icon_name(profile.machine_type.icon_name());
            icon.set_pixel_size(48);
            icon.set_halign(gtk::Align::Center);
            icon.set_valign(gtk::Align::Center);
            thumb_box.set_valign(gtk::Align::Center);
            thumb_box.append(&icon);
        }
    }

    let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let title = gtk::Label::new(Some(&profile.name));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    title.add_css_class("heading");
    title.set_xalign(0.0);

    let fav = gtk::Image::from_icon_name(if profile.favorite {
        "starred-symbolic"
    } else {
        "non-starred-symbolic"
    });
    title_row.append(&title);
    title_row.append(&fav);

    let subtitle = gtk::Label::new(Some(&format!(
        "{} · {}",
        profile.machine_type.user_facing_name(),
        profile.summary()
    )));
    subtitle.set_wrap(true);
    subtitle.add_css_class("dim-label");
    subtitle.set_xalign(0.0);

    let (running, pid) = machine_session_status(&profile.id, sessions);
    let status_text = if running {
        pid.map(|p| format!("Running · pid {p}"))
            .unwrap_or_else(|| "Running".to_string())
    } else if is_active {
        "Active".to_string()
    } else {
        "Stopped".to_string()
    };
    let status = gtk::Label::new(Some(&status_text));
    status.add_css_class(if running { "success" } else { "dim-label" });
    status.set_xalign(0.0);

    let actions = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    actions.set_halign(gtk::Align::End);

    let run_btn = gtk::Button::from_icon_name("media-playback-start-symbolic");
    run_btn.set_tooltip_text(Some("Run"));
    run_btn.add_css_class("flat");
    let stop_btn = gtk::Button::from_icon_name("media-playback-stop-symbolic");
    stop_btn.set_tooltip_text(Some("Stop"));
    stop_btn.add_css_class("flat");
    let edit_btn = gtk::Button::from_icon_name("document-edit-symbolic");
    edit_btn.set_tooltip_text(Some("Edit"));
    edit_btn.add_css_class("flat");
    let delete_btn = gtk::Button::from_icon_name("user-trash-symbolic");
    delete_btn.set_tooltip_text(Some("Delete"));
    delete_btn.add_css_class("flat");
    actions.append(&run_btn);
    actions.append(&stop_btn);
    actions.append(&edit_btn);
    actions.append(&delete_btn);

    vbox.append(&thumb_box);
    vbox.append(&title_row);
    vbox.append(&subtitle);
    vbox.append(&status);
    vbox.append(&actions);
    frame.set_child(Some(&vbox));

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&frame);

    run_btn.set_sensitive(!running);
    stop_btn.set_sensitive(running);

    MachineCard {
        root,
        run_btn,
        stop_btn,
        edit_btn,
        delete_btn,
    }
}

fn attach_card_actions(
    card: MachineCard,
    profile: &MachineProfile,
    state: SharedAppState,
    parent: adw::ApplicationWindow,
    shell: HomeShell,
    sessions: MachineSessions,
    layout: LayoutMode,
) {
    let run_btn = card.run_btn;
    let stop_btn = card.stop_btn;
    let edit_btn = card.edit_btn;
    let delete_btn = card.delete_btn;

    let (running, _) = machine_session_status(&profile.id, &sessions);
    run_btn.set_sensitive(!running);
    stop_btn.set_sensitive(running);

    let mid = profile.id.clone();
    let mname = profile.name.clone();
    let shell_r = shell.clone();
    let state_r = state.clone();
    let parent_r = parent.clone();
    let sessions_r = sessions.clone();
    run_btn.connect_clicked(move |_| {
        match try_launch_profile(&mid, &state_r) {
            Ok(child) => {
                wlog!("UI", "Launched '{}' pid={}", mname, child.id());
                sessions_r.borrow_mut().insert(mid.clone(), child);
                rebuild_home(RebuildHome {
                    shell: &shell_r,
                    state: &state_r,
                    parent: &parent_r,
                    sessions: sessions_r.clone(),
                    layout,
                });
            }
            Err(e) => show_warning(&parent_r, &e),
        }
    });

    let mid = profile.id.clone();
    let shell_s = shell.clone();
    let state_s = state.clone();
    let parent_s = parent.clone();
    let sessions_s = sessions.clone();
    stop_btn.connect_clicked(move |_| {
        stop_machine(&mid, &sessions_s);
        rebuild_home(RebuildHome {
            shell: &shell_s,
            state: &state_s,
            parent: &parent_s,
            sessions: sessions_s.clone(),
            layout,
        });
    });

    let existing = profile.clone();
    let state_e = state.clone();
    let parent_e = parent.clone();
    let shell_e = shell.clone();
    let sessions_e = sessions.clone();
    edit_btn.connect_clicked(move |_| {
        editor::show_editor(
            &parent_e,
            &state_e,
            Some(existing.clone()),
            &shell_e,
            sessions_e.clone(),
            layout,
        );
    });

    let mid = profile.id.clone();
    let state_d = state.clone();
    let parent_d = parent.clone();
    let shell_d = shell.clone();
    let sessions_d = sessions.clone();
    delete_btn.connect_clicked(move |_| {
        let mut app = state_d.borrow_mut();
        let _ = app.store.delete(&mid);
        drop(app);
        rebuild_home(RebuildHome {
            shell: &shell_d,
            state: &state_d,
            parent: &parent_d,
            sessions: sessions_d.clone(),
            layout,
        });
    });
}

impl Clone for HomeShell {
    fn clone(&self) -> Self {
        Self {
            root: self.root.clone(),
            search: self.search.clone(),
            flow: self.flow.clone(),
            scope: self.scope.clone(),
            query: self.query.clone(),
        }
    }
}

fn prune_dead_sessions(sessions: &MachineSessions) {
    sessions
        .borrow_mut()
        .retain(|_, child| matches!(child.try_wait(), Ok(None)));
}

fn machine_session_status(machine_id: &str, sessions: &MachineSessions) -> (bool, Option<u32>) {
    let mut map = sessions.borrow_mut();
    let Some(child) = map.get_mut(machine_id) else {
        return (false, None);
    };
    match child.try_wait() {
        Ok(Some(_)) => {
            map.remove(machine_id);
            (false, None)
        }
        Ok(None) => (true, Some(child.id())),
        Err(_) => (true, Some(child.id())),
    }
}

fn stop_machine(machine_id: &str, sessions: &MachineSessions) {
    if let Some(mut child) = sessions.borrow_mut().remove(machine_id) {
        wlog!("UI", "Stopping machine id={} pid={}", machine_id, child.id());
        let _ = child.kill();
        let _ = child.wait();
    }
}

pub fn try_launch_profile(machine_id: &str, state: &SharedAppState) -> Result<Child, String> {
    let app = state.borrow();
    let profile = app
        .store
        .profile(machine_id)
        .ok_or_else(|| "machine not found".to_string())?
        .clone();
    let settings = app.settings.clone();
    drop(app);
    let rt = runtime::read_runtime_state().map_err(|e| format!("{e}"))?;
    launcher::launch_profile(&profile, &settings, &rt).map_err(|e| format!("{e}"))
}

fn show_warning(parent: &adw::ApplicationWindow, message: &str) {
    let msg = if message.contains("runtime") || message.contains("XDG") {
        "Wawona compositor is not running. Launch the app (embedded compositor) or start the host from Settings → Diagnostics."
    } else {
        message
    };
    let dlg = gtk::MessageDialog::new(
        Some(parent),
        gtk::DialogFlags::MODAL,
        gtk::MessageType::Warning,
        gtk::ButtonsType::Ok,
        msg,
    );
    dlg.connect_response(|d, _| d.close());
    dlg.present();
}
