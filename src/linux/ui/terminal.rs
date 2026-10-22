//! In-app Wawona Terminal for Linux.
//!
//! Native Shell and SSH terminal sessions draw UniFFI `TerminalSession` lines.
//! This file owns the PTY and the GTK view.

use std::cell::{Cell, RefCell};
use std::time::Duration;
use std::fs::File;
use std::io::{ErrorKind, Read, Write};
use std::os::unix::io::{AsRawFd, FromRawFd};
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::Arc;

use adw::prelude::*;
use gtk::prelude::{NativeExt, *};
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::machine_profile::{MachineProfile, MachineType};
use crate::linux::ui::a11y::{self, id};
use crate::term::{TerminalImage, TerminalSession, TerminalSpan};

/// Command to run inside the terminal, when this profile is a shell session.
pub fn shell_command(profile: &MachineProfile) -> Option<String> {
    match profile.machine_type {
        MachineType::SshTerminal => {
            let host = profile.ssh_host.trim();
            if host.is_empty() {
                return None;
            }
            let user = if profile.ssh_user.trim().is_empty() {
                "user"
            } else {
                profile.ssh_user.trim()
            };
            let mut cmd = format!("ssh -tt -p {} {user}@{host}", profile.ssh_port);
            let remote = profile.remote_command.trim();
            if !remote.is_empty() {
                cmd.push(' ');
                cmd.push_str(&quote_sh(remote));
            }
            Some(cmd)
        }
        MachineType::Native => {
            let id = profile
                .runtime_overrides
                .bundled_app_id
                .as_deref()
                .map(str::trim)
                .unwrap_or("");
            if id == "wawona-wasm" {
                Some(crate::linux::wasm_launch::effective_wasm_command(profile))
            } else if id == "wawona-shell" || !profile.remote_command.trim().is_empty() {
                let custom = profile.remote_command.trim();
                if custom.is_empty() {
                    Some("wawona-shell".to_string())
                } else {
                    Some(custom.to_string())
                }
            } else {
                None
            }
        }
        MachineType::Wasm => Some(crate::linux::wasm_launch::effective_wasm_command(profile)),
        MachineType::VirtualMachine | MachineType::Container => {
            let cmd = profile.effective_command();
            let trimmed = cmd.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }
        _ => None,
    }
}

/// Open a PTY, start `command`, and present the VT screen.
/// Start shell on a PTY and return child, session, and master file descriptor.
pub fn start_shell(command: &str) -> Result<(Child, Arc<TerminalSession>, File), String> {
    let (master_fd, slave_fd) = open_pty()?;
    let child = match spawn_on_slave(slave_fd, command) {
        Ok(child) => child,
        Err(err) => {
            unsafe { libc::close(master_fd) };
            return Err(err);
        }
    };
    let session = TerminalSession::new(80, 24);
    let master = unsafe { File::from_raw_fd(master_fd) };
    Ok((child, session, master))
}

/// Open a PTY, start `command`, and present the VT screen in a floating window (fallback).
pub fn open_shell(parent: &impl IsA<gtk::Window>, command: &str) -> Result<Child, String> {
    let (child, session, master) = start_shell(command)?;
    let window = adw::Window::builder()
        .transient_for(parent)
        .modal(false)
        .default_width(760)
        .default_height(460)
        .title("Wawona Terminal")
        .build();
    let win_c1 = window.clone();
    let win_c2 = window.clone();
    let view = build_terminal_view(
        session,
        master,
        child.id(),
        "Local Shell",
        Rc::new(move || {
            win_c1.close();
        }),
        Rc::new(move || {
            win_c2.close();
        }),
    );
    window.set_content(Some(&view));
    window.present();
    Ok(child)
}

fn quote_sh(text: &str) -> String {
    if text.contains('\'') {
        format!("\"{}\"", text.replace('"', "\\\""))
    } else {
        format!("'{text}'")
    }
}

