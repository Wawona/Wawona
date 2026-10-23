//! Machines home. 1:1 with macOS `WWNMachinesGridView`: summary strip,
//! adaptive card grid, and card actions (Start / Stop / Focus / Edit / Delete).

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::process::Child;
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

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
    pub banner: gtk::Box,
    pub continue_btn: gtk::Button,
    pub search: gtk::SearchEntry,
    pub summary: gtk::Box,
    pub flow: gtk::Box,
    pub query: Rc<RefCell<String>>,
    pub selected_tag_id: Rc<RefCell<Option<String>>>,
    pub on_rebuild: Rc<dyn Fn()>,
}

pub struct RebuildHome<'a> {
    pub shell: &'a HomeShell,
    pub state: &'a SharedAppState,
    pub parent: &'a adw::ApplicationWindow,
    pub sessions: MachineSessions,
    pub layout: LayoutMode,
    pub on_edit: Option<Rc<dyn Fn(MachineProfile)>>,
    pub on_open_terminal: Option<Rc<dyn Fn(String, super::terminal::TerminalLaunch)>>,
}

pub fn build_home_shell(on_rebuild: Rc<dyn Fn()>) -> HomeShell {
    install_machine_card_styles();

    let search = gtk::SearchEntry::builder()
        .placeholder_text("Search machines")
        .hexpand(true)
        .build();
    search.set_size_request(80, -1);

    // Summary strip: one horizontal row. "Machines" sits beside the pills.
    let summary = gtk::Box::new(gtk::Orientation::Vertical, 0);
    summary.set_margin_start(8);
    summary.set_margin_end(8);
    summary.set_margin_top(8);

    let flow = gtk::Box::new(gtk::Orientation::Vertical, 12);
    flow.set_hexpand(true);
    flow.set_vexpand(true);
    flow.set_margin_start(8);
    flow.set_margin_end(8);
    flow.set_margin_bottom(12);

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
        .hexpand(true)
        .min_content_width(0)
        .min_content_height(0)
        .propagate_natural_width(false)
        .child(&flow)
        .build();

    let banner = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    banner.add_css_class("card");
    banner.set_margin_start(16);
    banner.set_margin_end(16);
    banner.set_margin_top(8);
    banner.set_margin_bottom(8);

    let lbl = gtk::Label::new(Some(crate::domain::welcome_copy::MESSAGE));
    lbl.set_wrap(true);
    lbl.set_hexpand(true);
    lbl.set_xalign(0.0);
    banner.append(&lbl);

    let continue_btn = gtk::Button::with_label(crate::domain::welcome_copy::CONTINUE);
    continue_btn.add_css_class("suggested-action");
    continue_btn.set_valign(gtk::Align::Center);
    banner.append(&continue_btn);
    banner.set_visible(false);

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&banner);
    root.append(&summary);
    root.append(&scroll);
    crate::linux::ui::a11y::set_wwn_a11y(
        &root,
        crate::linux::ui::a11y::id::MACHINES_ROOT,
        None,
    );

    // Responsive column count listener
    let current_cols = Rc::new(Cell::new(0));
    let on_rebuild_resize = on_rebuild.clone();
    root.add_tick_callback(move |widget, _| {
        if !widget.is_mapped() {
            return gtk::glib::ControlFlow::Continue;
        }
        let w = widget.width();
        if w <= 0 {
            return gtk::glib::ControlFlow::Continue;
        }
        let cols = if w >= 1050 {
            3
        } else if w >= 680 {
            2
        } else {
            1
        };
        let prev = current_cols.get();
        if prev != 0 && prev != cols {
            current_cols.set(cols);
            on_rebuild_resize();
        } else if prev == 0 {
            current_cols.set(cols);
        }
        gtk::glib::ControlFlow::Continue
    });

    let selected_tag_id = Rc::new(RefCell::new(None));

    HomeShell {
        root,
        banner,
        continue_btn,
        search,
        summary,
        flow,
        query,
        selected_tag_id,
        on_rebuild,
    }
}

pub fn rebuild_home(ctx: RebuildHome<'_>) {
    while let Some(child) = ctx.shell.flow.first_child() {
        ctx.shell.flow.remove(&child);
    }

    prune_dead_sessions(&ctx.sessions);

    let app = ctx.state.borrow();
    let query = ctx.shell.query.borrow().clone();
    let selected_tag_id = ctx.shell.selected_tag_id.borrow().clone();
    let active_id = app.store.active_machine_id.clone();
    let all_profiles: Vec<MachineProfile> = app.store.profiles.clone();
    let mut visible: Vec<MachineProfile> = visible_machines(&app.store.profiles, &query)
        .into_iter()
        .cloned()
        .collect();

    let active_tag = selected_tag_id
        .as_ref()
        .and_then(|tid| app.tags.tags.iter().find(|t| &t.id == tid).cloned());

    if let Some(tid) = &selected_tag_id {
        visible.retain(|p| app.tags.is_assigned(tid, &p.id));
    }
    let has_any = !app.store.profiles.is_empty();
    let has_query = !query.trim().is_empty();
    let show_thumbnails = app.settings.session_thumbnails;
    drop(app);

    let on_clear_tag = {
        let tag_id_cell = ctx.shell.selected_tag_id.clone();
        let on_rebuild_fn = ctx.shell.on_rebuild.clone();
        Some(Rc::new(move || {
            tag_id_cell.replace(None);
            on_rebuild_fn();
        }) as Rc<dyn Fn()>)
    };

    rebuild_summary_strip(
        &ctx.shell.summary,
        &all_profiles,
        &ctx.sessions,
        active_tag.as_ref(),
        on_clear_tag,
    );

    if visible.is_empty() {
        let (title, subtitle) = if let Some(tag) = active_tag {
            (
                format!("No Machines Tagged \"{}\"", tag.name),
                "Assign this tag to a machine from its context menu.".to_string(),
            )
        } else {
            let (t, s) = empty_state_text(has_any, has_query);
            (t.to_string(), s.to_string())
        };
        let empty = adw::StatusPage::builder()
            .icon_name("system-search-symbolic")
            .title(title)
            .description(subtitle)
            .build();
        empty.set_vexpand(true);
        ctx.shell.flow.append(&empty);
        return;
    }

    let (pinned, unpinned): (Vec<_>, Vec<_>) = visible.into_iter().partition(|p| p.favorite);

    if !pinned.is_empty() {
        ctx.shell.flow.append(&section_label("Pinned", 8));
        let flow = populate_flow(&pinned, &query, &active_id, show_thumbnails, &ctx);
        ctx.shell.flow.append(&flow);
    }

    if !unpinned.is_empty() {
        let top = if pinned.is_empty() { 8 } else { 12 };
        ctx.shell.flow.append(&section_label("Machines", top));
        let flow = populate_flow(&unpinned, &query, &active_id, show_thumbnails, &ctx);
        ctx.shell.flow.append(&flow);
    }
}

fn section_label(text: &str, margin_top: i32) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.add_css_class("heading");
    label.add_css_class("dim-label");
    label.set_xalign(0.0);
    label.set_margin_top(margin_top);
    label.set_margin_bottom(2);
    label
}

