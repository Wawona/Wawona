//! Safari-style Tab Overview for the Linux GTK host.

use std::rc::Rc;

use adw::prelude::*;
use gtk::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::domain::tab_overview;
use crate::linux::machine_profile::MachineProfile;
use crate::linux::ui::a11y;
use crate::linux::ui::home::{rebuild_home, HomeShell, MachineSessions, RebuildHome};
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;

/// Present Tab Overview as a modal window (search + preview cards).
pub fn show_tab_overview(
    parent: &adw::ApplicationWindow,
    state: &SharedAppState,
    sessions: MachineSessions,
    shell: &HomeShell,
    layout: LayoutMode,
) {
    let window = adw::Window::builder()
        .transient_for(parent)
        .modal(true)
        .default_width(720)
        .default_height(520)
        .title("Tab Overview")
        .build();

    let header = adw::HeaderBar::new();
    let title = gtk::Label::new(Some("Tab Overview"));
    title.add_css_class("title");
    header.set_title_widget(Some(&title));

    let search = gtk::SearchEntry::new();
    search.set_placeholder_text(Some("Search Tabs"));
    search.set_hexpand(true);
    a11y::set_wwn_a11y(&search, a11y::id::MACHINES_OVERVIEW, Some("Search Tabs"));

    let count_lbl = gtk::Label::new(None);
    count_lbl.add_css_class("dim-label");

    let flow = gtk::FlowBox::new();
    flow.set_valign(gtk::Align::Start);
    flow.set_max_children_per_line(3);
    flow.set_selection_mode(gtk::SelectionMode::None);
    flow.set_homogeneous(true);
    flow.set_column_spacing(12);
    flow.set_row_spacing(12);
    flow.set_margin_start(16);
    flow.set_margin_end(16);
    flow.set_margin_top(8);
    flow.set_margin_bottom(16);

    let scroller = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .child(&flow)
        .build();

    let empty = adw::StatusPage::builder()
        .icon_name("view-grid-symbolic")
        .title("No Active Tabs")
        .description("Start a machine, then open Tab Overview to switch sessions.")
        .build();

    let stack = gtk::Stack::new();
    stack.add_named(&scroller, Some("grid"));
    stack.add_named(&empty, Some("empty"));

    let body = gtk::Box::new(gtk::Orientation::Vertical, 8);
    body.append(&search);
    body.append(&count_lbl);
    body.append(&stack);
    body.set_margin_start(12);
    body.set_margin_end(12);
    body.set_margin_top(8);

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&header);
    root.append(&body);
    window.set_content(Some(&root));

    let rebuild = Rc::new({
        let flow = flow.clone();
        let stack = stack.clone();
        let empty = empty.clone();
        let count_lbl = count_lbl.clone();
        let search = search.clone();
        let state = state.clone();
        let sessions = sessions.clone();
        let parent = parent.clone();
        let shell = shell.clone();
        let window = window.clone();
        move || {
            while let Some(child) = flow.first_child() {
                flow.remove(&child);
            }

            let live_ids: Vec<String> = {
                let mut map = sessions.borrow_mut();
                map.retain(|_, child| matches!(child.try_wait(), Ok(None)));
                map.keys().cloned().collect()
            };

            let app = state.borrow();
            let active = app.store.active_machine_id.clone();
            let mut cards: Vec<MachineProfile> = app
                .store
                .profiles
                .iter()
                .filter(|p| {
                    live_ids.iter().any(|id| id == &p.id)
                        || active.as_deref() == Some(p.id.as_str())
                })
                .cloned()
                .collect();
            drop(app);

            let had_running = !cards.is_empty();
            let q = search.text().to_string();
            let titles: Vec<String> = cards.iter().map(|p| p.name.clone()).collect();
            let indices = tab_overview::filter_indices(&q, &titles);
            cards = indices
                .into_iter()
                .filter_map(|i| cards.get(i).cloned())
                .collect();

            let n = cards.len();
            count_lbl.set_text(&if n == 1 {
                "1 Tab".to_string()
            } else {
                format!("{n} Tabs")
            });

            if cards.is_empty() {
                stack.set_visible_child_name("empty");
                if !had_running && q.trim().is_empty() {
                    empty.set_title("No Active Tabs");
                    empty.set_description(Some(
                        "Start a machine, then open Tab Overview to switch sessions.",
                    ));
                } else {
                    empty.set_title("No Matching Tabs");
                    empty.set_description(Some("Try a different search."));
                }
                return;
            }
            stack.set_visible_child_name("grid");

            for profile in cards {
                let card = build_card(
                    &profile,
                    active.as_deref() == Some(profile.id.as_str()),
                    &state,
                    &sessions,
                    &parent,
                    &shell,
                    layout,
                    &window,
                );
                flow.append(&card);
            }
        }
    });

    {
        let rebuild = rebuild.clone();
        search.connect_search_changed(move |_| rebuild());
    }
    rebuild();

    window.present();
}

