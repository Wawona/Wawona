//! Adaptive layout helpers (width-based breakpoint + clamp).

use std::cell::Cell;
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::ui_model::{
    sidebar_width_from_pointer, LayoutMode, SPLIT_COLLAPSE_BELOW_PX,
};

/// Live layout mode shared between widgets (updated when the window resizes).
#[derive(Clone)]
pub struct LayoutBinding {
    pub mode: Rc<Cell<LayoutMode>>,
}

impl LayoutBinding {
    pub fn new(initial: LayoutMode) -> Self {
        Self {
            mode: Rc::new(Cell::new(initial)),
        }
    }

    pub fn is_compact(&self) -> bool {
        self.mode.get().is_compact()
    }

    pub fn get(&self) -> LayoutMode {
        self.mode.get()
    }
}

fn apply_width(binding: &LayoutBinding, width: i32) {
    binding.mode.set(LayoutMode::for_width(width));
}

/// Track window width and toggle compact vs expanded at the canonical 600px breakpoint.
pub fn install_breakpoint(window: &adw::ApplicationWindow, binding: &LayoutBinding) {
    let binding_init = binding.clone();
    apply_width(&binding_init, window.default_width());

    let binding_notify = binding.clone();
    window.connect_default_width_notify(move |w| {
        apply_width(&binding_notify, w.default_width());
    });

    let binding_tick = binding.clone();
    let last_w = Rc::new(Cell::new(0));
    window.add_tick_callback(move |w, _| {
        let width = w.width();
        if width > 0 && width != last_w.get() {
            last_w.set(width);
            apply_width(&binding_tick, width);
        }
        gtk::glib::ControlFlow::Continue
    });
}

/// Install adaptive breakpoint on the application window that collapses the
/// split view when the window width drops below 760px.
pub fn install_adaptive_split_view(
    window: &adw::ApplicationWindow,
    split_view: &adw::OverlaySplitView,
    binding: &LayoutBinding,
) {
    let spec = format!("max-width: {SPLIT_COLLAPSE_BELOW_PX}px");
    if let Ok(cond) = adw::BreakpointCondition::parse(&spec) {
        let bp = adw::Breakpoint::new(cond);
        bp.add_setter(split_view, "collapsed", Some(&true.to_value()));
        window.add_breakpoint(bp);
    }
    install_breakpoint(window, binding);
}


/// Ensure CSS for adaptive sidebar resizing is registered.
pub fn ensure_adaptive_css() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            ".sidebar-resize-handle {\n\
                 background: transparent;\n\
                 border-left: 1px solid var(--borders, rgba(127, 127, 127, 0.2));\n\
                 min-width: 8px;\n\
                 transition: background 150ms ease, border-color 150ms ease;\n\
             }\n\
             .sidebar-resize-handle.handle-end {\n\
                 border-left: none;\n\
                 border-right: 1px solid var(--borders, rgba(127, 127, 127, 0.2));\n\
             }\n\
             .sidebar-resize-handle:hover {\n\
                 background: color-mix(in srgb, var(--accent-bg-color, #3584e4) 20%, transparent);\n\
                 border-color: var(--accent-bg-color, #3584e4);\n\
             }\n\
             .sidebar-resize-handle.resizing {\n\
                 background: color-mix(in srgb, var(--accent-bg-color, #3584e4) 35%, transparent);\n\
                 border-color: var(--accent-bg-color, #3584e4);\n\
             }\n\
             .bottom-search-toolbar {\n\
                 background-color: var(--headerbar-bg-color, var(--window-bg-color));\n\
                 border-top: 1px solid var(--borders, rgba(127, 127, 127, 0.2));\n\
                 padding: 8px 12px;\n\
             }\n\
             .bottom-search-toolbar .search-entry {\n\
                 border-radius: 9999px;\n\
                 min-height: 38px;\n\
             }\n\
             .bottom-add-btn {\n\
                 min-width: 38px;\n\
                 min-height: 38px;\n\
                 border-radius: 9999px;\n\
             }\n\
             .compact-search-bar {\n\
                 padding: 6px 16px 8px 16px;\n\
                 border-bottom: 1px solid var(--borders, rgba(127, 127, 127, 0.15));\n\
                 background-color: var(--headerbar-bg-color, var(--window-bg-color));\n\
             }\n",
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

