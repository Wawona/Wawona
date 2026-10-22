//! Modal presentation helper mirroring `WawonaModalSheet` semantics.
//!
//! Supports two distinct presentation modes matching Wawona iOS, Android, and macOS:
//! 1. Mobile bottom sheet: when in touchscreen mode with phone-screen width (compact layout).
//!    Starts at half-height (detent 1) with a pill drag handle, and can be swiped to expand
//!    to full-height (detent 2) or swiped down to dismiss, matching iOS and Android bottom sheets.
//! 2. Desktop modal sheet: when in desktop mode (expanded width, mouse/pointer interaction).
//!    Presented as a centered modal sheet window matching macOS per-machine UI edit.

use std::cell::Cell;
use std::rc::Rc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::ui::SharedAppState;
use crate::linux::ui_model::LayoutMode;

/// Detect whether the session is currently in touchscreen interaction mode.
pub fn is_touchscreen_mode(state: &SharedAppState) -> bool {
    if let Ok(val) = std::env::var("WAWONA_TOUCH_MODE") {
        if val == "1" || val.eq_ignore_ascii_case("true") {
            return true;
        }
        if val == "0" || val.eq_ignore_ascii_case("false") {
            return false;
        }
    }
    if state.borrow().settings.touch_pointer_emulation {
        return true;
    }
    if let Some(display) = gtk::gdk::Display::default() {
        for seat in display.list_seats() {
            if seat.capabilities().contains(gtk::gdk::SeatCapabilities::TOUCH) {
                return true;
            }
            for dev in seat.devices(gtk::gdk::SeatCapabilities::ALL) {
                if dev.source() == gtk::gdk::InputSource::Touchscreen {
                    return true;
                }
            }
        }
    }
    false
}