fn build_card(
    profile: &MachineProfile,
    is_active: bool,
    state: &SharedAppState,
    sessions: &MachineSessions,
    parent: &adw::ApplicationWindow,
    shell: &HomeShell,
    layout: LayoutMode,
    overview: &adw::Window,
) -> gtk::Frame {
    let frame = gtk::Frame::new(None);
    frame.add_css_class("card");

    let box_ = gtk::Box::new(gtk::Orientation::Vertical, 6);
    box_.set_margin_start(10);
    box_.set_margin_end(10);
    box_.set_margin_top(10);
    box_.set_margin_bottom(10);

    let header_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let title = gtk::Label::new(Some(&profile.name));
    title.set_xalign(0.0);
    title.set_hexpand(true);
    title.set_ellipsize(gtk::pango::EllipsizeMode::End);
    title.add_css_class("heading");
    header_row.append(&title);

    let close_btn = gtk::Button::from_icon_name("window-close-symbolic");
    close_btn.add_css_class("flat");
    close_btn.set_tooltip_text(Some("Close"));
    a11y::set_wwn_a11y(
        &close_btn,
        a11y::id::MACHINES_OVERVIEW_TERMINATE,
        Some(&format!("Close {}", profile.name)),
    );
    header_row.append(&close_btn);
    box_.append(&header_row);

    let preview = gtk::Box::new(gtk::Orientation::Vertical, 8);
    preview.set_size_request(180, 120);
    preview.add_css_class("view");
    let icon = gtk::Image::from_icon_name("computer-symbolic");
    icon.set_pixel_size(36);
    icon.set_halign(gtk::Align::Center);
    icon.set_valign(gtk::Align::Center);
    icon.set_vexpand(true);
    preview.append(&icon);
    let status = gtk::Label::new(Some(if is_active {
        "Running · Active"
    } else {
        "Running"
    }));
    status.add_css_class("dim-label");
    status.set_halign(gtk::Align::Center);
    preview.append(&status);
    box_.append(&preview);

    let focus_btn = gtk::Button::with_label("Focus");
    focus_btn.add_css_class("suggested-action");
    a11y::set_wwn_a11y(
        &focus_btn,
        a11y::id::MACHINES_OVERVIEW_FOCUS,
        Some(&format!("Focus {}", profile.name)),
    );
    box_.append(&focus_btn);

    frame.set_child(Some(&box_));

    {
        let mid = profile.id.clone();
        let state = state.clone();
        let parent = parent.clone();
        let shell = shell.clone();
        let sessions = sessions.clone();
        let overview = overview.clone();
        focus_btn.connect_clicked(move |_| {
            {
                let mut app = state.borrow_mut();
                let _ = app.store.set_active(Some(mid.clone()));
            }
            overview.close();
            rebuild_home(RebuildHome {
                shell: &shell,
                state: &state,
                parent: &parent,
                sessions: sessions.clone(),
                layout,
            });
        });
    }

    {
        let mid = profile.id.clone();
        let state = state.clone();
        let parent = parent.clone();
        let shell = shell.clone();
        let sessions = sessions.clone();
        let overview = overview.clone();
        close_btn.connect_clicked(move |_| {
            if let Some(mut child) = sessions.borrow_mut().remove(&mid) {
                let _ = child.kill();
            }
            {
                let mut app = state.borrow_mut();
                if app.store.active_machine_id.as_deref() == Some(mid.as_str()) {
                    let _ = app.store.set_active(None);
                }
            }
            overview.close();
            rebuild_home(RebuildHome {
                shell: &shell,
                state: &state,
                parent: &parent,
                sessions: sessions.clone(),
                layout,
            });
        });
    }

    frame
}