/// Wrap a sidebar child widget with an interactive resize handle that allows the
/// user to tap or click and slide left or right to dynamically resize the
/// Libadwaita adaptive sidebar.
pub fn make_resizable_sidebar(
    split_view: &adw::OverlaySplitView,
    sidebar_content: &impl IsA<gtk::Widget>,
    default_fraction: f64,
) -> gtk::Box {
    ensure_adaptive_css();
    let container = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    sidebar_content.set_hexpand(true);
    sidebar_content.set_vexpand(true);

    let handle = gtk::Box::new(gtk::Orientation::Vertical, 0);
    handle.add_css_class("sidebar-resize-handle");
    if split_view.sidebar_position() == gtk::PackType::End {
        handle.add_css_class("handle-end");
    }
    handle.set_width_request(8);
    handle.set_cursor_from_name(Some("col-resize"));
    handle.set_tooltip_text(Some("Resize Sidebar (drag or tap to slide left/right)"));
    crate::linux::ui::a11y::set_wwn_a11y(
        &handle,
        crate::linux::ui::a11y::id::MACHINES_SIDEBAR_RESIZER,
        Some("Resize sidebar"),
    );

    let drag = gtk::GestureDrag::new();

    // Pointer X in the split view, minus the sidebar edge, captured at drag
    // start. AdwOverlaySplitView only swipes to show or hide the sidebar. It
    // does not drag the width. GtkPaned measures the pointer in the parent.
    // A delta in the handle's own coordinates jitters because the handle moves
    // with the sidebar under the pointer.
    let grab = Rc::new(Cell::new(0.0f64));

    let split_c = split_view.clone();
    let handle_c = handle.clone();
    let grab_c = grab.clone();

    drag.connect_drag_begin(move |gesture, _, _| {
        handle_c.add_css_class("resizing");
        let Some((px, py)) = gesture.point(None) else {
            return;
        };
        let Some((sx, _)) = handle_c.translate_coordinates(&split_c, px, py) else {
            return;
        };
        let total = split_c.width() as f64;
        let current = if total > 1.0 {
            total * split_c.sidebar_width_fraction()
        } else {
            split_c.min_sidebar_width()
        };
        let at_end = split_c.sidebar_position() == gtk::PackType::End;
        let edge = if at_end { total - current } else { current };
        grab_c.set(sx - edge);
    });

    let split_c2 = split_view.clone();
    let handle_c2 = handle.clone();
    let grab_c2 = grab.clone();

    drag.connect_drag_update(move |gesture, _, _| {
        let Some((px, py)) = gesture.point(None) else {
            return;
        };
        let Some((sx, _)) = handle_c2.translate_coordinates(&split_c2, px, py) else {
            return;
        };
        let total = split_c2.width() as f64;
        if total <= 1.0 {
            return;
        }
        let at_end = split_c2.sidebar_position() == gtk::PackType::End;
        let new_w = sidebar_width_from_pointer(
            sx,
            grab_c2.get(),
            total,
            at_end,
            split_c2.min_sidebar_width(),
            split_c2.max_sidebar_width(),
        );
        let fraction = (new_w / total).clamp(0.05, 0.90);
        split_c2.set_sidebar_width_fraction(fraction);
    });

    let handle_c2 = handle.clone();
    drag.connect_drag_end(move |_, _, _| {
        handle_c2.remove_css_class("resizing");
    });
    handle.add_controller(drag);

    let click = gtk::GestureClick::new();
    let split_c3 = split_view.clone();
    click.connect_pressed(move |_, n_press, _, _| {
        if n_press == 2 {
            split_c3.set_sidebar_width_fraction(default_fraction);
        }
    });
    handle.add_controller(click);

    container.set_hexpand(true);
    container.set_vexpand(true);

    if split_view.sidebar_position() == gtk::PackType::End {
        container.append(&handle);
        container.append(sidebar_content);
    } else {
        container.append(sidebar_content);
        container.append(&handle);
    }

    container
}

/// Vertical scroller for an adaptive sidebar. Horizontal resize stays on the
/// handle. A short window scrolls the sections instead of clipping them.
pub fn scrollable_sidebar(child: &impl IsA<gtk::Widget>) -> gtk::ScrolledWindow {
    let scroll = gtk::ScrolledWindow::new();
    scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scroll.set_propagate_natural_width(false);
    scroll.set_propagate_natural_height(false);
    scroll.set_kinetic_scrolling(true);
    scroll.set_min_content_width(0);
    scroll.set_min_content_height(0);
    scroll.set_hexpand(true);
    scroll.set_vexpand(true);
    child.set_hexpand(true);
    child.set_vexpand(true);
    scroll.set_child(Some(child));
    scroll
}