/// Install stylesheet for bottom sheet and desktop modal sheet.
pub fn install_sheet_styles() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let provider = gtk::CssProvider::new();
        provider.load_from_data(
            r#"
            .wwn-sheet-scrim {
              background-color: rgba(0, 0, 0, 0.48);
            }

            .wwn-bottom-sheet {
              background-color: var(--window-bg-color, #1e1e1e);
              border-top-left-radius: 20px;
              border-top-right-radius: 20px;
              box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.48);
              border-top: 1px solid rgba(255, 255, 255, 0.14);
              border-left: 1px solid rgba(255, 255, 255, 0.08);
              border-right: 1px solid rgba(255, 255, 255, 0.08);
            }

            .wwn-sheet-handle-bar {
              padding-top: 10px;
              padding-bottom: 6px;
              cursor: grab;
            }

            .wwn-sheet-handle {
              min-width: 44px;
              min-height: 5px;
              border-radius: 999px;
              background-color: rgba(255, 255, 255, 0.40);
            }

            .wwn-sheet-handle:hover {
              background-color: rgba(255, 255, 255, 0.70);
            }

            .wwn-macos-sheet {
              border-radius: 14px;
              box-shadow: 0 16px 40px rgba(0, 0, 0, 0.40);
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

/// Present `content` as a mobile bottom sheet inside the parent window's `root_overlay`.
///
/// Starts at half height with a top pill handle. Supports swipe-to-expand to full height,
/// swipe-to-collapse back to half height, and swipe-down to dismiss.
/// Returns a closer callback if successfully mounted.
pub fn present_bottom_sheet(
    parent: &adw::ApplicationWindow,
    content: &impl IsA<gtk::Widget>,
    on_close: Rc<dyn Fn(bool)>,
) -> Option<Rc<dyn Fn(bool)>> {
    let root_overlay = parent.content().and_downcast::<gtk::Overlay>()?;
    install_sheet_styles();

    let overlay_box = gtk::Box::new(gtk::Orientation::Vertical, 0);
    overlay_box.set_hexpand(true);
    overlay_box.set_vexpand(true);
    overlay_box.add_css_class("wwn-sheet-scrim");

    let scrim_dismiss = gtk::Box::new(gtk::Orientation::Vertical, 0);
    scrim_dismiss.set_hexpand(true);
    scrim_dismiss.set_vexpand(true);

    let sheet_card = gtk::Box::new(gtk::Orientation::Vertical, 0);
    sheet_card.add_css_class("wwn-bottom-sheet");
    sheet_card.set_halign(gtk::Align::Fill);
    sheet_card.set_valign(gtk::Align::End);
    sheet_card.set_hexpand(true);

    let handle_bar = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    handle_bar.add_css_class("wwn-sheet-handle-bar");
    handle_bar.set_halign(gtk::Align::Center);
    handle_bar.set_valign(gtk::Align::Center);
    handle_bar.set_hexpand(true);

    let handle = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    handle.add_css_class("wwn-sheet-handle");
    handle_bar.append(&handle);

    sheet_card.append(&handle_bar);
    content.set_vexpand(true);
    sheet_card.append(content);

    overlay_box.append(&scrim_dismiss);
    overlay_box.append(&sheet_card);

    let total_h = parent.height().max(520);
    let half_h = ((total_h as f64) * 0.52).round() as i32;
    sheet_card.set_height_request(half_h);

    let is_expanded = Rc::new(Cell::new(false));
    let is_closed = Rc::new(Cell::new(false));

    let close_sheet: Rc<dyn Fn(bool)> = {
        let is_closed = is_closed.clone();
        let overlay_box = overlay_box.clone();
        let root_overlay = root_overlay.clone();
        let on_close = on_close.clone();
        Rc::new(move |saved| {
            if is_closed.get() {
                return;
            }
            is_closed.set(true);
            root_overlay.remove_overlay(&overlay_box);
            on_close(saved);
        })
    };

    let scrim_click = gtk::GestureClick::new();
    {
        let close_sheet = close_sheet.clone();
        scrim_click.connect_released(move |_, _, _, _| {
            close_sheet(false);
        });
    }
    scrim_dismiss.add_controller(scrim_click);

    let key_controller = gtk::EventControllerKey::new();
    {
        let close_sheet = close_sheet.clone();
        key_controller.connect_key_pressed(move |_, keyval, _, _| {
            if keyval == gtk::gdk::Key::Escape {
                close_sheet(false);
                gtk::glib::Propagation::Stop
            } else {
                gtk::glib::Propagation::Proceed
            }
        });
    }
    overlay_box.add_controller(key_controller);

    let drag = gtk::GestureDrag::new();
    let start_h = Rc::new(Cell::new(half_h));
    {
        let start_h = start_h.clone();
        let is_expanded = is_expanded.clone();
        let parent = parent.clone();
        drag.connect_drag_begin(move |_, _, _| {
            let total_h = parent.height().max(520);
            let h = if is_expanded.get() {
                (total_h - 40).max(340)
            } else {
                ((total_h as f64) * 0.52).round() as i32
            };
            start_h.set(h);
        });
    }
    {
        let start_h = start_h.clone();
        let sheet_card = sheet_card.clone();
        let parent = parent.clone();
        drag.connect_drag_update(move |_, _offset_x, offset_y| {
            let total_h = parent.height().max(520);
            let min_h = ((total_h as f64) * 0.28).round() as i32;
            let max_h = total_h - 40;
            let new_h = (start_h.get() as f64 - offset_y).round() as i32;
            sheet_card.set_height_request(new_h.clamp(min_h, max_h));
        });
    }
    {
        let is_expanded = is_expanded.clone();
        let sheet_card = sheet_card.clone();
        let parent = parent.clone();
        let close_sheet = close_sheet.clone();
        drag.connect_drag_end(move |_, _offset_x, offset_y| {
            let total_h = parent.height().max(520);
            let half_h = ((total_h as f64) * 0.52).round() as i32;
            let full_h = (total_h - 40).max(half_h);

            if !is_expanded.get() && offset_y > 90.0 {
                close_sheet(false);
                return;
            }

            if !is_expanded.get() && offset_y < -50.0 {
                is_expanded.set(true);
                sheet_card.set_height_request(full_h);
                return;
            }

            if is_expanded.get() && offset_y > 60.0 {
                is_expanded.set(false);
                sheet_card.set_height_request(half_h);
                return;
            }

            let target = if is_expanded.get() { full_h } else { half_h };
            sheet_card.set_height_request(target);
        });
    }
    handle_bar.add_controller(drag);

    let handle_click = gtk::GestureClick::new();
    {
        let is_expanded = is_expanded.clone();
        let sheet_card = sheet_card.clone();
        let parent = parent.clone();
        handle_click.connect_released(move |_, _, _, _| {
            let next = !is_expanded.get();
            is_expanded.set(next);
            let total_h = parent.height().max(520);
            let target = if next {
                (total_h - 40).max(340)
            } else {
                ((total_h as f64) * 0.52).round() as i32
            };
            sheet_card.set_height_request(target);
        });
    }
    handle_bar.add_controller(handle_click);

    root_overlay.add_overlay(&overlay_box);
    Some(close_sheet)
}

/// Present `content` as a centered macOS-style modal sheet dialog.
pub fn present_macos_sheet(
    parent: &adw::ApplicationWindow,
    title: &str,
    content: &impl IsA<gtk::Widget>,
    on_close: Rc<dyn Fn(bool)>,
) -> adw::Window {
    install_sheet_styles();
    let dialog = adw::Window::builder()
        .transient_for(parent)
        .modal(true)
        .title(title)
        .default_width(760)
        .default_height(680)
        .resizable(true)
        .build();
    dialog.add_css_class("wwn-macos-sheet");

    let dialog_weak = dialog.downgrade();
    let on_close_c = on_close.clone();
    let key_controller = gtk::EventControllerKey::new();
    key_controller.connect_key_pressed(move |_, keyval, _, _| {
        if keyval == gtk::gdk::Key::Escape {
            if let Some(d) = dialog_weak.upgrade() {
                d.close();
            }
            on_close_c(false);
            gtk::glib::Propagation::Stop
        } else {
            gtk::glib::Propagation::Proceed
        }
    });
    dialog.add_controller(key_controller);

    dialog.set_content(Some(content));
    dialog.present();
    dialog
}

/// Legacy modal presentation helper for general dialogs.
pub fn present_sheet(
    parent: &impl IsA<gtk::Window>,
    title: &str,
    content: &impl IsA<gtk::Widget>,
    layout: LayoutMode,
) -> adw::Window {
    install_sheet_styles();
    let dialog = adw::Window::builder()
        .transient_for(parent)
        .modal(true)
        .title(title)
        .build();

    match layout {
        LayoutMode::Compact => {
            dialog.set_default_width(360);
            dialog.set_default_height(520);
            dialog.set_resizable(true);
        }
        LayoutMode::Expanded => {
            dialog.set_default_width(760);
            dialog.set_default_height(680);
            dialog.set_resizable(true);
        }
    }

    dialog.set_content(Some(content));
    dialog.present();
    dialog
}
