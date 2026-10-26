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
            if id == "wawona-shell" {
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
        _ => None,
    }
}

/// Open a PTY, start `command`, and present the VT screen.
pub fn open_shell(parent: &impl IsA<gtk::Window>, command: &str) -> Result<Child, String> {
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
    present(parent, session, master, child.id());
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
    }
    Ok((master, slave))
}

fn spawn_on_slave(slave_fd: i32, command: &str) -> Result<Child, String> {
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
    if let Ok(rt) = crate::linux::runtime::read_runtime_state() {
        cmd.env("XDG_RUNTIME_DIR", rt.xdg_runtime_dir);
        cmd.env("WAYLAND_DISPLAY", rt.wayland_display);
    }
    cmd.spawn()
        .map_err(|err| format!("shell failed to start: {err}"))
}

fn present(parent: &impl IsA<gtk::Window>, session: Arc<TerminalSession>, master: File, pid: u32) {
    let window = adw::Window::builder()
        .transient_for(parent)
        .modal(false)
        .default_width(720)
        .default_height(420)
        .title("Wawona Terminal")
        .build();
    a11y::set_wwn_a11y(&window, id::TERMINAL_ROOT, Some("Wawona Terminal"));

    let header = adw::HeaderBar::new();
    let done = gtk::Button::with_label("Done");
    a11y::set_wwn_a11y(&done, id::TERMINAL_DONE, Some("Close Terminal"));
    header.pack_end(&done);

    let view = gtk::TextView::new();
    view.set_editable(false);
    view.set_cursor_visible(false);
    view.set_monospace(true);
    view.set_wrap_mode(gtk::WrapMode::None);
    view.set_focusable(true);
    view.set_can_focus(true);
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
        .build();
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
    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&header);
    root.append(&overlay);
    window.set_content(Some(&root));

    let css = gtk::CssProvider::new();
    css.load_from_data(
        "textview, textview text { background: transparent; color: #e8e8e8; font-family: monospace, \"DejaVuSansM Nerd Font Mono\"; }",
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
    let window_fd = window.clone();
    let dec_modes = Rc::new(RefCell::new(HostDecModes::default()));
    let dec_read = dec_modes.clone();
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
            Ok(0) => glib::ControlFlow::Break,
            Err(err) if err.kind() == ErrorKind::WouldBlock => glib::ControlFlow::Continue,
            Err(_) => glib::ControlFlow::Break,
            Ok(n) => {
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
                let title = session_fd.title();
                if !title.is_empty() {
                    window_fd.set_title(Some(&title));
                }
                let mut end = buffer_fd.end_iter();
                let _ = view_fd.scroll_to_iter(&mut end, 0.0, true, 0.0, 1.0);
                glib::ControlFlow::Continue
            }
        }
    });

    let master_keys = dup_master(fd);
    let session_keys = session.clone();
    let dec_keys = dec_modes.clone();
    let keys = gtk::EventControllerKey::new();
    keys.connect_key_pressed(move |_, key, _, state| {
        if state.contains(gtk::gdk::ModifierType::CONTROL_MASK) {
            if let Some(ch) = key.to_unicode() {
                if ch.eq_ignore_ascii_case(&'v') {
                    paste_from_clipboard(&session_keys, &master_keys);
                    return gtk::glib::Propagation::Stop;
                }
            }
        }
        let bytes = dec_keys.borrow().map_key(key, state, bytes_for_key(key, state));
        if !bytes.is_empty() {
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
    let buffer_fit = buffer.clone();
    let grid_fit = grid.clone();
    let glyph_fit = glyph.clone();
    let pictures_fit = pictures.clone();
    let back_fit = back.clone();
    let front_fit = front.clone();
    window.connect_realize(move |widget| {
        let Some(surface) = widget.surface() else {
            return;
        };
        let session = session_fit.clone();
        let view = view_fit.clone();
        let buffer = buffer_fit.clone();
        let grid = grid_fit.clone();
        let glyph = glyph_fit.clone();
        let pictures = pictures_fit.clone();
        let back = back_fit.clone();
        let front = front_fit.clone();
        surface.connect_layout(move |_, _, _| {
            fit_grid(
                &view,
                &session,
                fd,
                &grid,
                &glyph,
                &buffer,
                &pictures,
                &back,
                &front,
            );
        });
    });
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

    let window_done = window.clone();
    done.connect_clicked(move |_| {
        unsafe { libc::kill(pid as i32, libc::SIGTERM) };
        window_done.close();
    });
    window.present();
    view.grab_focus();
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

fn write_pty(file: &mut File, bytes: &[u8]) {
    let mut sent = 0;
    let mut spins = 0;
    while sent < bytes.len() && spins < 32 {
        match file.write(&bytes[sent..]) {
            Ok(0) => spins += 1,
            Ok(n) => {
                sent += n;
                spins = 0;
            }
            Err(err)
                if err.kind() == ErrorKind::Interrupted || err.kind() == ErrorKind::WouldBlock =>
            {
                spins += 1;
            }
            Err(_) => return,
        }
    }
}

#[derive(Default)]
struct HostDecModes {
    cursor_app: bool,
    keypad_app: bool,
    pending: Vec<u8>,
}

impl HostDecModes {
    fn observe(&mut self, bytes: &[u8]) {
        self.pending.extend_from_slice(bytes);
        let mut i = 0;
        while i < self.pending.len() {
            if self.pending[i] != 0x1b {
                i += 1;
                continue;
            }
            if i + 1 >= self.pending.len() {
                break;
            }
            match self.pending[i + 1] {
                b'c' => {
                    self.cursor_app = false;
                    self.keypad_app = false;
                    i += 2;
                }
                b'=' => {
                    self.keypad_app = true;
                    i += 2;
                }
                b'>' => {
                    self.keypad_app = false;
                    i += 2;
                }
                b'[' => match self.finish_csi(i + 2) {
                    Some(next) => i = next,
                    None => break,
                },
                _ => i += 1,
            }
        }
        if i > 0 {
            self.pending.drain(..i);
        }
        if self.pending.len() > 32 {
            let drop_n = self.pending.len() - 32;
            self.pending.drain(..drop_n);
        }
    }

    fn finish_csi(&mut self, start: usize) -> Option<usize> {
        let mut j = start;
        let mut private = false;
        if j < self.pending.len() && self.pending[j] == b'?' {
            private = true;
            j += 1;
        }
        let mut params = Vec::new();
        let mut cur = 0i32;
        let mut any = false;
        loop {
            if j >= self.pending.len() {
                return None;
            }
            let c = self.pending[j];
            if c.is_ascii_digit() {
                cur = (cur * 10 + i32::from(c - b'0')).min(9999);
                any = true;
                j += 1;
                continue;
            }
            if c == b';' {
                params.push(if any { cur } else { 0 });
                cur = 0;
                any = false;
                j += 1;
                continue;
            }
            if (0x40..=0x7e).contains(&c) {
                params.push(if any { cur } else { 0 });
                if private && (c == b'h' || c == b'l') {
                    if params.contains(&1) {
                        self.cursor_app = c == b'h';
                    }
                    if params.contains(&66) {
                        self.keypad_app = c == b'l';
                    }
                }
                return Some(j + 1);
            }
            return Some(j + 1);
        }
    }

    fn map_key(
        &self,
        key: gtk::gdk::Key,
        state: gtk::gdk::ModifierType,
        bytes: Vec<u8>,
    ) -> Vec<u8> {
        let bare = !state.contains(gtk::gdk::ModifierType::CONTROL_MASK)
            && !state.contains(gtk::gdk::ModifierType::ALT_MASK)
            && !state.contains(gtk::gdk::ModifierType::SHIFT_MASK);
        if bare && self.keypad_app {
            if let Some(letter) = keypad_ss3(key) {
                return vec![0x1b, b'O', letter];
            }
        }
        if self.cursor_app
            && bytes.len() == 3
            && bytes[0] == 0x1b
            && bytes[1] == b'['
            && (b'A'..=b'D').contains(&bytes[2])
        {
            return vec![0x1b, b'O', bytes[2]];
        }
        bytes
    }
}

fn keypad_ss3(key: gtk::gdk::Key) -> Option<u8> {
    Some(match key {
        gtk::gdk::Key::KP_0 => 0x70,
        gtk::gdk::Key::KP_1 => 0x71,
        gtk::gdk::Key::KP_2 => 0x72,
        gtk::gdk::Key::KP_3 => 0x73,
        gtk::gdk::Key::KP_4 => 0x74,
        gtk::gdk::Key::KP_5 => 0x75,
        gtk::gdk::Key::KP_6 => 0x76,
        gtk::gdk::Key::KP_7 => 0x77,
        gtk::gdk::Key::KP_8 => 0x78,
        gtk::gdk::Key::KP_9 => 0x79,
        gtk::gdk::Key::KP_Decimal => 0x6e,
        gtk::gdk::Key::KP_Subtract => 0x6d,
        gtk::gdk::Key::KP_Add => 0x6b,
        gtk::gdk::Key::KP_Multiply => 0x6a,
        gtk::gdk::Key::KP_Divide => 0x6f,
        gtk::gdk::Key::KP_Enter => 0x4d,
        gtk::gdk::Key::KP_Separator => 0x6c,
        gtk::gdk::Key::KP_Equal => 0x58,
        _ => return None,
    })
}

fn bytes_for_key(key: gtk::gdk::Key, state: gtk::gdk::ModifierType) -> Vec<u8> {
    let ctrl = state.contains(gtk::gdk::ModifierType::CONTROL_MASK);
    let alt = state.contains(gtk::gdk::ModifierType::ALT_MASK);
    let shift = state.contains(gtk::gdk::ModifierType::SHIFT_MASK);
    if ctrl {
        if let Some(ch) = key.to_unicode() {
            let upper = ch.to_ascii_uppercase();
            if upper.is_ascii() {
                let ascii = upper as u8;
                if (0x40..=0x5F).contains(&ascii) {
                    let byte = ascii & 0x1F;
                    return if alt { vec![0x1b, byte] } else { vec![byte] };
                }
            }
        }
        let extra = match key {
            gtk::gdk::Key::_2 | gtk::gdk::Key::KP_2 => Some(0x00),
            gtk::gdk::Key::_3 => Some(0x1b),
            gtk::gdk::Key::_4 => Some(0x1c),
            gtk::gdk::Key::_5 => Some(0x1d),
            gtk::gdk::Key::_6 | gtk::gdk::Key::KP_6 => Some(0x1e),
            gtk::gdk::Key::_7 | gtk::gdk::Key::minus | gtk::gdk::Key::KP_Subtract => Some(0x1f),
            gtk::gdk::Key::_8 => Some(0x7f),
            gtk::gdk::Key::slash => Some(if shift { 0x7f } else { 0x1f }),
            gtk::gdk::Key::bracketleft => Some(0x1b),
            gtk::gdk::Key::backslash => Some(0x1c),
            gtk::gdk::Key::bracketright => Some(0x1d),
            _ => None,
        };
        if let Some(byte) = extra {
            return if alt { vec![0x1b, byte] } else { vec![byte] };
        }
    }
    let param = 1 + i32::from(shift) + 2 * i32::from(alt) + 4 * i32::from(ctrl);
    let modified = param != 1;
    match key {
        gtk::gdk::Key::Return | gtk::gdk::Key::KP_Enter => {
            if alt { b"\x1b\r".to_vec() } else { b"\r".to_vec() }
        }
        gtk::gdk::Key::BackSpace => {
            let byte = if ctrl { 0x08 } else { 0x7f };
            if alt { vec![0x1b, byte] } else { vec![byte] }
        }
        gtk::gdk::Key::Tab => {
            if shift {
                b"\x1b[Z".to_vec()
            } else if alt {
                b"\x1b\t".to_vec()
            } else {
                b"\t".to_vec()
            }
        }
        gtk::gdk::Key::Escape => vec![0x1b],
        gtk::gdk::Key::space => {
            if ctrl {
                if alt { vec![0x1b, 0x00] } else { vec![0x00] }
            } else if alt {
                b"\x1b ".to_vec()
            } else {
                b" ".to_vec()
            }
        }
        gtk::gdk::Key::Up | gtk::gdk::Key::KP_Up => csi_letter(b'A', param, modified, b"\x1b[A"),
        gtk::gdk::Key::Down | gtk::gdk::Key::KP_Down => csi_letter(b'B', param, modified, b"\x1b[B"),
        gtk::gdk::Key::Right | gtk::gdk::Key::KP_Right => csi_letter(b'C', param, modified, b"\x1b[C"),
        gtk::gdk::Key::Left | gtk::gdk::Key::KP_Left => csi_letter(b'D', param, modified, b"\x1b[D"),
        gtk::gdk::Key::Home | gtk::gdk::Key::KP_Home => csi_letter(b'H', param, modified, b"\x1b[H"),
        gtk::gdk::Key::End | gtk::gdk::Key::KP_End => csi_letter(b'F', param, modified, b"\x1b[F"),
        gtk::gdk::Key::Page_Up | gtk::gdk::Key::KP_Page_Up => csi_tilde(b'5', param, modified, b"\x1b[5~"),
        gtk::gdk::Key::Page_Down | gtk::gdk::Key::KP_Page_Down => {
            csi_tilde(b'6', param, modified, b"\x1b[6~")
        }
        gtk::gdk::Key::Delete | gtk::gdk::Key::KP_Delete => csi_tilde(b'3', param, modified, b"\x1b[3~"),
        gtk::gdk::Key::KP_Begin => b"\x1b[E".to_vec(),
        gtk::gdk::Key::KP_Divide => kp_ascii(b'/', alt),
        gtk::gdk::Key::KP_Multiply => kp_ascii(b'*', alt),
        gtk::gdk::Key::KP_Subtract => kp_ascii(b'-', alt),
        gtk::gdk::Key::KP_Add => kp_ascii(b'+', alt),
        gtk::gdk::Key::KP_Equal => kp_ascii(b'=', alt),
        gtk::gdk::Key::KP_Separator => kp_ascii(b',', alt),
        gtk::gdk::Key::Insert | gtk::gdk::Key::KP_Insert => {
            csi_tilde(b'2', param, modified, b"\x1b[2~")
        }
        gtk::gdk::Key::Menu => csi_fn("29", param, modified, b"\x1b[29~"),
        gtk::gdk::Key::Find => csi_tilde(b'1', param, modified, b"\x1b[1~"),
        gtk::gdk::Key::Select => csi_tilde(b'4', param, modified, b"\x1b[4~"),
        gtk::gdk::Key::Help => csi_fn("28", param, modified, b"\x1b[28~"),
        gtk::gdk::Key::F1 => csi_letter(b'P', param, modified, b"\x1bOP"),
        gtk::gdk::Key::F2 => csi_letter(b'Q', param, modified, b"\x1bOQ"),
        gtk::gdk::Key::F3 => csi_letter(b'R', param, modified, b"\x1bOR"),
        gtk::gdk::Key::F4 => csi_letter(b'S', param, modified, b"\x1bOS"),
        gtk::gdk::Key::F5 => csi_fn("15", param, modified, b"\x1b[15~"),
        gtk::gdk::Key::F6 => csi_fn("17", param, modified, b"\x1b[17~"),
        gtk::gdk::Key::F7 => csi_fn("18", param, modified, b"\x1b[18~"),
        gtk::gdk::Key::F8 => csi_fn("19", param, modified, b"\x1b[19~"),
        gtk::gdk::Key::F9 => csi_fn("20", param, modified, b"\x1b[20~"),
        gtk::gdk::Key::F10 => csi_fn("21", param, modified, b"\x1b[21~"),
        gtk::gdk::Key::F11 => csi_fn("23", param, modified, b"\x1b[23~"),
        gtk::gdk::Key::F12 => csi_fn("24", param, modified, b"\x1b[24~"),
        gtk::gdk::Key::F13 => csi_fn("25", param, modified, b"\x1b[25~"),
        gtk::gdk::Key::F14 => csi_fn("26", param, modified, b"\x1b[26~"),
        gtk::gdk::Key::F15 => csi_fn("28", param, modified, b"\x1b[28~"),
        gtk::gdk::Key::F16 => csi_fn("29", param, modified, b"\x1b[29~"),
        gtk::gdk::Key::F17 => csi_fn("31", param, modified, b"\x1b[31~"),
        gtk::gdk::Key::F18 => csi_fn("32", param, modified, b"\x1b[32~"),
        gtk::gdk::Key::F19 => csi_fn("33", param, modified, b"\x1b[33~"),
        gtk::gdk::Key::F20 => csi_fn("34", param, modified, b"\x1b[34~"),
        _ => {
            let Some(ch) = key.to_unicode() else {
                return Vec::new();
            };
            let mut bytes = ch.to_string().into_bytes();
            if alt {
                bytes.insert(0, 0x1b);
            }
            bytes
        }
    }
}

fn kp_ascii(byte: u8, alt: bool) -> Vec<u8> {
    if alt { vec![0x1b, byte] } else { vec![byte] }
}

fn csi_letter(letter: u8, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[1;{param}{}", letter as char).into_bytes()
}

fn csi_fn(code: &str, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[{code};{param}~").into_bytes()
}

fn csi_tilde(code: u8, param: i32, modified: bool, plain: &[u8]) -> Vec<u8> {
    if !modified {
        return plain.to_vec();
    }
    format!("\x1b[{};{param}~", code as char).into_bytes()
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
    write_pty(&mut file, &reply);
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
                write_pty(file, &bytes);
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
