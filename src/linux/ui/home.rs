//! Machines home — 1:1 with macOS `WWNMachinesGridView`: summary strip,
//! adaptive card grid, and card actions (Start / Stop / Focus / Edit / Delete).

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
use crate::linux::ui_model::{
    empty_state_text, launch_supported, machine_configuration_summary, machine_scope_label,
    machine_subtitle, visible_machines, LayoutMode,
};
use crate::wlog;

pub type MachineSessions = Rc<RefCell<HashMap<String, Child>>>;

pub struct HomeShell {
    pub root: gtk::Box,
    pub search: gtk::SearchEntry,
    pub summary: gtk::Box,
    pub flow: gtk::FlowBox,
    pub query: Rc<RefCell<String>>,
}

pub struct RebuildHome<'a> {
    pub shell: &'a HomeShell,
    pub state: &'a SharedAppState,
    pub parent: &'a adw::ApplicationWindow,
    pub sessions: MachineSessions,
    pub layout: LayoutMode,
}

pub fn build_home_shell(on_rebuild: Rc<dyn Fn()>) -> HomeShell {
    install_machine_card_styles();

    let search = gtk::SearchEntry::builder()
        .placeholder_text("Search machines")
        .hexpand(true)
        .build();

    // Summary strip: "Machines" + Profiles / Connected / Ready pills
    // (mirrors macOS `summaryStrip`).
    let summary = gtk::Box::new(gtk::Orientation::Horizontal, 10);
    summary.set_margin_start(18);
    summary.set_margin_end(18);
    summary.set_margin_top(8);

    let flow = gtk::FlowBox::new();
    flow.set_selection_mode(gtk::SelectionMode::None);
    flow.set_homogeneous(false);
    flow.set_max_children_per_line(3);
    flow.set_min_children_per_line(1);
    flow.set_column_spacing(14);
    flow.set_row_spacing(14);
    flow.set_margin_start(16);
    flow.set_margin_end(16);
    flow.set_margin_bottom(16);

    let query = Rc::new(RefCell::new(String::new()));

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
    root.append(&summary);
    root.append(&scroll);
    crate::linux::ui::a11y::set_wwn_a11y(
        &root,
        crate::linux::ui::a11y::id::MACHINES_ROOT,
        Some("Machines"),
    );

    HomeShell {
        root,
        search,
        summary,
        flow,
        query,
    }
}

pub fn rebuild_home(ctx: RebuildHome<'_>) {
    while let Some(child) = ctx.shell.flow.first_child() {
        ctx.shell.flow.remove(&child);
    }

    prune_dead_sessions(&ctx.sessions);

    let app = ctx.state.borrow();
    let query = ctx.shell.query.borrow().clone();
    let active_id = app.store.active_machine_id.clone();
    let all_profiles: Vec<MachineProfile> = app.store.profiles.clone();
    let visible: Vec<MachineProfile> = visible_machines(&app.store.profiles, &query)
        .into_iter()
        .cloned()
        .collect();
    let has_any = !app.store.profiles.is_empty();
    let has_query = !query.trim().is_empty();
    drop(app);

    rebuild_summary_strip(&ctx.shell.summary, &all_profiles, &ctx.sessions);

    if visible.is_empty() {
        let (title, subtitle) = empty_state_text(has_any, has_query);
        let empty = adw::StatusPage::builder()
            .icon_name("system-search-symbolic")
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
        configure_flowbox_child(&root);
    }
}

/// "Machines" heading + Profiles / Connected / Ready pills.
fn rebuild_summary_strip(
    summary: &gtk::Box,
    profiles: &[MachineProfile],
    sessions: &MachineSessions,
) {
    while let Some(child) = summary.first_child() {
        summary.remove(&child);
    }

    let heading_icon = gtk::Image::from_icon_name("network-server-symbolic");
    let heading = gtk::Label::new(Some("Machines"));
    heading.add_css_class("heading");
    summary.append(&heading_icon);
    summary.append(&heading);

    let connected = profiles
        .iter()
        .filter(|p| machine_session_status(&p.id, sessions).0)
        .count();
    let ready = profiles.iter().filter(|p| launch_supported(p)).count();

    for (title, value) in [
        ("Profiles", profiles.len()),
        ("Connected", connected),
        ("Ready", ready),
    ] {
        let pill = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        pill.add_css_class("card");
        pill.set_margin_top(2);
        pill.set_margin_bottom(2);
        let t = gtk::Label::new(Some(title));
        t.add_css_class("caption");
        t.set_margin_start(10);
        t.set_margin_top(4);
        t.set_margin_bottom(4);
        let v = gtk::Label::new(Some(&value.to_string()));
        v.add_css_class("caption-heading");
        v.set_margin_end(10);
        pill.append(&t);
        pill.append(&v);
        summary.append(&pill);
    }
}