/// Clamp the main content to a comfortable desktop max width.
pub fn clamp_content(child: &impl IsA<gtk::Widget>) -> adw::Clamp {
    adw::Clamp::builder()
        .child(child)
        .maximum_size(1320)
        .tightening_threshold(600)
        .build()
}

/// Search field and optional add button, placed like Machine Configuration.
/// Wide: search entry and add in the header. Narrow: search icon reveals a
/// bar under the header, add stays in the header. Touch: both sit in a
/// bottom bar.
pub struct AdaptiveSearchAdd {
    pub header_search: gtk::SearchEntry,
    pub search_toggle: gtk::ToggleButton,
    pub header_add: Option<gtk::Button>,
    pub revealer: gtk::Revealer,
    pub bottom_bar: gtk::Box,
    pub bottom_add: Option<gtk::Button>,
    compact_search: gtk::SearchEntry,
    bottom_search: gtk::SearchEntry,
}

pub struct SearchAddOptions<'a> {
    pub placeholder: &'a str,
    pub search_a11y: &'a str,
    pub search_label: &'a str,
    pub add_tooltip: Option<&'a str>,
    pub add_a11y: Option<&'a str>,
    pub add_label: Option<&'a str>,
}

impl AdaptiveSearchAdd {
    pub fn new(opts: SearchAddOptions<'_>) -> Self {
        ensure_adaptive_css();

        let header_search = gtk::SearchEntry::new();
        header_search.set_placeholder_text(Some(opts.placeholder));
        header_search.set_hexpand(false);
        header_search.set_width_chars(12);
        header_search.set_max_width_chars(20);
        crate::linux::ui::a11y::set_wwn_a11y(
            &header_search,
            opts.search_a11y,
            Some(opts.search_label),
        );

        let search_toggle = gtk::ToggleButton::new();
        search_toggle.set_icon_name("system-search-symbolic");
        search_toggle.set_tooltip_text(Some(opts.search_label));
        crate::linux::ui::a11y::set_wwn_a11y(
            &search_toggle,
            &format!("{}.toggle", opts.search_a11y),
            Some(opts.search_label),
        );

        let revealer = gtk::Revealer::new();
        revealer.set_transition_type(gtk::RevealerTransitionType::SlideDown);
        let compact_box = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        compact_box.add_css_class("compact-search-bar");
        let compact_search = gtk::SearchEntry::new();
        compact_search.set_placeholder_text(Some(opts.placeholder));
        compact_search.set_hexpand(true);
        crate::linux::ui::a11y::set_wwn_a11y(
            &compact_search,
            opts.search_a11y,
            Some(opts.search_label),
        );
        let compact_clamp = clamp_content(&compact_search);
        compact_clamp.set_hexpand(true);
        compact_box.append(&compact_clamp);
        revealer.set_child(Some(&compact_box));

        let rev_c = revealer.clone();
        let compact_focus = compact_search.clone();
        search_toggle.connect_toggled(move |btn| {
            let active = btn.is_active();
            rev_c.set_reveal_child(active);
            if active {
                compact_focus.grab_focus();
            }
        });
        let toggle_escape = search_toggle.clone();
        compact_search.connect_stop_search(move |_| {
            toggle_escape.set_active(false);
        });

        let bottom_bar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        bottom_bar.add_css_class("bottom-search-toolbar");
        let bottom_search = gtk::SearchEntry::new();
        bottom_search.set_placeholder_text(Some(opts.placeholder));
        bottom_search.set_hexpand(true);
        bottom_search.add_css_class("search-entry");
        crate::linux::ui::a11y::set_wwn_a11y(
            &bottom_search,
            opts.search_a11y,
            Some(opts.search_label),
        );
        bottom_bar.append(&bottom_search);

        let (header_add, bottom_add) = if let Some(tooltip) = opts.add_tooltip {
            let header_add = gtk::Button::from_icon_name("list-add-symbolic");
            header_add.set_tooltip_text(Some(tooltip));
            if let Some(id) = opts.add_a11y {
                crate::linux::ui::a11y::set_wwn_a11y(&header_add, id, opts.add_label);
            }
            let bottom_add = gtk::Button::from_icon_name("list-add-symbolic");
            bottom_add.set_tooltip_text(Some(tooltip));
            bottom_add.add_css_class("suggested-action");
            bottom_add.add_css_class("circular");
            bottom_add.add_css_class("bottom-add-btn");
            if let Some(id) = opts.add_a11y {
                crate::linux::ui::a11y::set_wwn_a11y(&bottom_add, id, opts.add_label);
            }
            bottom_bar.append(&bottom_add);
            (Some(header_add), Some(bottom_add))
        } else {
            (None, None)
        };

        let chrome = Self {
            header_search,
            search_toggle,
            header_add,
            revealer,
            bottom_bar,
            bottom_add,
            compact_search,
            bottom_search,
        };
        chrome.apply(false, false, 0);
        chrome
    }