/// Build an adaptive FlowBox of machine cards (replaces gtk::Grid).
/// FlowBox automatically reflows children based on their size request and the
/// available container width, matching SwiftUI's `LazyVGrid(.adaptive(...))`.
fn populate_flow(
    profiles: &[MachineProfile],
    query: &str,
    active_id: &Option<String>,
    show_thumbnails: bool,
    ctx: &RebuildHome<'_>,
) -> gtk::FlowBox {
    let flow = gtk::FlowBox::new();
    flow.set_orientation(gtk::Orientation::Horizontal);
    flow.set_column_spacing(14);
    flow.set_row_spacing(14);
    // Min 1 column, max 3. Each card requests min 280px so FlowBox decides
    // how many fit -- same adaptive behaviour as SwiftUI GridItem(.adaptive).
    flow.set_min_children_per_line(1);
    flow.set_max_children_per_line(3);
    flow.set_homogeneous(true);
    flow.set_selection_mode(gtk::SelectionMode::None);
    flow.set_hexpand(true);
    flow.set_halign(gtk::Align::Fill);

    for profile in profiles {
        let tags = ctx.state.borrow().tags.tags_for_machine(&profile.id);
        let card = build_machine_card(
            profile,
            active_id.as_deref() == Some(profile.id.as_str()),
            &ctx.sessions,
            &tags,
            query,
            show_thumbnails,
        );
        let root = card.root.clone();
        attach_card_actions(
            card,
            profile,
            ctx.state.clone(),
            ctx.parent.clone(),
            ctx.shell.clone(),
            ctx.sessions.clone(),
            ctx.layout,
            ctx.on_edit.clone(),
            ctx.on_open_terminal.clone(),
        );
        // Wrap in a box so FlowBox doesn't stretch the frame oddly.
        let wrapper = gtk::Box::new(gtk::Orientation::Vertical, 0);
        wrapper.set_hexpand(true);
        // 160px lets one card fit a phone-width column. FlowBox still grows
        // cards to share a wide window, up to three per line.
        wrapper.set_size_request(160, -1);
        wrapper.append(&root);
        flow.append(&wrapper);
    }
    flow
}

/// One side-scrolling row: "Machines" label, then Profiles / Connected / Ready,
/// then the active tag pill. Same order as the macOS summary strip.
fn rebuild_summary_strip(
    summary: &gtk::Box,
    profiles: &[MachineProfile],
    sessions: &MachineSessions,
    active_tag: Option<&crate::linux::tag_store::MachineTag>,
    on_clear_tag: Option<Rc<dyn Fn()>>,
) {
    while let Some(child) = summary.first_child() {
        summary.remove(&child);
    }

    let row = gtk::Box::new(gtk::Orientation::Horizontal, 10);
    row.set_halign(gtk::Align::Start);
    row.set_valign(gtk::Align::Center);

    let heading_group = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    heading_group.set_valign(gtk::Align::Center);
    let heading_icon = gtk::Image::from_icon_name("network-server-symbolic");
    heading_icon.set_valign(gtk::Align::Center);
    let heading = gtk::Label::new(Some("Machines"));
    heading.add_css_class("heading");
    heading.set_valign(gtk::Align::Center);
    heading.set_xalign(0.0);
    heading_group.append(&heading_icon);
    heading_group.append(&heading);
    row.append(&heading_group);

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
        let pill = summary_pill();
        let t = gtk::Label::new(Some(title));
        t.add_css_class("caption");
        t.set_margin_start(10);
        t.set_margin_top(4);
        t.set_margin_bottom(4);
        let v = gtk::Label::new(Some(&value.to_string()));
        v.add_css_class("caption-heading");
        v.set_margin_end(10);
        v.set_margin_top(4);
        v.set_margin_bottom(4);
        pill.append(&t);
        pill.append(&v);
        row.append(&pill);
    }

    if let Some(tag) = active_tag {
        let pill = summary_pill();
        let dot = color_dot(&tag.color_hex, 8);
        dot.set_margin_start(10);
        pill.append(&dot);

        let t = gtk::Label::new(Some(&tag.name));
        t.add_css_class("caption");
        t.set_margin_top(4);
        t.set_margin_bottom(4);
        pill.append(&t);

        if let Some(on_clear) = on_clear_tag {
            let clear_btn = gtk::Button::from_icon_name("window-close-symbolic");
            clear_btn.add_css_class("flat");
            clear_btn.add_css_class("circular");
            clear_btn.add_css_class("machine-summary-pill-clear");
            clear_btn.set_tooltip_text(Some("Clear tag filter"));
            clear_btn.set_margin_end(10);
            clear_btn.connect_clicked(move |_| {
                on_clear();
            });
            pill.append(&clear_btn);
        } else {
            t.set_margin_end(10);
        }
        row.append(&pill);
    }

    let scroll = gtk::ScrolledWindow::new();
    scroll.add_css_class("machine-summary-scroll");
    scroll.set_policy(gtk::PolicyType::External, gtk::PolicyType::Never);
    scroll.set_kinetic_scrolling(true);
    scroll.set_propagate_natural_height(true);
    scroll.set_propagate_natural_width(false);
    scroll.set_min_content_width(0);
    scroll.set_has_frame(false);
    scroll.set_hexpand(true);
    scroll.set_child(Some(&row));
    summary.append(&scroll);
}

fn summary_pill() -> gtk::Box {
    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    pill.add_css_class("card");
    pill.add_css_class("machine-summary-pill");
    pill.set_margin_top(2);
    pill.set_margin_bottom(2);
    pill.set_hexpand(false);
    pill.set_halign(gtk::Align::Start);
    pill.set_valign(gtk::Align::Center);
    pill
}

struct MachineCard {
    root: gtk::Frame,
    start_btn: gtk::Button,
    stop_btn: gtk::Button,
    focus_btn: gtk::Button,
    edit_btn: gtk::Button,
    delete_btn: gtk::Button,
}

fn highlighted_label_title(text: &str, query: &str) -> gtk::Label {
    let ranges = crate::linux::ui_model::highlight_ranges(query, text);
    if ranges.is_empty() {
        return gtk::Label::new(Some(text));
    }
    let is_dark = adw::StyleManager::default().is_dark();
    let bg_color = if is_dark { "#BF9130" } else { "#FFF9C4" };
    let fg_color = "#1F1F1F";

    let mut markup = String::new();
    let mut last = 0;
    for r in ranges {
        if r.start > last {
            markup.push_str(&gtk::glib::markup_escape_text(&text[last..r.start]));
        }
        let matched = gtk::glib::markup_escape_text(&text[r.clone()]);
        markup.push_str(&format!(
            r#"<span background="{bg_color}" foreground="{fg_color}" weight="bold">{matched}</span>"#
        ));
        last = r.end;
    }
    if last < text.len() {
        markup.push_str(&gtk::glib::markup_escape_text(&text[last..]));
    }
    let label = gtk::Label::new(None);
    label.set_markup(&markup);
    label
}

