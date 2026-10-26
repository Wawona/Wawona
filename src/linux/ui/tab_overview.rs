//! Safari-style Tab Overview for the Linux GTK host.
//! Design contract: mirrors `WWNTabOverviewView` (SwiftUI) and `WatchTabOverviewList`.
//!
//! Parity with SwiftUI:
//!  - Count row: icon + bold count label, left-aligned
//!  - Adaptive FlowBox: 1 col (<480px), 2 cols (480-899px), 3 cols (>=900px)
//!  - Card header: small type-icon + title (ellipsized) + circular dark xmark close
//!  - Card body (preview well): click to focus (no separate Focus button)
//!  - Active card: accent-color 2.5px border + accent icon
//!  - Status: "Running · Active" or "Running"
//!  - Empty state: window-symbolic icon
//!  - Escape key + Done button both dismiss

use std::rc::Rc;

use adw::prelude::*;
use gtk::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::domain::tab_overview;
use crate::linux::machine_profile::MachineProfile;
use crate::linux::ui::a11y;
use crate::linux::ui::home::{HomeShell, MachineSessions};
use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;

// ---------------------------------------------------------------------------
// CSS (installed once per process)
// ---------------------------------------------------------------------------

fn install_tab_overview_styles() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            r#"
            .wwn-tab-card {
              border-radius: 16px;
              border: 1.0px solid rgba(127, 127, 127, 0.18);
              background-color: rgba(127, 127, 127, 0.06);
              transition: border-color 160ms ease, box-shadow 160ms ease;
            }
            .wwn-tab-card:hover {
              border-color: rgba(127, 127, 127, 0.30);
              box-shadow: 0 4px 14px rgba(0, 0, 0, 0.18);
            }
            .wwn-tab-card-active {
              border-radius: 16px;
              border: 2.5px solid var(--accent-bg-color);
              background-color: rgba(127, 127, 127, 0.06);
              transition: border-color 160ms ease, box-shadow 160ms ease;
            }
            .wwn-tab-card-active:hover {
              box-shadow: 0 4px 18px rgba(0, 0, 0, 0.22);
            }
            .wwn-tab-preview {
              border-radius: 10px;
              background-image: linear-gradient(
                135deg,
                rgba(60, 120, 220, 0.18),
                rgba(80, 40, 200, 0.12),
                rgba(0, 0, 0, 0.30)
              );
              border: 1px solid rgba(127, 127, 127, 0.10);
            }
            .wwn-tab-preview:hover {
              background-image: linear-gradient(
                135deg,
                rgba(70, 140, 250, 0.24),
                rgba(90, 50, 220, 0.18),
                rgba(0, 0, 0, 0.32)
              );
            }
            .wwn-tab-close {
              border-radius: 100px;
              min-width:  22px;
              min-height: 22px;
              padding: 0;
              background-color: rgba(0, 0, 0, 0.42);
              color: rgba(255, 255, 255, 0.90);
              transition: background-color 120ms ease;
            }
            .wwn-tab-close:hover {
              background-color: rgba(0, 0, 0, 0.62);
            }
            .wwn-tab-count-label {
              font-weight: 700;
              font-size: 1.05em;
            }
            .wwn-tab-status {
              font-size: 0.82em;
              font-weight: 500;
            }
            .wwn-tab-title {
              font-weight: 600;
              font-size: 0.88em;
            }
            .wwn-tab-thumbnail {
              border-radius: 10px;
            }
            flowboxchild {
              padding: 0;
              margin: 0;
              background: transparent;
              border-radius: 16px;
              outline: none;
            }
            flowboxchild:hover, flowboxchild:selected, flowboxchild:focus {
              background: transparent;
              outline: none;
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn icon_for_title(name: &str) -> &'static str {
    let lower = name.to_lowercase();
    if lower.contains("term") || lower.contains("zsh") || lower.contains("shell") {
        "utilities-terminal-symbolic"
    } else if lower.contains("niri") {
        "view-paged-symbolic"
    } else if lower.contains("weston") {
        "window-symbolic"
    } else if lower.contains("wayland") {
        "video-display-symbolic"
    } else {
        "computer-symbolic"
    }
}

fn status_label(is_active: bool) -> &'static str {
    if is_active {
        "Running \u{00b7} Active"
    } else {
        "Running"
    }
}

