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

    if split_view.sidebar_position() == gtk::PackType::End {
        container.append(&handle);
        container.append(sidebar_content);
    } else {
        container.append(sidebar_content);
        container.append(&handle);
    }

    container
}

/// Clamp the main content to a comfortable desktop max width.
pub fn clamp_content(child: &impl IsA<gtk::Widget>) -> adw::Clamp {
    adw::Clamp::builder()
        .child(child)
        .maximum_size(1320)
        .tightening_threshold(600)
        .build()
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