fn build_machine_card(
    profile: &MachineProfile,
    is_active: bool,
    sessions: &MachineSessions,
    tags: &[crate::linux::tag_store::MachineTag],
    search_query: &str,
    show_thumbnails: bool,
) -> MachineCard {
    let frame = gtk::Frame::new(None);
    frame.add_css_class("card");
    frame.add_css_class("machine-card");
    frame.set_halign(gtk::Align::Fill);
    frame.set_hexpand(true);
    frame.set_vexpand(false);

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 12);
    vbox.set_margin_top(16);
    vbox.set_margin_bottom(16);
    vbox.set_margin_start(16);
    vbox.set_margin_end(16);

    let (running, _pid) = machine_session_status(&profile.id, sessions);

    // Header banner: thumbnail (or gradient placeholder) with name + subtitle and
    // the machine-type icon in a frosted glass tile.
    let banner = gtk::Overlay::new();
    banner.add_css_class("machine-banner-clip");
    banner.set_overflow(gtk::Overflow::Hidden);
    let thumb_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    thumb_box.add_css_class("machine-banner");
    thumb_box.set_height_request(90);
    thumb_box.set_overflow(gtk::Overflow::Hidden);
    let pic = gtk::Picture::new();
    pic.add_css_class("machine-banner-image");
    pic.set_content_fit(gtk::ContentFit::Cover);
    pic.set_can_shrink(true);
    pic.set_hexpand(true);
    pic.set_vexpand(true);
    pic.set_overflow(gtk::Overflow::Hidden);
    pic.set_visible(false);
    thumb_box.append(&pic);
    if show_thumbnails {
        if let Ok(path) = thumbnail_store::thumbnail_path(&profile.id) {
            watch_machine_thumbnail(&thumb_box, &pic, path);
        } else {
            thumb_box.add_css_class("machine-banner-placeholder");
        }
    } else {
        thumb_box.add_css_class("machine-banner-placeholder");
    }
    banner.set_child(Some(&thumb_box));

    let scrim = gtk::Box::new(gtk::Orientation::Vertical, 0);
    scrim.add_css_class("machine-banner-scrim");
    scrim.set_hexpand(true);
    scrim.set_vexpand(true);
    scrim.set_overflow(gtk::Overflow::Hidden);
    scrim.set_can_target(false);
    banner.add_overlay(&scrim);

    let banner_content = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    banner_content.set_margin_start(14);
    banner_content.set_margin_end(14);
    banner_content.set_valign(gtk::Align::Center);
    banner_content.set_hexpand(true);

    let name_col = gtk::Box::new(gtk::Orientation::Vertical, 4);
    name_col.set_hexpand(true);
    name_col.set_valign(gtk::Align::Center);

    let display_name = if profile.name.is_empty() {
        "Unnamed Machine"
    } else {
        &profile.name
    };
    let title_widget = highlighted_label_title(display_name, search_query);
    title_widget.add_css_class("machine-banner-title");
    title_widget.set_xalign(0.0);
    title_widget.set_ellipsize(gtk::pango::EllipsizeMode::End);

    let subtitle = gtk::Label::new(Some(&machine_subtitle(profile)));
    subtitle.add_css_class("machine-banner-subtitle");
    subtitle.set_xalign(0.0);
    subtitle.set_ellipsize(gtk::pango::EllipsizeMode::End);

    let title_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    title_row.append(&title_widget);

    // Finder-style tag dots, inline with the machine name in the thumbnail banner.
    for t in tags.iter().take(4) {
        let dot = color_dot(&t.color_hex, 10);
        dot.set_tooltip_text(Some(&t.name));
        dot.set_valign(gtk::Align::Center);
        title_row.append(&dot);
    }
    if tags.len() > 4 {
        let more_lbl = gtk::Label::new(Some(&format!("+{}", tags.len() - 4)));
        more_lbl.add_css_class("caption");
        more_lbl.add_css_class("machine-banner-tag-count");
        more_lbl.set_tooltip_text(Some(&format!("{} more tags", tags.len() - 4)));
        more_lbl.set_valign(gtk::Align::Center);
        title_row.append(&more_lbl);
    }

    name_col.append(&title_row);
    name_col.append(&subtitle);

    // Trailing icon tray: machine-type icon tile + pinned icon tile
    let icon_tray = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    icon_tray.set_valign(gtk::Align::Center);
    icon_tray.set_halign(gtk::Align::End);

    let icon_tile = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    icon_tile.add_css_class("machine-type-icon-tile");
    icon_tile.set_valign(gtk::Align::Center);
    let type_icon = gtk::Image::from_icon_name(profile.machine_type.icon_name());
    type_icon.set_pixel_size(24);
    icon_tile.append(&type_icon);
    icon_tray.append(&icon_tile);

    if profile.favorite {
        let pin_tile = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        pin_tile.add_css_class("machine-pin-tile");
        pin_tile.set_valign(gtk::Align::Center);
        pin_tile.set_tooltip_text(Some("Pinned"));
        let pin_icon = gtk::Image::from_icon_name("view-pin-symbolic");
        pin_icon.set_pixel_size(18);
        pin_tile.append(&pin_icon);
        icon_tray.append(&pin_tile);
    }

    banner_content.append(&name_col);
    banner_content.append(&icon_tray);
    banner.add_overlay(&banner_content);

    // Status badge + chips
    let badge_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    badge_row.add_css_class("machine-badge-row");
    badge_row.set_hexpand(true);

    let status_icon = gtk::Image::from_icon_name(if running {
        "emblem-ok-symbolic"
    } else {
        "media-playback-pause-symbolic"
    });
    status_icon.set_pixel_size(14);
    let status = gtk::Label::new(Some(if running { "Connected" } else { "Disconnected" }));
    status.add_css_class("caption-heading");
    status.set_ellipsize(gtk::pango::EllipsizeMode::End);
    status.set_hexpand(true);
    status.set_halign(gtk::Align::Start);
    if running {
        status.add_css_class("success");
        status_icon.add_css_class("success");
    } else {
        status.add_css_class("dim-label");
        status_icon.add_css_class("dim-label");
    }
    badge_row.append(&status_icon);
    badge_row.append(&status);

    let chips = gtk::FlowBox::new();
    chips.set_selection_mode(gtk::SelectionMode::None);
    chips.set_column_spacing(6);
    chips.set_row_spacing(4);
    chips.set_min_children_per_line(1);
    chips.set_max_children_per_line(4);
    chips.set_homogeneous(false);
    chips.set_hexpand(true);
    chips.set_halign(gtk::Align::End);
    chips.add_css_class("machine-badge-chips");
    chips.append(&chip(
        &machine_scope_label(profile.machine_type).to_uppercase(),
    ));
    chips.append(&chip(
        &profile.machine_type.user_facing_name().to_uppercase(),
    ));
    if is_active {
        let a_chip = chip("ACTIVE");
        a_chip.add_css_class("machine-chip-active");
        chips.append(&a_chip);
    }
    badge_row.append(&chips);

    // Summary line
    let summary = gtk::Label::new(Some(&machine_configuration_summary(profile)));
    summary.set_wrap(true);
    summary.set_lines(2);
    summary.add_css_class("dim-label");
    summary.add_css_class("caption");
    summary.set_xalign(0.0);

    // Content-sized chips, packed from the start. A FlowBox that hexpands
    // gives every slot, including hidden Focus/Stop, an equal share of the
    // card, which opens a wide gap between Start and Edit.
    let actions = gtk::FlowBox::new();
    actions.set_selection_mode(gtk::SelectionMode::None);
    actions.set_column_spacing(6);
    actions.set_row_spacing(6);
    actions.set_min_children_per_line(1);
    actions.set_max_children_per_line(8);
    actions.set_homogeneous(false);
    actions.set_hexpand(false);
    actions.set_halign(gtk::Align::Start);
    actions.set_valign(gtk::Align::Start);
    actions.add_css_class("machine-actions-row");

    let start_btn = button_with_icon_label("media-playback-start-symbolic", "Start");
    start_btn.add_css_class("suggested-action");
    crate::linux::ui::a11y::set_wwn_a11y(
        &start_btn,
        crate::linux::ui::a11y::id::MACHINES_START,
        Some("Start"),
    );

    let focus_btn = button_with_icon_label("find-location-symbolic", "Focus");
    focus_btn.add_css_class("suggested-action");
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

    for btn in [&start_btn, &focus_btn, &stop_btn, &edit_btn, &delete_btn] {
        btn.set_hexpand(false);
        btn.set_halign(gtk::Align::Center);
        actions.append(btn);
        if let Some(slot) = btn.parent() {
            slot.set_hexpand(false);
            slot.set_halign(gtk::Align::Start);
            slot.set_visible(btn.is_visible());
        }
    }

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

