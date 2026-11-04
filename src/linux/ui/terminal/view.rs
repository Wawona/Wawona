//! GTK widget hosting Wawona Terminal (chrome + TextView + input).

use std::cell::{Cell, RefCell};
use std::fs::File;
use std::io::Read;
use std::os::unix::io::{AsRawFd, FromRawFd};
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

use adw::prelude::*;
use gtk::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::ui::a11y::{self, id};
use crate::term::TerminalSession;

use super::keys::{bytes_for_key, HostDecModes};
use super::paint::{
    emit_pointer, paste_from_clipboard, refresh, wire_picture_canvas, write_pty,
    PictureLayer,
};

/// Build an in-app GTK widget hosting Wawona Terminal.
pub fn build_terminal_view(
    session: Arc<TerminalSession>,
    master: File,
    pid: u32,
    title: &str,
    subtitle: &str,
    on_back: Rc<dyn Fn()>,
    on_stop: Rc<dyn Fn()>,
) -> gtk::Widget {
    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.set_hexpand(true);
    root.set_vexpand(true);
    root.add_css_class("wwn-terminal-root");
    a11y::set_wwn_a11y(&root, id::TERMINAL_ROOT, Some("Wawona Terminal"));

    let header = adw::HeaderBar::new();
    header.set_show_end_title_buttons(false);
    header.set_show_start_title_buttons(false);
    let back = gtk::Button::builder()
        .icon_name("go-previous-symbolic")
        .tooltip_text("Back to Machines")
        .css_classes(["flat"])
        .build();
    let on_back_click = on_back.clone();
    back.connect_clicked(move |_| on_back_click());
    header.pack_start(&back);

    let title_widget = adw::WindowTitle::new(title, subtitle);
    header.set_title_widget(Some(&title_widget));
    let done = gtk::Button::with_label("Stop Session");
    done.add_css_class("destructive-action");
    a11y::set_wwn_a11y(&done, id::TERMINAL_DONE, Some("Close Terminal"));
    let on_stop_click = on_stop.clone();
    done.connect_clicked(move |_| {
        unsafe { libc::kill(pid as i32, libc::SIGTERM) };
        on_stop_click();
    });
    header.pack_end(&done);

    let view = gtk::TextView::new();
    view.set_editable(false);
    view.set_cursor_visible(false);
    view.set_monospace(true);
    view.set_wrap_mode(gtk::WrapMode::None);
    view.set_focusable(true);
    view.set_can_focus(true);
    view.set_top_margin(12);
    view.set_bottom_margin(12);
    view.set_left_margin(14);
    view.set_right_margin(14);
    view.add_css_class("wwn-terminal-view");
    let buffer = view.buffer();
    let pictures: Rc<RefCell<PictureLayer>> = Rc::new(RefCell::new(PictureLayer {
        images: Vec::new(),
        scrollback: 0,
    }));
    let grid = Rc::new(Cell::new((0u32, 0u32)));
    let scroll = gtk::ScrolledWindow::builder()
        .child(&view)
        .hexpand(true)
        .vexpand(true)
        .min_content_width(0)
        .min_content_height(0)
        .propagate_natural_width(false)
        .propagate_natural_height(false)
        .build();
    scroll.add_css_class("wwn-terminal-scroll");
    let back = gtk::DrawingArea::new();
    back.set_hexpand(true);
    back.set_vexpand(true);
    let front = gtk::DrawingArea::new();
    front.set_can_target(false);
    front.set_hexpand(true);
    front.set_vexpand(true);
    let overlay = gtk::Overlay::new();
    overlay.set_child(Some(&back));
    overlay.add_overlay(&scroll);
    overlay.add_overlay(&front);
    root.append(&header);
    root.append(&overlay);

    let css = gtk::CssProvider::new();
    css.load_from_data(
        ".wwn-terminal-root { background-color: #0d0f14; } .wwn-terminal-scroll, .wwn-terminal-scroll viewport, .wwn-terminal-view, textview.wwn-terminal-view, textview.wwn-terminal-view text { background-color: #0d0f14; color: #e8e8e8; font-family: \"DejaVu Sans Mono\", \"Fira Code\", monospace; font-size: 13px; }",
    );
    if let Some(display) = gtk::gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &css,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let master = Rc::new(RefCell::new(master));
    let fd = master.borrow().as_raw_fd();
    let view_fd = view.clone();
    let buffer_fd = buffer.clone();
    let session_fd = session.clone();
    let title_fd = title_widget.clone();
    let dec_modes = Rc::new(RefCell::new(HostDecModes::default()));
    let dec_read = dec_modes.clone();
    let master_fd_loop = master.clone();
    let pictures_fd = pictures.clone();
    let back_fd = back.clone();
    let front_fd = front.clone();
    let grid_fd = grid.clone();
    let session_alive = Rc::new(Cell::new(true));
    let alive_read = session_alive.clone();
    glib::unix_fd_add_local(fd, glib::IOCondition::IN, move |_, _| {
        let mut buf = [0u8; 4096];
        let read = {
            let mut file = master_fd_loop.borrow_mut();
            file.read(&mut buf)
        };
        let (n, errno) = match &read {
            Ok(n) => (*n as isize, 0),
            Err(err) => (-1, err.raw_os_error().unwrap_or(0)),
        };
        let kind = crate::domain::terminal_liveness::classify_pty_read(n, errno);
        if crate::domain::terminal_liveness::screen_fate(kind)
            == crate::domain::terminal_liveness::ScreenFate::Ended
        {
            mark_session_ended(&title_fd, &buffer_fd, alive_read.as_ref());
            return glib::ControlFlow::Break;
        }
        if let Ok(n) = read {
            if n > 0 {
                session_fd.feed(buf[..n].to_vec());
                dec_read.borrow_mut().observe(&buf[..n]);
                let reply = session_fd.take_reply();
                if !reply.is_empty() {
                    let mut file = master_fd_loop.borrow_mut();
                    write_pty(&mut file, &reply);
                }
                refresh(
                    &session_fd,
                    &buffer_fd,
                    &pictures_fd,
                    &grid_fd,
                    &back_fd,
                    &front_fd,
                );
                let terminal_title = session_fd.title();
                if !terminal_title.is_empty() {
                    title_fd.set_subtitle(&terminal_title);
                }
                let mut end = buffer_fd.end_iter();
                let _ = view_fd.scroll_to_iter(&mut end, 0.0, true, 0.0, 1.0);
                return glib::ControlFlow::Continue;
            }
        }
        glib::ControlFlow::Continue
    });

    let alive_keys = session_alive.clone();
    let master_keys = dup_master(fd);
    let session_keys = session.clone();
    let buffer_keys = buffer.clone();
    let dec_keys = dec_modes.clone();
    let keys = gtk::EventControllerKey::new();
    keys.connect_key_pressed(move |_, key, _, state| {
        if state.contains(gtk::gdk::ModifierType::CONTROL_MASK) {
            if let Some(ch) = key.to_unicode() {
                if state.contains(gtk::gdk::ModifierType::SHIFT_MASK) {
                    if ch.eq_ignore_ascii_case(&'c') {
                        copy_selection_to_clipboard(&buffer_keys);
                        return gtk::glib::Propagation::Stop;
                    }
                    if ch.eq_ignore_ascii_case(&'v') {
                        paste_from_clipboard(&session_keys, &master_keys);
                        return gtk::glib::Propagation::Stop;
                    }
                } else if ch.eq_ignore_ascii_case(&'v') {
                    paste_from_clipboard(&session_keys, &master_keys);
                    return gtk::glib::Propagation::Stop;
                }
            }
        }
        let bytes = dec_keys
            .borrow()
            .map_key(key, state, bytes_for_key(key, state));
        if alive_keys.get() && !bytes.is_empty() {
            if let Some(file) = master_keys.borrow_mut().as_mut() {
                write_pty(file, &bytes);
            }
        }
        gtk::glib::Propagation::Stop
    });
    view.add_controller(keys);

    let glyph = Rc::new(Cell::new((0i32, 0i32)));
    wire_picture_canvas(&back, &pictures, &glyph, &scroll, true);
    wire_picture_canvas(&front, &pictures, &glyph, &scroll, false);
    refresh(&session, &buffer, &pictures, &grid, &back, &front);
    let session_ptr = session.clone();
    let master_ptr = master.clone();
    let glyph_ptr = glyph.clone();
    let click = gtk::GestureClick::new();
    click.set_button(0);
    click.connect_pressed(move |gesture, _, x, y| {
        let button = gesture.current_button();
        emit_pointer(
            &session_ptr,
            &master_ptr,
            &glyph_ptr,
            x,
            y,
            button,
            true,
            false,
        );
    });
    let session_rel = session.clone();
    let master_rel = master.clone();
    let glyph_rel = glyph.clone();
    click.connect_released(move |gesture, _, x, y| {
        let button = gesture.current_button();
        emit_pointer(
            &session_rel,
            &master_rel,
            &glyph_rel,
            x,
            y,
            button,
            false,
            false,
        );
    });
    view.add_controller(click);
    let session_motion = session.clone();
    let master_motion = master.clone();
    let glyph_motion = glyph.clone();
    let motion = gtk::EventControllerMotion::new();
    motion.connect_motion(move |_, x, y| {
        emit_pointer(
            &session_motion,
            &master_motion,
            &glyph_motion,
            x,
            y,
            0,
            true,
            true,
        );
    });
    view.add_controller(motion);

    let session_fit = session.clone();
    let view_fit = view.clone();
    let buffer_fit = buffer.clone();
    let grid_fit = grid.clone();
    let glyph_fit = glyph.clone();
    let pictures_fit = pictures.clone();
    let back_fit = back.clone();
    let front_fit = front.clone();
    let resize_fit = Rc::new(move || {
        let session = session_fit.clone();
        let view = view_fit.clone();
        let buffer = buffer_fit.clone();
        let grid = grid_fit.clone();
        let glyph = glyph_fit.clone();
        let pictures = pictures_fit.clone();
        let back = back_fit.clone();
        let front = front_fit.clone();
        fit_grid(
            &view, &session, fd, &grid, &glyph, &buffer, &pictures, &back, &front,
        );
    });
    let resize_tick = resize_fit.clone();
    let last_size = Rc::new(Cell::new((0i32, 0i32)));
    let last_size_tick = last_size.clone();
    root.add_tick_callback(move |widget, _| {
        let size = (widget.width(), widget.height());
        if widget.is_mapped() && size.0 > 0 && size.1 > 0 && last_size_tick.get() != size {
            last_size_tick.set(size);
            resize_tick();
        }
        gtk::glib::ControlFlow::Continue
    });
    let resize_map = resize_fit.clone();
    root.connect_map(move |_| resize_map());
    let session_idle = session.clone();
    let view_idle = view.clone();
    let buffer_idle = buffer.clone();
    let grid_idle = grid.clone();
    let glyph_idle = glyph.clone();
    let pictures_idle = pictures.clone();
    let back_idle = back.clone();
    let front_idle = front.clone();
    let buffer_blink = buffer.clone();
    let blink_on = Rc::new(Cell::new(false));
    let alive_wait = session_alive.clone();
    let title_wait = title_widget.clone();
    let buffer_wait = buffer.clone();
    let pid_wait = pid;
    glib::timeout_add_local(Duration::from_millis(1000), move || {
        if !alive_wait.get() {
            return glib::ControlFlow::Break;
        }
        if pid_wait > 0
            && crate::domain::terminal_liveness::child_fate(child_exited(pid_wait))
                == crate::domain::terminal_liveness::ScreenFate::Ended
        {
            mark_session_ended(&title_wait, &buffer_wait, alive_wait.as_ref());
            return glib::ControlFlow::Break;
        }
        glib::ControlFlow::Continue
    });
    glib::timeout_add_local(Duration::from_millis(500), move || {
        let hidden = !blink_on.get();
        blink_on.set(hidden);
        let table = buffer_blink.tag_table();
        table.foreach(|tag| {
            if tag.name().is_some_and(|name| name.ends_with("-blink")) {
                tag.set_invisible(hidden);
            }
        });
        glib::ControlFlow::Continue
    });
    glib::idle_add_local(move || {
        fit_grid(
            &view_idle,
            &session_idle,
            fd,
            &grid_idle,
            &glyph_idle,
            &buffer_idle,
            &pictures_idle,
            &back_idle,
            &front_idle,
        );
        glib::ControlFlow::Break
    });

    let view_focus = view.clone();
    root.connect_map(move |_| {
        view_focus.grab_focus();
    });
    root.upcast()
}

