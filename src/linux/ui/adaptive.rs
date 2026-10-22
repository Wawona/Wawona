//! Adaptive layout helpers (width-based breakpoint + clamp).

use std::cell::Cell;
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::ui_model::LayoutMode;

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
    if let Ok(cond) = adw::BreakpointCondition::parse("max-width: 760px") {
        let bp = adw::Breakpoint::new(cond);
        bp.add_setter(split_view, "collapsed", Some(&true.to_value()));
        bp.add_setter(split_view, "show-sidebar", Some(&false.to_value()));
        window.add_breakpoint(bp);
    }
    install_breakpoint(window, binding);
}


/// Clamp the main content to a comfortable desktop max width.
pub fn clamp_content(child: &impl IsA<gtk::Widget>) -> adw::Clamp {
    adw::Clamp::builder()
        .child(child)
        .maximum_size(1320)
        .tightening_threshold(600)
        .build()
}