fn watch_machine_thumbnail(banner: &gtk::Box, pic: &gtk::Picture, path: std::path::PathBuf) {
    let banner = banner.clone();
    let pic = pic.clone();
    let last_stamp = std::rc::Rc::new(std::cell::Cell::new(0u128));
    let ticks = std::rc::Rc::new(std::cell::Cell::new(0i32));
    banner.add_tick_callback(move |banner, _| {
        let n = ticks.get().wrapping_add(1);
        ticks.set(n);
        if n % 20 != 1 {
            return gtk::glib::ControlFlow::Continue;
        }
        let Ok(meta) = std::fs::metadata(&path) else {
            pic.set_visible(false);
            banner.add_css_class("machine-banner-placeholder");
            return gtk::glib::ControlFlow::Continue;
        };
        let stamp = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_millis())
            .unwrap_or(0);
        if stamp == last_stamp.get() {
            return gtk::glib::ControlFlow::Continue;
        }
        if let Ok(bytes) = std::fs::read(&path) {
            if let Ok(tex) = gtk::gdk::Texture::from_bytes(&gtk::glib::Bytes::from_owned(bytes)) {
                pic.set_paintable(Some(&tex));
                pic.set_visible(true);
                banner.remove_css_class("machine-banner-placeholder");
                last_stamp.set(stamp);
            }
        }
        gtk::glib::ControlFlow::Continue
    });
}

fn button_with_icon_label(icon: &str, label: &str) -> gtk::Button {
    let content = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    content.set_halign(gtk::Align::Center);
    content.set_valign(gtk::Align::Center);
    let image = gtk::Image::from_icon_name(icon);
    image.set_pixel_size(14);
    let text = gtk::Label::new(Some(label));
    text.set_single_line_mode(true);
    text.set_wrap(false);
    text.set_ellipsize(gtk::pango::EllipsizeMode::End);
    content.append(&image);
    content.append(&text);
    let btn = gtk::Button::new();
    btn.add_css_class("machine-action-button");
    btn.set_child(Some(&content));
    btn
}

fn chip(text: &str) -> gtk::Box {
    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    pill.add_css_class("machine-chip");
    let lbl = gtk::Label::new(Some(text));
    lbl.add_css_class("caption-heading");
    lbl.set_single_line_mode(true);
    lbl.set_wrap(false);
    lbl.set_ellipsize(gtk::pango::EllipsizeMode::None);
    lbl.set_margin_start(8);
    lbl.set_margin_end(8);
    lbl.set_margin_top(3);
    lbl.set_margin_bottom(3);
    lbl.set_xalign(0.5);
    pill.append(&lbl);
    pill
}

fn tag_chip(name: &str, color_hex: &str) -> gtk::Box {
    let pill = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    pill.add_css_class("machine-tag-chip");
    pill.set_valign(gtk::Align::Center);

    let dot = color_dot(color_hex, 8);
    let lbl = gtk::Label::new(Some(name));
    lbl.add_css_class("caption");
    lbl.set_single_line_mode(true);
    lbl.set_margin_end(2);

    pill.append(&dot);
    pill.append(&lbl);
    pill
}

pub fn color_dot(color_hex: &str, size: i32) -> gtk::Box {
    let dot = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    dot.add_css_class("tag-color-dot");
    dot.set_size_request(size, size);
    dot.set_valign(gtk::Align::Center);
    dot.set_halign(gtk::Align::Center);

    let clean = color_hex.trim_start_matches('#');
    let class_name = if let Some(idx) = crate::linux::tag_store::PALETTE_HEX
        .iter()
        .position(|&h| h.eq_ignore_ascii_case(clean))
    {
        format!("palette-dot-{}", idx)
    } else {
        "palette-dot-0".to_string()
    };
    dot.add_css_class(&class_name);
    dot
}