fn open_pty() -> Result<(i32, i32), String> {
    let mut master = -1;
    let mut slave = -1;
    let mut size = libc::winsize {
        ws_row: 24,
        ws_col: 80,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let rc = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null(),
            &mut size,
        )
    };
    if rc != 0 {
        return Err("openpty failed".into());
    }
    unsafe {
        let flags = libc::fcntl(master, libc::F_GETFL);
        if flags >= 0 {
            libc::fcntl(master, libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
        libc::fcntl(master, libc::F_SETFD, libc::FD_CLOEXEC);
    }
    Ok((master, slave))
}

fn spawn_on_slave(slave_fd: i32, command: &str) -> Result<Child, String> {
    use std::os::unix::process::CommandExt;

    let slave = unsafe { File::from_raw_fd(slave_fd) };
    let stdin = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let stdout = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let mut cmd = if command == "wawona-shell" {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string());
        let mut cmd = Command::new(shell);
        cmd.arg("-i");
        cmd
    } else {
        let mut cmd = Command::new("/bin/sh");
        cmd.args(["-c", command]);
        cmd
    };
    cmd.stdin(stdin)
        .stdout(stdout)
        .stderr(Stdio::from(slave))
        .env("TERM", "xterm-256color");
    let (runtime_dir, wayland_disp) = if let Ok(rt) = crate::linux::runtime::read_runtime_state() {
        (rt.xdg_runtime_dir, rt.wayland_display)
    } else {
        let uid = unsafe { libc::getuid() };
        (format!("/run/user/{uid}"), "wawona-0".to_string())
    };
    cmd.env("XDG_RUNTIME_DIR", &runtime_dir);
    cmd.env("WAYLAND_DISPLAY", &wayland_disp);
    cmd.env_remove("WAYLAND_SOCKET");
    cmd.env("GDK_BACKEND", "wayland");
    cmd.env("QT_QPA_PLATFORM", "wayland");
    unsafe {
        cmd.pre_exec(move || {
            libc::signal(libc::SIGTTOU, libc::SIG_IGN);
            libc::signal(libc::SIGTTIN, libc::SIG_IGN);
            let _ = libc::setsid();
            let _ = libc::ioctl(0, libc::TIOCSCTTY, 0);
            let _ = libc::tcsetpgrp(0, libc::getpid());
            libc::signal(libc::SIGTTOU, libc::SIG_DFL);
            libc::signal(libc::SIGTTIN, libc::SIG_DFL);
            Ok(())
        });
    }
    cmd.spawn()
        .map_err(|err| format!("shell failed to start: {err}"))
}