fn copy_selection_to_clipboard(buffer: &gtk::TextBuffer) {
    if let Some((start, end)) = buffer.selection_bounds() {
        let text = buffer.text(&start, &end, false);
        if let Some(display) = gtk::gdk::Display::default() {
            display.clipboard().set_text(&text);
        }
    }
}

fn dup_master(fd: i32) -> Rc<RefCell<Option<File>>> {
    let dup = unsafe { libc::dup(fd) };
    let file = if dup >= 0 {
        Some(unsafe { File::from_raw_fd(dup) })
    } else {
        None
    };
    Rc::new(RefCell::new(file))
}

fn child_exited(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    let mut status = 0;
    let rc = unsafe { libc::waitpid(pid as i32, &mut status, libc::WNOHANG) };
    rc == pid as i32
}

fn mark_session_ended(title: &adw::WindowTitle, buffer: &gtk::TextBuffer, alive: &Cell<bool>) {
    if !alive.get() {
        return;
    }
    alive.set(false);
    title.set_subtitle("Session ended");
    let mut end = buffer.end_iter();
    buffer.insert(
        &mut end,
        &format!("\n{}\n", crate::domain::terminal_liveness::ENDED_NOTICE),
    );
}

fn fit_grid(
    view: &gtk::TextView,
    session: &TerminalSession,
    master_fd: i32,
    grid: &Cell<(u32, u32)>,
    glyph: &Cell<(i32, i32)>,
    buffer: &gtk::TextBuffer,
    pictures: &RefCell<PictureLayer>,
    back: &gtk::DrawingArea,
    front: &gtk::DrawingArea,
) {
    let alloc = view.allocation();
    let layout = view.create_pango_layout(Some("M"));
    let (cell_w, cell_h) = layout.pixel_size();
    if cell_w < 1 || cell_h < 1 || alloc.width() < 1 || alloc.height() < 1 {
        return;
    }
    let cell_changed = glyph.get() != (cell_w, cell_h);
    glyph.set((cell_w, cell_h));
    session.set_cell_px(cell_w as u32, cell_h as u32);
    let cols = (alloc.width() / cell_w).clamp(20, 512) as u32;
    let rows = (alloc.height() / cell_h).clamp(8, 256) as u32;
    let grid_changed = grid.get() != (cols, rows);
    if !cell_changed && !grid_changed {
        return;
    }
    if grid_changed {
        grid.set((cols, rows));
        session.resize(cols, rows);
        let mut winsize = libc::winsize {
            ws_row: rows as u16,
            ws_col: cols as u16,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        unsafe {
            libc::ioctl(master_fd, libc::TIOCSWINSZ, &mut winsize);
        }
    }
    refresh(session, buffer, pictures, grid, back, front);
}