fn install_machine_card_styles() {
    use std::sync::Once;

    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            r#"
            .machine-card {
              border-radius: 16px;
              border: 1px solid rgba(255, 255, 255, 0.08);
              background-color: var(--card-bg-color, rgba(255, 255, 255, 0.04));
              transition: all 180ms ease;
            }

            .machine-card:hover {
              border-color: rgba(255, 255, 255, 0.18);
              box-shadow: 0 4px 12px rgba(0, 0, 0, 0.22);
            }

            .machine-banner-clip,
            .machine-banner,
            .machine-banner-image,
            .machine-banner-scrim {
              border-radius: 14px;
            }

            .machine-banner {
              min-height: 90px;
              background-image: linear-gradient(
                135deg,
                rgba(53, 132, 228, 0.35),
                rgba(98, 54, 255, 0.20),
                rgba(0, 0, 0, 0.45)
              );
              border: 1px solid rgba(255, 255, 255, 0.10);
            }

            .machine-banner-image,
            .machine-banner picture {
              min-height: 90px;
            }

            .machine-banner-scrim {
              background-color: rgba(0, 0, 0, 0.28);
            }

            .machine-banner-title {
              color: #ffffff;
              font-weight: 700;
              font-size: 1.15rem;
            }

            .machine-banner-subtitle {
              color: rgba(255, 255, 255, 0.82);
              font-size: 0.85rem;
            }

            .machine-type-icon-tile {
              background-color: rgba(255, 255, 255, 0.16);
              border: 1px solid rgba(255, 255, 255, 0.22);
              border-radius: 10px;
              padding: 8px;
              color: #ffffff;
            }

            .machine-pin-tile {
              background-color: rgba(0, 0, 0, 0.45);
              border: 1px solid rgba(255, 255, 255, 0.22);
              border-radius: 8px;
              padding: 8px;
              color: #ffa348;
            }

            .machine-banner-tag-count {
              color: rgba(255, 255, 255, 0.75);
              font-size: 0.75rem;
              font-weight: 600;
            }

            .machine-summary-pill {
              border-radius: 999px;
              min-height: 0;
              min-width: 0;
              padding: 0;
            }

            button.machine-summary-pill-clear {
              min-height: 16px;
              min-width: 16px;
              padding: 0;
              margin-top: 4px;
              margin-bottom: 4px;
            }

            button.machine-summary-pill-clear image {
              -gtk-icon-size: 12px;
            }

            .machine-chip {
              background-color: rgba(255, 255, 255, 0.07);
              border: 1px solid rgba(255, 255, 255, 0.06);
              border-radius: 999px;
              min-width: 0;
            }

            .machine-chip-pinned {
              background-color: rgba(246, 97, 81, 0.18);
              border: 1px solid rgba(246, 97, 81, 0.35);
              color: #ffa348;
            }

            .machine-chip-active {
              background-color: rgba(53, 132, 228, 0.22);
              border: 1px solid rgba(53, 132, 228, 0.40);
              color: #78aeed;
            }

            .machine-badge-row {
              min-width: 0;
            }

            .machine-tags-row {
              margin-top: -2px;
              margin-bottom: 2px;
            }

            .machine-tag-chip {
              background-color: rgba(255, 255, 255, 0.07);
              border: 1px solid rgba(255, 255, 255, 0.10);
              border-radius: 999px;
              padding: 2px 8px;
            }

            .tag-color-dot {
              border-radius: 999px;
              min-width: 10px;
              min-height: 10px;
              border: 1px solid rgba(255, 255, 255, 0.35);
              box-shadow: 0 1px 2px rgba(0, 0, 0, 0.35);
            }

            .tag-palette-button {
              border-radius: 999px;
              padding: 4px;
              border: 2px solid transparent;
            }

            .tag-palette-button.tag-palette-selected {
              border-color: #ffffff;
            }

            .palette-dot-0 { background-color: #FF3B30; }
            .palette-dot-1 { background-color: #FF9500; }
            .palette-dot-2 { background-color: #FFCC00; }
            .palette-dot-3 { background-color: #34C759; }
            .palette-dot-4 { background-color: #00C7A6; }
            .palette-dot-5 { background-color: #30B0C7; }
            .palette-dot-6 { background-color: #007AFF; }
            .palette-dot-7 { background-color: #5957D6; }
            .palette-dot-8 { background-color: #AF52DE; }
            .palette-dot-9 { background-color: #FF2D55; }
            .palette-dot-10 { background-color: #A3855E; }
            .palette-dot-11 { background-color: #8E8E93; }

            .machine-actions-row {
              margin-top: 4px;
            }

            flowbox.machine-badge-chips > flowboxchild {
              padding: 0;
              margin: 0;
              background: none;
              border: none;
              box-shadow: none;
              min-height: 0;
              min-width: 0;
            }

            flowbox.machine-actions-row > flowboxchild {
              padding: 0;
              margin: 0;
              background: none;
              border: none;
              box-shadow: none;
              min-height: 0;
              min-width: 0;
            }

            flowbox.machine-actions-row > flowboxchild > button.machine-action-button {
              margin: 0;
            }

            button.machine-action-button {
              border-radius: 8px;
              padding: 2px 8px;
              font-weight: 600;
              font-size: 13px;
              min-height: 26px;
              min-width: 0;
            }

            button.machine-action-button label {
              font-size: 13px;
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
    on_edit: Option<Rc<dyn Fn(MachineProfile)>>,
    on_open_terminal: Option<Rc<dyn Fn(String, super::terminal::TerminalLaunch)>>,
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
    let on_edit_r = on_edit.clone();
    let on_open_term_r = on_open_terminal.clone();
    start_btn.connect_clicked(move |_| {
        let terminal_cmd = {
            let app = state_r.borrow();
            app.store
                .profile(&mid)
                .and_then(super::terminal::terminal_launch)
        };
        if let Some(launch) = terminal_cmd {
            let launch_window: Rc<dyn Fn()> = Rc::new({
                let parent = parent_r.clone();
                let sessions = sessions_r.clone();
                let state = state_r.clone();
                let shell = shell_r.clone();
                let on_edit = on_edit_r.clone();
                let on_open_term = on_open_term_r.clone();
                let mid = mid.clone();
                let mname = mname.clone();
                let launch = launch.clone();
                move || {
                    let launched = super::terminal::open_launched(&parent, &launch, &mname);
                    match launched {
                        Ok(child) => {
                            wlog!("UI", "Launched '{}' pid={}", mname, child.id());
                            sessions.borrow_mut().insert(mid.clone(), child);
                            let mut app = state.borrow_mut();
                            let _ = app.store.set_active(Some(mid.clone()));
                            drop(app);
                            rebuild_home(RebuildHome {
                                shell: &shell,
                                state: &state,
                                parent: &parent,
                                sessions: sessions.clone(),
                                layout,
                                on_edit: on_edit.clone(),
                                on_open_terminal: on_open_term.clone(),
                            });
                        }
                        Err(e) => show_warning(&parent, &e),
                    }
                }
            });

            let behavior = state_r.borrow().settings.start_behavior.clone();
            match behavior.as_str() {
                "tab" | "newTab" => {
                    if let Some(open_term) = on_open_term_r.as_ref() {
                        open_term(mid.clone(), launch.clone());
                    } else {
                        launch_window();
                    }
                    return;
                }
                "window" | "newWindow" => {
                    launch_window();
                    return;
                }
                _ => {
                    let dialog = adw::MessageDialog::new(
                        Some(&parent_r),
                        Some(&format!("Start {}", mname)),
                        Some("Open in a new window or a new tab?"),
                    );
                    dialog.add_response("tab", "New Tab");
                    dialog.add_response("window", "New Window");
                    dialog.add_response("cancel", "Cancel");
                    dialog.set_response_appearance("tab", adw::ResponseAppearance::Suggested);
                    dialog.set_default_response(Some("tab"));
                    dialog.set_close_response("cancel");

                    let open_term_c = on_open_term_r.clone();
                    let mid_c = mid.clone();
                    let launch_c = launch.clone();
                    let launch_win_c = launch_window.clone();

                    dialog.connect_response(None, move |d, response| {
                        match response {
                            "tab" => {
                                if let Some(open_term) = open_term_c.as_ref() {
                                    open_term(mid_c.clone(), launch_c.clone());
                                } else {
                                    launch_win_c();
                                }
                            }
                            "window" => {
                                launch_win_c();
                            }
                            _ => {}
                        }
                        d.close();
                    });
                    dialog.present();
                    return;
                }
            }
        }

        let launched = try_launch_profile(&mid, &state_r);
        match launched {
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
                    on_edit: on_edit_r.clone(),
                    on_open_terminal: on_open_term_r.clone(),
                });
            }
            Err(e) => show_warning(&parent_r, &e),
        }
    });

    let mid = profile.id.clone();
    let shell_f = shell.clone();
    let state_f = state.clone();
    let parent_f = parent.clone();
    let sessions_f = sessions.clone();
    let on_edit_f = on_edit.clone();
    let on_open_term_f = on_open_terminal.clone();
    focus_btn.connect_clicked(move |_| {
        let terminal_cmd = {
            let app = state_f.borrow();
            app.store
                .profile(&mid)
                .and_then(super::terminal::terminal_launch)
        };
        if let Some(launch) = terminal_cmd {
            if let Some(open_term) = on_open_term_f.as_ref() {
                open_term(mid.clone(), launch);
                return;
            }
        }
        let mut app = state_f.borrow_mut();
        let _ = app.store.set_active(Some(mid.clone()));
        drop(app);
        rebuild_home(RebuildHome {
            shell: &shell_f,
            state: &state_f,
            parent: &parent_f,
            sessions: sessions_f.clone(),
            layout,
            on_edit: on_edit_f.clone(),
            on_open_terminal: on_open_term_f.clone(),
        });
    });

    let mid = profile.id.clone();
    let shell_s = shell.clone();
    let state_s = state.clone();
    let parent_s = parent.clone();
    let sessions_s = sessions.clone();
    let on_edit_s = on_edit.clone();
    let on_open_term_s = on_open_terminal.clone();
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
            on_edit: on_edit_s.clone(),
            on_open_terminal: on_open_term_s.clone(),
        });
    });

    let existing = profile.clone();
    let state_e = state.clone();
    let parent_e = parent.clone();
    let shell_e = shell.clone();
    let sessions_e = sessions.clone();
    let on_edit_e = on_edit.clone();
    edit_btn.connect_clicked(move |_| {
        if let Some(cb) = on_edit_e.as_ref() {
            cb(existing.clone());
        } else {
            editor::show_editor(
                &parent_e,
                &state_e,
                Some(existing.clone()),
                existing.machine_type,
                &shell_e,
                sessions_e.clone(),
                layout,
                None,
            );
        }
    });

    let mid = profile.id.clone();
    let state_d = state.clone();
    let parent_d = parent.clone();
    let shell_d = shell.clone();
    let sessions_d = sessions.clone();
    let on_edit_d = on_edit.clone();
    let on_open_term_d = on_open_terminal.clone();
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
            on_edit: on_edit_d.clone(),
            on_open_terminal: on_open_term_d.clone(),
        });
    });

    // Right-click / long-press context menu
    let popover = gtk::Popover::new();
    popover.set_parent(&card.root);
    popover.set_has_arrow(true);

    let menu_box = gtk::Box::new(gtk::Orientation::Vertical, 4);
    menu_box.set_margin_start(6);
    menu_box.set_margin_end(6);
    menu_box.set_margin_top(6);
    menu_box.set_margin_bottom(6);

    let is_fav = profile.favorite;
    let pin_label = if is_fav { "Unpin Machine" } else { "Pin Machine" };
    let pin_item = popover_menu_button("view-pin-symbolic", pin_label, false);
    if is_fav {
        if let Some(content) = pin_item.child().and_then(|c| c.downcast::<gtk::Box>().ok()) {
            if let Some(img) = content.first_child().and_then(|c| c.downcast::<gtk::Image>().ok()) {
                img.add_css_class("wwn-icon-orange");
            }
        }
    }
    let mid_pin = profile.id.clone();
    let state_pin = state.clone();
    let parent_pin = parent.clone();
    let shell_pin = shell.clone();
    let sessions_pin = sessions.clone();
    let on_edit_pin = on_edit.clone();
    let on_open_term_pin = on_open_terminal.clone();
    let popover_pin = popover.clone();
    pin_item.connect_clicked(move |_| {
        popover_pin.popdown();
        let mut app = state_pin.borrow_mut();
        if let Some(mut p) = app.store.profile(&mid_pin).cloned() {
            p.favorite = !is_fav;
            let _ = app.store.upsert(p);
        }
        drop(app);
        rebuild_home(RebuildHome {
            shell: &shell_pin,
            state: &state_pin,
            parent: &parent_pin,
            sessions: sessions_pin.clone(),
            layout,
            on_edit: on_edit_pin.clone(),
            on_open_terminal: on_open_term_pin.clone(),
        });
    });
    menu_box.append(&pin_item);

    // TAGS section
    menu_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));

    let tags_header = gtk::Label::new(Some("TAGS"));
    tags_header.add_css_class("dim-label");
    tags_header.add_css_class("caption");
    tags_header.set_xalign(0.0);
    tags_header.set_margin_start(8);
    tags_header.set_margin_top(4);
    tags_header.set_margin_bottom(2);
    menu_box.append(&tags_header);

    let all_tags = state.borrow().tags.tags.clone();
    for tag in all_tags {
        let is_assigned = state.borrow().tags.is_assigned(&tag.id, &profile.id);
        let tag_btn = tag_menu_item(&tag, is_assigned);

        let tag_id = tag.id.clone();
        let mid_tag = profile.id.clone();
        let state_tag = state.clone();
        let parent_tag = parent.clone();
        let shell_tag = shell.clone();
        let sessions_tag = sessions.clone();
        let on_edit_tag = on_edit.clone();
        let on_open_term_tag = on_open_terminal.clone();
        let popover_tag = popover.clone();
        tag_btn.connect_clicked(move |_| {
            popover_tag.popdown();
            {
                let mut app = state_tag.borrow_mut();
                app.tags.toggle_assignment(&tag_id, &mid_tag);
                app.persist_tags();
            }
            rebuild_home(RebuildHome {
                shell: &shell_tag,
                state: &state_tag,
                parent: &parent_tag,
                sessions: sessions_tag.clone(),
                layout,
                on_edit: on_edit_tag.clone(),
                on_open_terminal: on_open_term_tag.clone(),
            });
        });
        menu_box.append(&tag_btn);
    }

    let new_tag_btn = popover_menu_button("list-add-symbolic", "New Tag...", false);
    let mid_newtag = profile.id.clone();
    let state_newtag = state.clone();
    let parent_newtag = parent.clone();
    let shell_newtag = shell.clone();
    let sessions_newtag = sessions.clone();
    let on_edit_newtag = on_edit.clone();
    let on_open_term_newtag = on_open_terminal.clone();
    let popover_newtag = popover.clone();
    new_tag_btn.connect_clicked(move |_| {
        popover_newtag.popdown();
        let parent_c = parent_newtag.clone();
        let state_c = state_newtag.clone();
        let shell_c = shell_newtag.clone();
        let sessions_c = sessions_newtag.clone();
        let on_edit_c = on_edit_newtag.clone();
        let on_open_term_c = on_open_term_newtag.clone();
        let on_rebuild_fn = Rc::new(move || {
            rebuild_home(RebuildHome {
                shell: &shell_c,
                state: &state_c,
                parent: &parent_c,
                sessions: sessions_c.clone(),
                layout,
                on_edit: on_edit_c.clone(),
                on_open_terminal: on_open_term_c.clone(),
            });
        });
        show_new_tag_dialog(
            &parent_newtag,
            Some(&mid_newtag),
            state_newtag.clone(),
            on_rebuild_fn,
        );
    });
    menu_box.append(&new_tag_btn);

    menu_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));

    let edit_item = popover_menu_button("emblem-system-symbolic", "Edit Profile", false);
    let existing_c = profile.clone();
    let parent_edit = parent.clone();
    let state_edit = state.clone();
    let shell_edit = shell.clone();
    let sessions_edit = sessions.clone();
    let on_edit_item = on_edit.clone();
    let popover_edit = popover.clone();
    edit_item.connect_clicked(move |_| {
        popover_edit.popdown();
        if let Some(cb) = on_edit_item.as_ref() {
            cb(existing_c.clone());
        } else {
            editor::show_editor(
                &parent_edit,
                &state_edit,
                Some(existing_c.clone()),
                existing_c.machine_type,
                &shell_edit,
                sessions_edit.clone(),
                layout,
                None,
            );
        }
    });
    menu_box.append(&edit_item);

    let dup_item = popover_menu_button("edit-copy-symbolic", "Duplicate Machine", false);
    let profile_dup = profile.clone();
    let state_dup = state.clone();
    let parent_dup = parent.clone();
    let shell_dup = shell.clone();
    let sessions_dup = sessions.clone();
    let on_edit_dup = on_edit.clone();
    let on_open_term_dup = on_open_terminal.clone();
    let popover_dup = popover.clone();
    dup_item.connect_clicked(move |_| {
        popover_dup.popdown();
        let mut new_p = profile_dup.clone();
        new_p.id = crate::domain::machine_profile::new_uuid();
        new_p.name = format!("{} (Copy)", profile_dup.name);
        let mut app = state_dup.borrow_mut();
        let _ = app.store.upsert(new_p);
        drop(app);
        rebuild_home(RebuildHome {
            shell: &shell_dup,
            state: &state_dup,
            parent: &parent_dup,
            sessions: sessions_dup.clone(),
            layout,
            on_edit: on_edit_dup.clone(),
            on_open_terminal: on_open_term_dup.clone(),
        });
    });
    menu_box.append(&dup_item);

    menu_box.append(&gtk::Separator::new(gtk::Orientation::Horizontal));

    let (running, _) = machine_session_status(&profile.id, &sessions);
    let del_item = popover_menu_button("user-trash-symbolic", "Delete Machine", true);
    if running {
        del_item.set_sensitive(false);
    } else {
        let mid_del = profile.id.clone();
        let state_del = state.clone();
        let parent_del = parent.clone();
        let shell_del = shell.clone();
        let sessions_del = sessions.clone();
        let on_edit_del = on_edit.clone();
        let on_open_term_del = on_open_terminal.clone();
        let popover_del = popover.clone();
        del_item.connect_clicked(move |_| {
            popover_del.popdown();
            let mut app = state_del.borrow_mut();
            let _ = app.store.delete(&mid_del);
            drop(app);
            rebuild_home(RebuildHome {
                shell: &shell_del,
                state: &state_del,
                parent: &parent_del,
                sessions: sessions_del.clone(),
                layout,
                on_edit: on_edit_del.clone(),
                on_open_terminal: on_open_term_del.clone(),
            });
        });
    }
    menu_box.append(&del_item);

    popover.set_child(Some(&menu_box));

    let right_click = gtk::GestureClick::new();
    right_click.set_button(3);
    right_click.set_propagation_phase(gtk::PropagationPhase::Capture);
    let popover_rc = popover.clone();
    right_click.connect_pressed(move |_, _, x, y| {
        let rect = gtk::gdk::Rectangle::new(x as i32, y as i32, 1, 1);
        popover_rc.set_pointing_to(Some(&rect));
        popover_rc.popup();
    });
    card.root.add_controller(right_click);

    // Context menu:
    // 1. Right-click for mouse / KBM input.
    // 2. Touch-only long press (tap-and-hold) for touchscreen input.
    // Mouse click-and-hold is explicitly ignored so click-and-drag or deliberate clicks never trigger it.
    let long_press = gtk::GestureLongPress::new();
    long_press.set_touch_only(true);
    let popover_lp = popover.clone();
    long_press.connect_pressed(move |gesture, x, y| {
        if let Some(dev) = gesture.current_event_device() {
            if dev.source() != gtk::gdk::InputSource::Touchscreen {
                return;
            }
        }
        let rect = gtk::gdk::Rectangle::new(x as i32, y as i32, 1, 1);
        popover_lp.set_pointing_to(Some(&rect));
        popover_lp.popup();
    });
    card.root.add_controller(long_press);
}