struct MachineCard {
    root: gtk::Frame,
    start_btn: gtk::Button,
    stop_btn: gtk::Button,
    focus_btn: gtk::Button,
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
    frame.add_css_class("machine-card");
    frame.set_halign(gtk::Align::Fill);
    frame.set_hexpand(true);
    frame.set_vexpand(false);
    frame.set_width_request(300);

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 12);
    vbox.set_margin_top(16);
    vbox.set_margin_bottom(16);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);

    let (running, _pid) = machine_session_status(&profile.id, sessions);

    // Header banner: thumbnail (or type placeholder) with name + subtitle and
    // the machine-type icon (mirrors macOS `headerBanner`).
    let banner = gtk::Overlay::new();
    let thumb_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    thumb_box.add_css_class("machine-banner");
    thumb_box.set_height_request(90);
    let mut has_thumbnail = false;
    if let Ok(path) = thumbnail_store::thumbnail_path(&profile.id) {
        if path.is_file() {
            has_thumbnail = true;
            let pic = gtk::Picture::for_filename(&path);
            pic.set_can_shrink(true);
            pic.set_hexpand(true);
            pic.set_vexpand(true);
            thumb_box.append(&pic);
        }
    }
    if !has_thumbnail {
        thumb_box.add_css_class("machine-banner-placeholder");
    }
    banner.set_child(Some(&thumb_box));

    let banner_text = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    banner_text.set_margin_start(12);
    banner_text.set_margin_end(12);
    banner_text.set_valign(gtk::Align::Center);
    let name_col = gtk::Box::new(gtk::Orientation::Vertical, 4);
    name_col.set_hexpand(true);
    name_col.set_valign(gtk::Align::Center);
    let title = gtk::Label::new(Some(if profile.name.is_empty() {
        "Unnamed Machine"
    } else {
        &profile.name
    }));
    title.add_css_class("title-3");
    title.set_xalign(0.0);
    title.set_ellipsize(gtk::pango::EllipsizeMode::End);
    let subtitle = gtk::Label::new(Some(&machine_subtitle(profile)));
    subtitle.add_css_class("dim-label");
    subtitle.set_xalign(0.0);
    subtitle.set_ellipsize(gtk::pango::EllipsizeMode::End);
    name_col.append(&title);
    name_col.append(&subtitle);
    let type_icon = gtk::Image::from_icon_name(profile.machine_type.icon_name());
    type_icon.set_pixel_size(24);
    banner_text.append(&name_col);
    banner_text.append(&type_icon);
    banner.add_overlay(&banner_text);

    // Status badge + scope/type/active chips.
    let badge_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let status_text = if running { "Connected" } else { "Disconnected" };
    let status_icon = gtk::Image::from_icon_name(if running {
        "emblem-ok-symbolic"
    } else {
        "media-playback-pause-symbolic"
    });
    let status = gtk::Label::new(Some(status_text));
    status.add_css_class("caption-heading");
    if running {
        status.add_css_class("success");
        status_icon.add_css_class("success");
    } else {
        status.add_css_class("dim-label");
        status_icon.add_css_class("dim-label");
    }
    badge_row.append(&status_icon);
    badge_row.append(&status);

    let chips = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    chips.set_halign(gtk::Align::End);
    chips.set_hexpand(true);
    chips.append(&chip(&machine_scope_label(profile.machine_type).to_uppercase()));
    chips.append(&chip(&profile.machine_type.user_facing_name().to_uppercase()));
    if is_active {
        chips.append(&chip("ACTIVE"));
    }
    badge_row.append(&chips);

    // Summary line (e.g. "Runs: Weston Terminal").
    let summary = gtk::Label::new(Some(&machine_configuration_summary(profile)));
    summary.set_wrap(true);
    summary.set_lines(3);
    summary.add_css_class("dim-label");
    summary.add_css_class("caption");
    summary.set_xalign(0.0);

    // Action row: Start (or Focus + Stop when running), Edit, Delete.
    let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);

    let start_btn = button_with_icon_label("media-playback-start-symbolic", "Start");
    start_btn.add_css_class("suggested-action");
    crate::linux::ui::a11y::set_wwn_a11y(
        &start_btn,
        crate::linux::ui::a11y::id::MACHINES_START,
        Some("Start"),
    );
    let focus_btn = button_with_icon_label("find-location-symbolic", "Focus");
    crate::linux::ui::a11y::set_wwn_a11y(
        &focus_btn,
        crate::linux::ui::a11y::id::MACHINES_FOCUS,
        Some("Focus"),
    );
    let stop_btn = button_with_icon_label("media-playback-stop-symbolic", "Stop");
    stop_btn.add_css_class("destructive-action");
    crate::linux::ui::a11y::set_wwn_a11y(
        &stop_btn,
        crate::linux::ui::a11y::id::MACHINES_STOP,
        Some("Stop"),
    );
    let edit_btn = button_with_icon_label("emblem-system-symbolic", "Edit");
    crate::linux::ui::a11y::set_wwn_a11y(
        &edit_btn,
        crate::linux::ui::a11y::id::MACHINES_EDIT,
        Some("Edit"),
    );
    let delete_btn = button_with_icon_label("user-trash-symbolic", "Delete");
    crate::linux::ui::a11y::set_wwn_a11y(
        &delete_btn,
        crate::linux::ui::a11y::id::MACHINES_DELETE,
        Some("Delete"),
    );

    start_btn.set_visible(!running);
    start_btn.set_sensitive(launch_supported(profile));
    focus_btn.set_visible(running);
    stop_btn.set_visible(running);
    delete_btn.set_sensitive(!running);

    actions.append(&start_btn);
    actions.append(&focus_btn);
    actions.append(&stop_btn);
    actions.append(&edit_btn);
    actions.append(&delete_btn);

    vbox.append(&banner);
    vbox.append(&badge_row);
    vbox.append(&summary);
    vbox.append(&actions);
    frame.set_child(Some(&vbox));

    MachineCard {
        root: frame,
        start_btn,
        stop_btn,
        focus_btn,
        edit_btn,
        delete_btn,
    }
}