    /// Pack add, then the search toggle, then the search field. Call this
    /// after the header's trailing buttons so those stay furthest right.
    pub fn pack_header(&self, header: &adw::HeaderBar) {
        if let Some(add) = &self.header_add {
            header.pack_end(add);
        }
        header.pack_end(&self.search_toggle);
        header.pack_end(&self.header_search);
    }

    pub fn bind_query(&self, on_change: Rc<dyn Fn(String)>) {
        let entries = [
            self.header_search.clone(),
            self.compact_search.clone(),
            self.bottom_search.clone(),
        ];
        let syncing = Rc::new(Cell::new(false));
        for entry in entries.clone() {
            let others = entries.clone();
            let on_change = on_change.clone();
            let syncing = syncing.clone();
            entry.connect_search_changed(move |entry| {
                if syncing.get() {
                    return;
                }
                let text = entry.text().to_string();
                syncing.set(true);
                for other in &others {
                    if other != entry && other.text().as_str() != text {
                        other.set_text(&text);
                    }
                }
                syncing.set(false);
                on_change(text);
            });
        }
    }

    /// `active` is false when this screen is not showing the list.
    /// Width below 760px is the narrow rule from Machine Configuration.
    pub fn apply(&self, active: bool, is_touch: bool, width: i32) {
        let is_compact = width > 0 && width < crate::linux::ui_model::SPLIT_COLLAPSE_BELOW_PX;
        if !active {
            self.header_search.set_visible(false);
            self.search_toggle.set_visible(false);
            self.search_toggle.set_active(false);
            self.revealer.set_reveal_child(false);
            self.bottom_bar.set_visible(false);
            if let Some(add) = &self.header_add {
                add.set_visible(false);
            }
            return;
        }
        if is_touch {
            self.header_search.set_visible(false);
            self.search_toggle.set_visible(false);
            self.search_toggle.set_active(false);
            self.revealer.set_reveal_child(false);
            if let Some(add) = &self.header_add {
                add.set_visible(false);
            }
            self.bottom_bar.set_visible(true);
        } else {
            self.bottom_bar.set_visible(false);
            if let Some(add) = &self.header_add {
                add.set_visible(true);
            }
            if is_compact {
                self.header_search.set_visible(false);
                self.search_toggle.set_visible(true);
            } else {
                self.header_search.set_visible(true);
                self.search_toggle.set_visible(false);
                self.revealer.set_reveal_child(false);
                self.search_toggle.set_active(false);
            }
        }
    }
}

/// Returns true if a touchscreen is present, or if running under a Linux Mobile
/// shell (such as Phosh or gnome-mobile), or if WAWONA_TOUCH_UI or WAWONA_MOBILE is set.
pub fn is_touchscreen_active() -> bool {
    if std::env::var("WAWONA_TOUCH_UI").map(|v| v == "1" || v == "true").unwrap_or(false)
        || std::env::var("WAWONA_MOBILE").map(|v| v == "1" || v == "true").unwrap_or(false)
        || std::env::var("PHOSH_SESSION").is_ok()
        || std::env::var("GNOME_SHELL_SESSION_MODE").map(|v| v.contains("phosh")).unwrap_or(false)
    {
        return true;
    }
    if let Some(display) = gtk::gdk::Display::default() {
        if let Some(seat) = display.default_seat() {
            use gtk::gdk::prelude::SeatExt;
            return seat.capabilities().contains(gtk::gdk::SeatCapabilities::TOUCH);
        }
    }
    false
}