fn popover_menu_button(icon: &str, label: &str, is_destructive: bool) -> gtk::Button {
    let content = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    content.set_margin_start(8);
    content.set_margin_end(8);
    content.set_margin_top(4);
    content.set_margin_bottom(4);
    let image = gtk::Image::from_icon_name(icon);
    image.set_pixel_size(16);
    if is_destructive {
        image.add_css_class("destructive-action");
    }
    let text = gtk::Label::new(Some(label));
    text.set_xalign(0.0);
    text.set_hexpand(true);
    if is_destructive {
        text.add_css_class("destructive-action");
    }
    content.append(&image);
    content.append(&text);
    let btn = gtk::Button::new();
    btn.add_css_class("flat");
    btn.set_child(Some(&content));
    btn
}

fn tag_menu_item(tag: &crate::linux::tag_store::MachineTag, is_assigned: bool) -> gtk::Button {
    let btn = gtk::Button::new();
    btn.add_css_class("flat");

    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    row.set_margin_start(8);
    row.set_margin_end(8);
    row.set_margin_top(4);
    row.set_margin_bottom(4);

    let check = gtk::Image::from_icon_name("object-select-symbolic");
    check.set_pixel_size(14);
    if !is_assigned {
        check.set_opacity(0.0);
    }
    row.append(&check);

    let dot = color_dot(&tag.color_hex, 10);
    row.append(&dot);

    let lbl = gtk::Label::new(Some(&tag.name));
    lbl.set_xalign(0.0);
    lbl.set_hexpand(true);
    row.append(&lbl);

    btn.set_child(Some(&row));
    btn
}