fn button_with_icon_label(icon: &str, label: &str) -> gtk::Button {
    let content = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    content.append(&gtk::Image::from_icon_name(icon));
    content.append(&gtk::Label::new(Some(label)));
    let btn = gtk::Button::new();
    btn.set_child(Some(&content));
    btn
}

fn chip(text: &str) -> gtk::Box {
    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    pill.add_css_class("machine-chip");
    let lbl = gtk::Label::new(Some(text));
    lbl.add_css_class("caption-heading");
    lbl.set_margin_start(8);
    lbl.set_margin_end(8);
    lbl.set_margin_top(4);
    lbl.set_margin_bottom(4);
    lbl.set_xalign(0.5);
    pill.append(&lbl);
    pill
}

fn configure_flowbox_child(card: &impl IsA<gtk::Widget>) {
    if let Some(fbc) = card
        .parent()
        .and_then(|parent| parent.downcast::<gtk::FlowBoxChild>().ok())
    {
        fbc.set_can_focus(false);
        fbc.set_vexpand(false);
        fbc.set_hexpand(true);
        fbc.set_halign(gtk::Align::Fill);
    }
}

fn install_machine_card_styles() {
    use std::sync::Once;

    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            r#"
            flowbox flowboxchild {
              padding: 0;
            }

            .machine-card {
              border: 1px solid transparent;
            }

            .machine-card:hover {
              border-color: alpha(currentColor, 0.08);
            }

            .machine-banner {
              border-radius: 12px;
              min-height: 90px;
            }

            .machine-banner-placeholder {
              background-image: linear-gradient(
                135deg,
                alpha(@accent_color, 0.22),
                alpha(@theme_fg_color, 0.08)
              );
            }

            .machine-chip {
              background-color: alpha(currentColor, 0.08);
              border-radius: 999px;
            }
            "#,
        );
        if let Some(display) = gtk::gdk::Display::default() {
            gtk::style_context_add_provider_for_display(
                &display,
                &provider,
                gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }
    });
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
    let start_btn = card.start_btn;
    let stop_btn = card.stop_btn;
    let focus_btn = card.focus_btn;
    let edit_btn = card.edit_btn;
    let delete_btn = card.delete_btn;

    let mid = profile.id.clone();
    let mname = profile.name.clone();
    let shell_r = shell.clone();
    let state_r = state.clone();
    let parent_r = parent.clone();
    let sessions_r = sessions.clone();
    start_btn.connect_clicked(move |_| {
        match try_launch_profile(&mid, &state_r) {
            Ok(child) => {
                wlog!("UI", "Launched '{}' pid={}", mname, child.id());
                sessions_r.borrow_mut().insert(mid.clone(), child);
                let mut app = state_r.borrow_mut();
                let _ = app.store.set_active(Some(mid.clone()));
                drop(app);
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

    // Focus: mark active (host window raise is compositor-driven).
    let mid = profile.id.clone();
    let shell_f = shell.clone();
    let state_f = state.clone();
    let parent_f = parent.clone();
    let sessions_f = sessions.clone();
    focus_btn.connect_clicked(move |_| {
        let mut app = state_f.borrow_mut();
        let _ = app.store.set_active(Some(mid.clone()));
        drop(app);
        rebuild_home(RebuildHome {
            shell: &shell_f,
            state: &state_f,
            parent: &parent_f,
            sessions: sessions_f.clone(),
            layout,
        });
    });

    let mid = profile.id.clone();
    let shell_s = shell.clone();
    let state_s = state.clone();
    let parent_s = parent.clone();
    let sessions_s = sessions.clone();
    stop_btn.connect_clicked(move |_| {
        stop_machine(&mid, &sessions_s);
        let mut app = state_s.borrow_mut();
        if app.store.active_machine_id.as_deref() == Some(mid.as_str()) {
            let _ = app.store.set_active(None);
        }
        drop(app);
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
            existing.machine_type,
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
            summary: self.summary.clone(),
            flow: self.flow.clone(),
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
