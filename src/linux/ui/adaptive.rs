//! Adaptive layout helpers (width-based breakpoint + clamp).

use std::cell::Cell;
use std::rc::Rc;

use gtk4 as gtk;
use libadwaita as adw;
use adw::prelude::*;

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

/// Track window width and toggle compact vs expanded at the canonical 600px
/// breakpoint. libadwaita 0.7 lacks `AdwBreakpoint` in the Rust bindings we
/// ship, so this uses width notifications instead.
pub fn install_breakpoint(window: &adw::ApplicationWindow, binding: &LayoutBinding) {
    let binding_init = binding.clone();
    apply_width(&binding_init, window.default_width());

    let binding_notify = binding.clone();
    window.connect_default_width_notify(move |w| {
        apply_width(&binding_notify, w.default_width());
    });
}

/// Clamp the main content to a comfortable desktop max width.
pub fn clamp_content(child: &impl IsA<gtk::Widget>) -> adw::Clamp {
    adw::Clamp::builder()
        .child(child)
        .maximum_size(1100)
        .tightening_threshold(400)
        .build()
}