pub fn show_new_tag_dialog(
    parent: &adw::ApplicationWindow,
    machine_id: Option<&str>,
    state: SharedAppState,
    on_rebuild: Rc<dyn Fn()>,
) {
    let dialog = adw::MessageDialog::new(
        Some(parent),
        Some("New Tag"),
        Some(if machine_id.is_some() {
            "Create a tag and assign it to this machine."
        } else {
            "Create a new machine tag."
        }),
    );
    dialog.add_response("cancel", "Cancel");
    dialog.add_response("create", "Create Tag");
    dialog.set_response_appearance("create", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("create"));
    dialog.set_close_response("cancel");

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 12);
    vbox.set_margin_top(8);
    vbox.set_margin_bottom(8);

    let entry_group = adw::PreferencesGroup::new();
    let name_entry = adw::EntryRow::new();
    name_entry.set_title("Tag Name");
    entry_group.add(&name_entry);
    vbox.append(&entry_group);

    let color_lbl = gtk::Label::new(Some("Color"));
    color_lbl.add_css_class("dim-label");
    color_lbl.add_css_class("caption");
    color_lbl.set_xalign(0.0);
    vbox.append(&color_lbl);

    let palette_grid = gtk::Grid::new();
    palette_grid.set_column_spacing(8);
    palette_grid.set_row_spacing(8);
    palette_grid.set_halign(gtk::Align::Center);

    let selected_color = Rc::new(RefCell::new(
        crate::linux::tag_store::PALETTE_HEX[6].to_string(),
    ));

    let buttons = Rc::new(RefCell::new(Vec::<gtk::Button>::new()));

    for (i, &hex) in crate::linux::tag_store::PALETTE_HEX.iter().enumerate() {
        let btn = gtk::Button::new();
        btn.add_css_class("flat");
        btn.add_css_class("tag-palette-button");
        if i == 6 {
            btn.add_css_class("tag-palette-selected");
        }

        let dot = color_dot(hex, 20);
        btn.set_child(Some(&dot));

        let sel_c = selected_color.clone();
        let hex_str = hex.to_string();
        let btns_c = buttons.clone();
        let btn_self = btn.clone();

        btn.connect_clicked(move |_| {
            *sel_c.borrow_mut() = hex_str.clone();
            for b in btns_c.borrow().iter() {
                b.remove_css_class("tag-palette-selected");
            }
            btn_self.add_css_class("tag-palette-selected");
        });

        buttons.borrow_mut().push(btn.clone());
        let col = (i as i32) % 6;
        let row = (i as i32) / 6;
        palette_grid.attach(&btn, col, row, 1, 1);
    }

    vbox.append(&palette_grid);
    dialog.set_extra_child(Some(&vbox));

    let mid = machine_id.map(|s| s.to_string());
    dialog.connect_response(None, move |d, response| {
        if response == "create" {
            let name = name_entry.text().trim().to_string();
            if !name.is_empty() {
                let color = selected_color.borrow().clone();
                {
                    let mut app = state.borrow_mut();
                    let new_tag = app.tags.create_tag(&name, &color);
                    if let Some(ref m) = mid {
                        app.tags.set_assigned(true, &new_tag.id, m);
                    }
                    app.persist_tags();
                }
                on_rebuild();
            }
        }
        d.close();
    });

    dialog.present();
}