/// Build an in-app GTK widget hosting Wawona Terminal.
pub fn build_terminal_view(
    session: Arc<TerminalSession>,
    master: File,
    pid: u32,
    title: &str,
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

    let back_btn = gtk::Button::builder()
        .icon_name("go-previous-symbolic")
        .tooltip_text("Back to Machines")
        .css_classes(["flat"])
        .build();
    let on_back_click = on_back.clone();
    back_btn.connect_clicked(move |_| {
        on_back_click();
    });
    header.pack_start(&back_btn);

    let title_widget = adw::WindowTitle::new(title, "Wawona Terminal (xterm-256color)");
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
        .hscrollbar_policy(gtk::PolicyType::Automatic)
        .vscrollbar_policy(gtk::PolicyType::Automatic)
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
    overlay.set_hexpand(true);
    overlay.set_vexpand(true);

    root.append(&header);
    root.append(&overlay);

    let css = gtk::CssProvider::new();
    css.load_from_data(
        "
        .wwn-terminal-root { background-color: #0d0f14; }
        .wwn-terminal-scroll, .wwn-terminal-scroll viewport, .wwn-terminal-view, textview.wwn-terminal-view, textview.wwn-terminal-view text {
            background-color: #0d0f14;
            color: #e8e8e8;
            font-family: \"DejaVu Sans Mono\", \"Fira Code\", monospace, \"DejaVuSansM Nerd Font Mono\";
            font-size: 13px;
        }
        ",
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
    let master_fd_loop = master.clone();
    let pictures_fd = pictures.clone();
    let back_fd = back.clone();
    let front_fd = front.clone();
    let grid_fd = grid.clone();

    glib::unix_fd_add_local(fd, glib::IOCondition::IN, move |_, _| {
        let mut buf = [0u8; 4096];
        let read = {
            let mut file = master_fd_loop.borrow_mut();
            file.read(&mut buf)
        };
        match read {
            Ok(0) => {
                title_fd.set_subtitle("Process exited [Finished]");
                glib::ControlFlow::Break
            }
            Err(err) if err.kind() == ErrorKind::WouldBlock => glib::ControlFlow::Continue,
            Err(_) => {
                title_fd.set_subtitle("Process exited [Finished]");
                glib::ControlFlow::Break
            }
            Ok(n) => {
                session_fd.feed(buf[..n].to_vec());
                let reply = session_fd.take_reply();
                if !reply.is_empty() {
                    let mut file = master_fd_loop.borrow_mut();
                    let _ = file.write_all(&reply);
                }
                refresh(
                    &session_fd,
                    &buffer_fd,
                    &pictures_fd,
                    &grid_fd,
                    &back_fd,
                    &front_fd,
                );
                let title = session_fd.title();
                if !title.is_empty() {
                    title_fd.set_subtitle(&title);
                }
                let mut end = buffer_fd.end_iter();
                let _ = view_fd.scroll_to_iter(&mut end, 0.0, false, 0.0, 1.0);
                glib::ControlFlow::Continue
            }
        }
    });

    let master_keys = dup_master(fd);
    let session_keys = session.clone();
    let buffer_keys = buffer.clone();
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
        let bytes = bytes_for_key(key, state);
        if !bytes.is_empty() {
            if let Some(file) = master_keys.borrow_mut().as_mut() {
                let _ = file.write_all(&bytes);
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
        emit_pointer(&session_ptr, &master_ptr, &glyph_ptr, x, y, button, true, false);
    });
    let session_rel = session.clone();
    let master_rel = master.clone();
    let glyph_rel = glyph.clone();
    click.connect_released(move |gesture, _, x, y| {
        let button = gesture.current_button();
        emit_pointer(&session_rel, &master_rel, &glyph_rel, x, y, button, false, false);
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
    let scroll_fit = scroll.clone();
    let buffer_fit = buffer.clone();
    let grid_fit = grid.clone();
    let glyph_fit = glyph.clone();
    let pictures_fit = pictures.clone();
    let back_fit = back.clone();
    let front_fit = front.clone();
    let do_fit = Rc::new(move || {
        fit_grid(
            &scroll_fit,
            &view_fit,
            &session_fit,
            fd,
            &grid_fit,
            &glyph_fit,
            &buffer_fit,
            &pictures_fit,
            &back_fit,
            &front_fit,
        );
    });

    let df1 = do_fit.clone();
    scroll.connect_notify_local(Some("width"), move |_, _| {
        df1();
    });
    let df2 = do_fit.clone();
    scroll.connect_notify_local(Some("height"), move |_, _| {
        df2();
    });
    let df3 = do_fit.clone();
    scroll.connect_map(move |_| {
        df3();
    });
    let df4 = do_fit.clone();
    glib::idle_add_local(move || {
        df4();
        glib::ControlFlow::Break
    });

    let buffer_blink = buffer.clone();
    let blink_on = Rc::new(Cell::new(false));
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

fn bytes_for_key(key: gtk::gdk::Key, state: gtk::gdk::ModifierType) -> Vec<u8> {
    if state.contains(gtk::gdk::ModifierType::CONTROL_MASK) {
        if let Some(ch) = key.to_unicode() {
            let lower = ch.to_ascii_lowercase();
            if lower.is_ascii_lowercase() {
                return vec![lower as u8 - b'a' + 1];
            }
        }
    }
    match key {
        gtk::gdk::Key::Return | gtk::gdk::Key::KP_Enter => b"\r".to_vec(),
        gtk::gdk::Key::BackSpace => vec![0x7f],
        gtk::gdk::Key::Tab => b"\t".to_vec(),
        gtk::gdk::Key::Escape => vec![0x1b],
        gtk::gdk::Key::Up => b"\x1b[A".to_vec(),
        gtk::gdk::Key::Down => b"\x1b[B".to_vec(),
        gtk::gdk::Key::Right => b"\x1b[C".to_vec(),
        gtk::gdk::Key::Left => b"\x1b[D".to_vec(),
        gtk::gdk::Key::Home => b"\x1b[H".to_vec(),
        gtk::gdk::Key::End => b"\x1b[F".to_vec(),
        gtk::gdk::Key::Page_Up => b"\x1b[5~".to_vec(),
        gtk::gdk::Key::Page_Down => b"\x1b[6~".to_vec(),
        gtk::gdk::Key::Delete => b"\x1b[3~".to_vec(),
        gtk::gdk::Key::ISO_Left_Tab => b"\x1b[Z".to_vec(),
        gtk::gdk::Key::F1 => b"\x1bOP".to_vec(),
        gtk::gdk::Key::F2 => b"\x1bOQ".to_vec(),
        gtk::gdk::Key::F3 => b"\x1bOR".to_vec(),
        gtk::gdk::Key::F4 => b"\x1bOS".to_vec(),
        gtk::gdk::Key::F5 => b"\x1b[15~".to_vec(),
        gtk::gdk::Key::F6 => b"\x1b[17~".to_vec(),
        gtk::gdk::Key::F7 => b"\x1b[18~".to_vec(),
        gtk::gdk::Key::F8 => b"\x1b[19~".to_vec(),
        gtk::gdk::Key::F9 => b"\x1b[20~".to_vec(),
        gtk::gdk::Key::F10 => b"\x1b[21~".to_vec(),
        gtk::gdk::Key::F11 => b"\x1b[23~".to_vec(),
        gtk::gdk::Key::F12 => b"\x1b[24~".to_vec(),
        _ => key
            .to_unicode()
            .map(|ch| ch.to_string().into_bytes())
            .unwrap_or_default(),
    }
}

fn fit_grid(
    container: &impl IsA<gtk::Widget>,
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
    let alloc = container.allocation();
    let layout = view.create_pango_layout(Some("M"));
    let (cell_w, cell_h) = layout.pixel_size();
    if cell_w < 1 || cell_h < 1 || alloc.width() < 1 || alloc.height() < 1 {
        return;
    }
    let cell_changed = glyph.get() != (cell_w, cell_h);
    glyph.set((cell_w, cell_h));
    session.set_cell_px(cell_w as u32, cell_h as u32);
    let usable_w = (alloc.width() - 28).max(cell_w);
    let usable_h = (alloc.height() - 24).max(cell_h);
    let cols = (usable_w / cell_w).clamp(20, 512) as u32;
    let rows = (usable_h / cell_h).clamp(8, 256) as u32;
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

struct PictureLayer {
    images: Vec<TerminalImage>,
    scrollback: i32,
}

fn refresh(
    session: &TerminalSession,
    buffer: &gtk::TextBuffer,
    pictures: &RefCell<PictureLayer>,
    grid: &Cell<(u32, u32)>,
    back: &gtk::DrawingArea,
    front: &gtk::DrawingArea,
) {
    let lines = session.lines();
    let screen = grid.get().1 as i32;
    {
        let mut layer = pictures.borrow_mut();
        layer.scrollback = (lines.len() as i32 - screen).max(0);
        layer.images = session.images();
    }
    buffer.set_text("");
    let table = buffer.tag_table();
    for line in &lines {
        for span in &line.spans {
            insert_span(buffer, &table, span);
        }
        let mut iter = buffer.end_iter();
        buffer.insert(&mut iter, "\n");
    }
    back.queue_draw();
    front.queue_draw();
}

fn insert_span(buffer: &gtk::TextBuffer, table: &gtk::TextTagTable, span: &TerminalSpan) {
    if span.text.is_empty() {
        return;
    }
    let name = format!(
        "wtn-{:06x}-{:06x}-{}{}{}{}{}{}",
        span.fg & 0xFFFFFF,
        span.bg & 0xFFFFFF,
        u8::from(span.bold),
        u8::from(span.italic),
        u8::from(span.underline),
        u8::from(span.blink),
        u8::from(span.strike),
        if span.blink { "-blink" } else { "" }
    );
    let tag = if let Some(tag) = table.lookup(&name) {
        tag
    } else if let Some(tag) = buffer.create_tag(Some(&name), &[]) {
        tag.set_foreground(Some(&css(span.fg)));
        if span.bg != 0 {
            tag.set_background(Some(&css(span.bg)));
        }
        if span.bold {
            tag.set_weight(700);
        }
        if span.italic {
            tag.set_style(gtk::pango::Style::Italic);
        }
        if span.underline {
            tag.set_underline(gtk::pango::Underline::Single);
        }
        if span.strike {
            tag.set_strikethrough(true);
        }
        tag
    } else {
        let mut end = buffer.end_iter();
        buffer.insert(&mut end, &span.text);
        return;
    };
    let mut end = buffer.end_iter();
    buffer.insert_with_tags(&mut end, &span.text, &[&tag]);
}

fn emit_pointer(
    session: &Arc<TerminalSession>,
    master: &Rc<RefCell<File>>,
    glyph: &Cell<(i32, i32)>,
    x: f64,
    y: f64,
    button: u32,
    pressed: bool,
    motion: bool,
) {
    let (cell_w, cell_h) = glyph.get();
    if cell_w < 1 || cell_h < 1 {
        return;
    }
    let col = (x as i32 / cell_w).clamp(0, 511) as u32 + 1;
    let row = (y as i32 / cell_h).clamp(0, 255) as u32 + 1;
    let vt_button = match button {
        2 => 1,
        3 => 2,
        _ => 0,
    };
    session.pointer(vt_button, col, row, pressed, motion);
    let reply = session.take_reply();
    if reply.is_empty() {
        return;
    }
    let mut file = master.borrow_mut();
    let _ = file.write_all(&reply);
}

fn paste_from_clipboard(session: &Arc<TerminalSession>, master: &Rc<RefCell<Option<File>>>) {
    let Some(display) = gtk::gdk::Display::default() else {
        return;
    };
    let session = session.clone();
    let master = master.clone();
    display.clipboard().read_text_async(
        None::<&gtk::gio::Cancellable>,
        move |result| {
            let Ok(Some(text)) = result else {
                return;
            };
            let bytes = session.encode_paste(text.to_string());
            if let Some(file) = master.borrow_mut().as_mut() {
                let _ = file.write_all(&bytes);
            }
        },
    );
}

fn css(rgb: u32) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        (rgb >> 16) & 0xFF,
        (rgb >> 8) & 0xFF,
        rgb & 0xFF
    )
}

fn wire_picture_canvas(
    canvas: &gtk::DrawingArea,
    pictures: &Rc<RefCell<PictureLayer>>,
    glyph: &Rc<Cell<(i32, i32)>>,
    scroll: &gtk::ScrolledWindow,
    behind: bool,
) {
    let pictures = pictures.clone();
    let glyph = glyph.clone();
    let scroll = scroll.clone();
    canvas.set_draw_func(move |_area, cr, _width, _height| {
        if behind {
            let _ = cr.set_source_rgb(0.0, 0.0, 0.0);
            let _ = cr.paint();
        }
        let (cell_w, cell_h) = glyph.get();
        if cell_w < 1 || cell_h < 1 {
            return;
        }
        let layer = pictures.borrow();
        let scroll_y = scroll.vadjustment().value();
        for image in &layer.images {
            let front = image.z >= 0;
            if behind == front {
                continue;
            }
            blit_picture(cr, image, cell_w, cell_h, layer.scrollback, scroll_y);
        }
    });
}

fn blit_picture(
    cr: &gtk::cairo::Context,
    image: &TerminalImage,
    cell_w: i32,
    cell_h: i32,
    scrollback: i32,
    scroll_y: f64,
) {
    let width = image.pixel_width as i32;
    let height = image.pixel_height as i32;
    if width < 1 || height < 1 {
        return;
    }
    let need = (width as usize).saturating_mul(height as usize).saturating_mul(4);
    if image.rgba.len() < need {
        return;
    }
    let Ok(stride) = gtk::cairo::Format::ARgb32.stride_for_width(image.pixel_width) else {
        return;
    };
    let data = rgba_to_cairo(&image.rgba, width as usize, height as usize, stride as usize);
    let Ok(surface) = gtk::cairo::ImageSurface::create_for_data(
        data,
        gtk::cairo::Format::ARgb32,
        width,
        height,
        stride,
    ) else {
        return;
    };
    let x = image.column as f64 * cell_w as f64 + image.x_px as f64;
    let y = (scrollback + image.row) as f64 * cell_h as f64 + image.y_px as f64 - scroll_y;
    let dest_w = image.columns.max(1) as f64 * cell_w as f64;
    let dest_h = image.rows.max(1) as f64 * cell_h as f64;
    let _ = cr.save();
    let _ = cr.translate(x, y);
    let _ = cr.scale(dest_w / width as f64, dest_h / height as f64);
    let _ = cr.set_source_surface(&surface, 0.0, 0.0);
    let _ = cr.paint();
    let _ = cr.restore();
}

fn rgba_to_cairo(rgba: &[u8], width: usize, height: usize, stride: usize) -> Vec<u8> {
    let mut data = vec![0u8; stride.saturating_mul(height)];
    for y in 0..height {
        let src = y * width * 4;
        let dst = y * stride;
        for x in 0..width {
            let i = src + x * 4;
            let a = rgba[i + 3] as u32;
            let r = rgba[i] as u32 * a / 255;
            let g = rgba[i + 1] as u32 * a / 255;
            let b = rgba[i + 2] as u32 * a / 255;
            let pixel = (a << 24) | (r << 16) | (g << 8) | b;
            let o = dst + x * 4;
            data[o..o + 4].copy_from_slice(&pixel.to_ne_bytes());
        }
    }
    data
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spawn_and_read_echo() {
        let (master_fd, slave_fd) = open_pty().expect("open_pty failed");
        let mut child = spawn_on_slave(slave_fd, "echo hello-wawona").expect("spawn failed");
        let mut master = unsafe { File::from_raw_fd(master_fd) };
        let mut buf = [0u8; 128];
        let mut output = Vec::new();
        for _ in 0..50 {
            match master.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => output.extend_from_slice(&buf[..n]),
                Err(err) if err.kind() == ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(_) => break,
            }
            if output.windows(12).any(|w| w == b"hello-wawona") {
                break;
            }
        }
        let _ = child.kill();
        let _ = child.wait();
        let text = String::from_utf8_lossy(&output);
        assert!(text.contains("hello-wawona"), "output was: {text}");
    }

    #[test]
    fn test_spawn_interactive_shell() {
        let (master_fd, slave_fd) = open_pty().expect("open_pty failed");
        let mut child = spawn_on_slave(slave_fd, "wawona-shell").expect("spawn failed");
        let mut master = unsafe { File::from_raw_fd(master_fd) };
        // Send a simple command to the interactive shell
        let _ = master.write_all(b"echo shell-is-alive\n");
        let mut buf = [0u8; 128];
        let mut output = Vec::new();
        for _ in 0..50 {
            match master.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => output.extend_from_slice(&buf[..n]),
                Err(err) if err.kind() == ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(50));
                }
                Err(_) => break,
            }
            if output.windows(14).any(|w| w == b"shell-is-alive") {
                break;
            }
        }
        let _ = child.kill();
        let _ = child.wait();
        let text = String::from_utf8_lossy(&output);
        assert!(text.contains("shell-is-alive"), "output was: {text}");
    }
}