fn cols_for_width(width: i32) -> u32 {
    if width >= 900 {
        3
    } else if width >= 480 {
        2
    } else {
        1
    }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Build the Tab Overview view embedded in the main app content stack.
pub fn build_tab_overview_view(
    state: &SharedAppState,
    sessions: MachineSessions,
    on_select: Rc<dyn Fn(String)>,
    on_close: Rc<dyn Fn()>,
) -> gtk::Box {
    install_tab_overview_styles();

    // Header bar
    let header = adw::HeaderBar::new();
    header.set_show_end_title_buttons(true);
    header.set_show_start_title_buttons(true);
    let title = gtk::Label::new(Some("Tab Overview"));
    title.add_css_class("title");
    header.set_title_widget(Some(&title));

    let back_btn = gtk::Button::from_icon_name("go-previous-symbolic");
    back_btn.set_tooltip_text(Some("Back to Machines (Escape)"));
    a11y::set_wwn_a11y(&back_btn, "wwn.tabOverview.back", Some("Back"));
    {
        let on_close_c = on_close.clone();
        back_btn.connect_clicked(move |_| on_close_c());
    }
    header.pack_start(&back_btn);

    let done_btn = gtk::Button::with_label("Done");
    done_btn.add_css_class("suggested-action");
    done_btn.set_tooltip_text(Some("Return to Machines (Escape)"));
    a11y::set_wwn_a11y(&done_btn, "wwn.tabOverview.done", Some("Done"));
    {
        let on_close_c = on_close.clone();
        done_btn.connect_clicked(move |_| on_close_c());
    }
    header.pack_end(&done_btn);

    // Same search placement as Machine Configuration. Tab Overview has no
    // add action, so only the search field moves.
    let search_chrome =
        super::adaptive::AdaptiveSearchAdd::new(super::adaptive::SearchAddOptions {
            placeholder: "Search Tabs",
            search_a11y: "wwn.tabOverview.search",
            search_label: "Search Tabs",
            add_tooltip: None,
            add_a11y: None,
            add_label: None,
        });
    search_chrome.pack_header(&header);
    let search = search_chrome.header_search.clone();
    search_chrome.bind_query(std::rc::Rc::new(|_| {}));

    // Count row
    let count_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    count_row.set_margin_start(20);
    count_row.set_margin_end(20);
    count_row.set_margin_top(8);
    count_row.set_margin_bottom(4);
    let count_icon = gtk::Image::from_icon_name("view-grid-symbolic");
    count_icon.set_pixel_size(15);
    count_row.append(&count_icon);
    let count_lbl = gtk::Label::new(None);
    count_lbl.add_css_class("wwn-tab-count-label");
    count_lbl.set_xalign(0.0);
    count_row.append(&count_lbl);

    // Grid container
    let grid_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    grid_box.set_hexpand(true);
    grid_box.set_vexpand(true);

    let grid_clamp = adw::Clamp::builder()
        .maximum_size(1100)
        .tightening_threshold(750)
        .child(&grid_box)
        .build();

    let scroller = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .min_content_width(0)
        .min_content_height(0)
        .propagate_natural_width(false)
        .hscrollbar_policy(gtk::PolicyType::Never)
        .child(&grid_clamp)
        .build();

    // Empty state
    let empty = adw::StatusPage::builder()
        .icon_name("window-symbolic")
        .title("No Active Tabs")
        .description("Start a machine, then open Tab Overview to switch sessions.")
        .vexpand(true)
        .build();
    a11y::set_wwn_a11y(&empty, "wwn.tabOverview.empty", Some("No Active Tabs"));

    // Content stack
    let content_stack = gtk::Stack::new();
    content_stack.set_transition_type(gtk::StackTransitionType::Crossfade);
    content_stack.set_transition_duration(180);
    content_stack.set_hhomogeneous(false);
    content_stack.set_vhomogeneous(false);
    content_stack.add_named(&scroller, Some("grid"));
    content_stack.add_named(&empty, Some("empty"));

    // Body
    let count_clamp = adw::Clamp::builder()
        .maximum_size(1100)
        .tightening_threshold(750)
        .child(&count_row)
        .build();

    let body = gtk::Box::new(gtk::Orientation::Vertical, 0);
    body.append(&count_clamp);
    body.append(&content_stack);
    body.set_margin_top(4);

    // Root with Escape key
    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    {
        let esc_ctrl = gtk::EventControllerKey::new();
        let on_close_k = on_close.clone();
        esc_ctrl.connect_key_pressed(move |_, keyval, _, _| {
            if keyval == gtk::gdk::Key::Escape {
                on_close_k();
                gtk::glib::Propagation::Stop
            } else {
                gtk::glib::Propagation::Proceed
            }
        });
        root.add_controller(esc_ctrl);
    }
    root.append(&header);
    root.append(&search_chrome.revealer);
    root.append(&body);
    root.append(&search_chrome.bottom_bar);

    {
        let chrome = search_chrome;
        let is_touch = super::adaptive::is_touchscreen_active();
        let last_state = std::rc::Rc::new(std::cell::Cell::new(None::<(bool, bool)>));
        root.add_tick_callback(move |widget, _| {
            let w = widget.width();
            if w <= 0 {
                return gtk::glib::ControlFlow::Continue;
            }
            let is_compact = w < crate::linux::ui_model::SPLIT_COLLAPSE_BELOW_PX;
            if last_state.get() == Some((is_touch, is_compact)) {
                return gtk::glib::ControlFlow::Continue;
            }
            last_state.set(Some((is_touch, is_compact)));
            chrome.apply(true, is_touch, w);
            gtk::glib::ControlFlow::Continue
        });
    }

    // Rebuild slot
    let rebuild_slot: Rc<std::cell::RefCell<Option<Rc<dyn Fn()>>>> =
        Rc::new(std::cell::RefCell::new(None));
    let rebuild_slot_c = rebuild_slot.clone();

    let rebuild: Rc<dyn Fn()> = Rc::new({
        let grid_box = grid_box.clone();
        let content_stack = content_stack.clone();
        let empty = empty.clone();
        let count_lbl = count_lbl.clone();
        let count_row = count_row.clone();
        let search = search.clone();
        let state = state.clone();
        let sessions = sessions.clone();
        let on_select = on_select.clone();

        move || {
            while let Some(child) = grid_box.first_child() {
                grid_box.remove(&child);
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
            if n == 0 {
                count_row.set_visible(false);
                content_stack.set_visible_child_name("empty");
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

            count_row.set_visible(true);
            count_lbl.set_text(&if n == 1 {
                "1 Tab".to_string()
            } else {
                format!("{n} Tabs")
            });
            content_stack.set_visible_child_name("grid");

            let avail_w = grid_box.allocated_width();
            let cols = if avail_w > 0 {
                cols_for_width(avail_w)
            } else {
                1
            };

            let flow = gtk::FlowBox::new();
            flow.set_orientation(gtk::Orientation::Horizontal);
            flow.set_column_spacing(16);
            flow.set_row_spacing(16);
            flow.set_max_children_per_line(cols);
            flow.set_min_children_per_line(1);
            flow.set_homogeneous(true);
            flow.set_selection_mode(gtk::SelectionMode::None);
            flow.set_hexpand(true);
            flow.set_halign(gtk::Align::Fill);
            flow.set_margin_start(16);
            flow.set_margin_end(16);
            flow.set_margin_top(8);
            flow.set_margin_bottom(24);
            a11y::set_wwn_a11y(&flow, "wwn.tabOverview.grid", Some("Tab Overview Grid"));

            for profile in &cards {
                let is_active = active.as_deref() == Some(profile.id.as_str());
                let card = build_card(
                    profile,
                    is_active,
                    &state,
                    &sessions,
                    on_select.clone(),
                    rebuild_slot_c.clone(),
                );
                flow.append(&card);
            }

            grid_box.append(&flow);
        }
    });

    *rebuild_slot.borrow_mut() = Some(rebuild.clone());
    {
        let rebuild = rebuild.clone();
        search.connect_search_changed(move |_| rebuild());
    }
    rebuild();

    root
}

// ---------------------------------------------------------------------------
// Individual card builder
// ---------------------------------------------------------------------------

fn build_card(
    profile: &MachineProfile,
    is_active: bool,
    state: &SharedAppState,
    sessions: &MachineSessions,
    on_select: Rc<dyn Fn(String)>,
    rebuild_slot: Rc<std::cell::RefCell<Option<Rc<dyn Fn()>>>>,
) -> gtk::Box {
    let icon_name = icon_for_title(&profile.name);
    let status_text = status_label(is_active);
    let display_title = if profile.name.trim().is_empty() {
        "Untitled".to_string()
    } else {
        profile.name.clone()
    };

    let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
    if is_active {
        card.add_css_class("wwn-tab-card-active");
    } else {
        card.add_css_class("wwn-tab-card");
    }
    card.set_size_request(160, -1);
    card.set_hexpand(true);
    card.set_halign(gtk::Align::Fill);
    a11y::set_wwn_a11y(
        &card,
        &format!("wwn.tabOverview.card.{}", profile.id),
        Some(&display_title),
    );

    // Card header: [icon] [title...] [xmark]
    let header_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    header_row.set_margin_start(10);
    header_row.set_margin_end(8);
    header_row.set_margin_top(8);
    header_row.set_margin_bottom(6);

    let type_icon = gtk::Image::from_icon_name(icon_name);
    type_icon.set_pixel_size(13);
    if is_active {
        type_icon.add_css_class("accent");
    } else {
        type_icon.add_css_class("dim-label");
    }
    header_row.append(&type_icon);

    let title_lbl = gtk::Label::new(Some(&display_title));
    title_lbl.add_css_class("wwn-tab-title");
    title_lbl.set_xalign(0.0);
    title_lbl.set_hexpand(true);
    title_lbl.set_ellipsize(gtk::pango::EllipsizeMode::End);
    title_lbl.set_max_width_chars(22);
    header_row.append(&title_lbl);

    let close_btn = gtk::Button::from_icon_name("window-close-symbolic");
    close_btn.add_css_class("flat");
    close_btn.add_css_class("wwn-tab-close");
    close_btn.set_tooltip_text(Some(&format!("Close {}", display_title)));
    a11y::set_wwn_a11y(
        &close_btn,
        "wwn.tabOverview.card.close",
        Some(&format!("Close {}", display_title)),
    );
    header_row.append(&close_btn);
    card.append(&header_row);

    // Preview well (tap to focus)
    let preview = gtk::Box::new(gtk::Orientation::Vertical, 0);
    preview.add_css_class("wwn-tab-preview");
    preview.set_height_request(130);
    preview.set_margin_start(6);
    preview.set_margin_end(6);
    preview.set_margin_bottom(6);
    preview.set_overflow(gtk::Overflow::Hidden);
    preview.set_cursor_from_name(Some("pointer"));

    let mut has_thumbnail = false;
    if let Ok(path) = crate::linux::thumbnail_store::thumbnail_path(&profile.id) {
        if path.is_file() {
            let pic = gtk::Picture::for_filename(&path);
            pic.set_can_shrink(true);
            pic.set_content_fit(gtk::ContentFit::Cover);
            pic.set_hexpand(true);
            pic.set_vexpand(true);
            pic.add_css_class("wwn-tab-thumbnail");
            preview.append(&pic);
            has_thumbnail = true;
        }
    }

    if !has_thumbnail {
        let center = gtk::Box::new(gtk::Orientation::Vertical, 8);
        center.set_valign(gtk::Align::Center);
        center.set_halign(gtk::Align::Center);
        center.set_hexpand(true);
        center.set_vexpand(true);

        let preview_icon = gtk::Image::from_icon_name(icon_name);
        preview_icon.set_pixel_size(30);
        preview_icon.add_css_class("dim-label");
        center.append(&preview_icon);

        let status_lbl = gtk::Label::new(Some(status_text));
        status_lbl.add_css_class("wwn-tab-status");
        status_lbl.add_css_class("dim-label");
        status_lbl.set_halign(gtk::Align::Center);
        status_lbl.set_ellipsize(gtk::pango::EllipsizeMode::End);
        center.append(&status_lbl);

        preview.append(&center);
    }

    card.append(&preview);

    // Tap preview to focus
    {
        let mid = profile.id.clone();
        let state_c = state.clone();
        let on_select_c = on_select.clone();
        let gesture = gtk::GestureClick::new();
        gesture.connect_pressed(move |_, _, _, _| {
            {
                let mut app = state_c.borrow_mut();
                let _ = app.store.set_active(Some(mid.clone()));
            }
            on_select_c(mid.clone());
        });
        preview.add_controller(gesture);
    }

    // Close button
    {
        let mid = profile.id.clone();
        let state_c = state.clone();
        let sessions_c = sessions.clone();
        close_btn.connect_clicked(move |_| {
            if let Some(mut child) = sessions_c.borrow_mut().remove(&mid) {
                let _ = child.kill();
            }
            {
                let mut app = state_c.borrow_mut();
                if app.store.active_machine_id.as_deref() == Some(&mid) {
                    let _ = app.store.set_active(None);
                }
            }
            if let Some(f) = rebuild_slot.borrow().as_ref() {
                f();
            }
        });
    }

    card
}

// ---------------------------------------------------------------------------
// show_tab_overview: no-op (in-app navigation stack)
// ---------------------------------------------------------------------------

/// Tab overview presenter.
/// Wawona Linux UI presents Tab Overview strictly in-app via the navigation stack.
pub fn show_tab_overview(
    _parent: &adw::ApplicationWindow,
    _state: &SharedAppState,
    _sessions: MachineSessions,
    _shell: &HomeShell,
    _layout: LayoutMode,
) {
    crate::wlog!(
        "UI",
        "Tab Overview: strictly in-app navigation stack (floating window eliminated)"
    );
}