pub fn show_edit_tag_dialog(
    parent: &adw::ApplicationWindow,
    tag: &crate::linux::tag_store::MachineTag,
    state: SharedAppState,
    on_rebuild: Rc<dyn Fn()>,
) {
    let dialog = adw::MessageDialog::new(
        Some(parent),
        Some("Edit Tag"),
        Some("Change the tag name and color."),
    );
    dialog.add_response("cancel", "Cancel");
    dialog.add_response("save", "Save");
    dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("save"));
    dialog.set_close_response("cancel");

    let vbox = gtk::Box::new(gtk::Orientation::Vertical, 12);
    vbox.set_margin_top(8);
    vbox.set_margin_bottom(8);

    let entry_group = adw::PreferencesGroup::new();
    let name_entry = adw::EntryRow::new();
    name_entry.set_title("Tag Name");
    name_entry.set_text(&tag.name);
    entry_group.add(&name_entry);
    vbox.append(&entry_group);

    let color_lbl = gtk::Label::new(Some("Color"));
    color_lbl.add_css_class("dim-label");
    color_lbl.add_css_class("caption");
    color_lbl.set_xalign(0.0);
    vbox.append(&color_lbl);

    let palette_grid = gtk::Grid::new();
    palette_grid.set_column_spacing(8);
    palette_grid.set_row_spacing(8);
    palette_grid.set_halign(gtk::Align::Center);

    let selected_color = Rc::new(RefCell::new(tag.color_hex.clone()));
    let buttons = Rc::new(RefCell::new(Vec::<gtk::Button>::new()));

    for (i, &hex) in crate::linux::tag_store::PALETTE_HEX.iter().enumerate() {
        let btn = gtk::Button::new();
        btn.add_css_class("flat");
        btn.add_css_class("tag-palette-button");
        if hex.eq_ignore_ascii_case(&tag.color_hex) {
            btn.add_css_class("tag-palette-selected");
        }

        let dot = color_dot(hex, 20);
        btn.set_child(Some(&dot));

        let sel_c = selected_color.clone();
        let hex_str = hex.to_string();
        let btns_c = buttons.clone();
        let btn_self = btn.clone();

        btn.connect_clicked(move |_| {
            *sel_c.borrow_mut() = hex_str.clone();
            for b in btns_c.borrow().iter() {
                b.remove_css_class("tag-palette-selected");
            }
            btn_self.add_css_class("tag-palette-selected");
        });

        buttons.borrow_mut().push(btn.clone());
        let col = (i as i32) % 6;
        let row = (i as i32) / 6;
        palette_grid.attach(&btn, col, row, 1, 1);
    }

    vbox.append(&palette_grid);
    dialog.set_extra_child(Some(&vbox));

    let tag_id = tag.id.clone();
    dialog.connect_response(None, move |d, response| {
        if response == "save" {
            let name = name_entry.text().trim().to_string();
            if !name.is_empty() {
                let color = selected_color.borrow().clone();
                {
                    let mut app = state.borrow_mut();
                    app.tags.update_tag(crate::linux::tag_store::MachineTag {
                        id: tag_id.clone(),
                        name,
                        color_hex: color,
                    });
                    app.persist_tags();
                }
                on_rebuild();
            }
        }
        d.close();
    });

    dialog.present();
}

impl Clone for HomeShell {
    fn clone(&self) -> Self {
        Self {
            root: self.root.clone(),
            banner: self.banner.clone(),
            continue_btn: self.continue_btn.clone(),
            search: self.search.clone(),
            summary: self.summary.clone(),
            flow: self.flow.clone(),
            query: self.query.clone(),
            selected_tag_id: self.selected_tag_id.clone(),
            on_rebuild: self.on_rebuild.clone(),
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
        wlog!(
            "UI",
            "Stopping machine id={} pid={}",
            machine_id,
            child.id()
        );
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
    if let Some(core) = crate::linux::embedded_core::get() {
        core.set_fills_host_for_client_launch(crate::linux::bundled_clients::fills_host(
            &profile.effective_command(),
        ));
    }
    launcher::launch_profile(&profile, &settings, &rt).map_err(|e| format!("{e}"))
}

fn show_warning(_parent: &adw::ApplicationWindow, message: &str) {
    let msg = if message.contains("runtime") || message.contains("XDG") {
        "Wawona compositor is not running. Launch the app (embedded compositor) or start the host from Settings -> Diagnostics."
    } else {
        message
    };
    wlog!("UI", "Warning: {}", msg);
}

/// First-launch welcome. Same copy as Apple/Android (`wawona-welcome-alert`).
pub fn maybe_show_welcome(shell: &HomeShell, state: &SharedAppState) {
    let needs = {
        let app = state.borrow();
        !app.settings.has_seen_welcome && app.store.profiles.is_empty()
    };
    if !needs {
        shell.banner.set_visible(false);
        return;
    }

    shell.banner.set_visible(true);
    let state_c = state.clone();
    let banner_c = shell.banner.clone();
    shell.continue_btn.connect_clicked(move |_| {
        {
            let mut app = state_c.borrow_mut();
            app.settings.has_seen_welcome = true;
            app.persist_settings();
        }
        banner_c.set_visible(false);
    });
}
