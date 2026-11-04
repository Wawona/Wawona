//! PTY launch and window present for Linux Wawona Terminal.

use std::fs::File;
use std::os::unix::io::FromRawFd;
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::Arc;

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;

use crate::linux::machine_profile::{MachineProfile, MachineType};
use crate::term::TerminalSession;

use super::view::build_terminal_view;

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
            if id == "wawona-wasm"
                || id == "hello-wasi-gui"
                || profile.runtime_overrides.wasm_command.is_some()
                || profile.runtime_overrides.wasm_module_path.is_some()
            {
                Some(crate::linux::wasm_launch::effective_wasm_command(profile))
            } else if id == "wawona-shell"
                || id.is_empty()
                || !profile.remote_command.trim().is_empty()
            {
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
        MachineType::VirtualMachine | MachineType::Container => None,
        _ => None,
    }
}

/// How Start fills Wawona Terminal.
#[derive(Clone, Debug)]
pub enum TerminalLaunch {
    /// Host login shell. Native Shell, SSH, and Wasm.
    Shell(String),
    /// Guest serial console, never a host login shell.
    Guest {
        argv: Vec<String>,
        role: &'static str,
    },
}

pub fn terminal_launch(profile: &MachineProfile) -> Option<TerminalLaunch> {
    match profile.machine_type {
        MachineType::VirtualMachine | MachineType::Container => {
            let guest = crate::linux::relay::guest_terminal(profile);
            Some(TerminalLaunch::Guest {
                argv: guest.argv,
                role: guest.role,
            })
        }
        _ => shell_command(profile).map(TerminalLaunch::Shell),
    }
}

pub fn launch_subtitle(launch: &TerminalLaunch) -> &'static str {
    match launch {
        TerminalLaunch::Shell(_) => "Wawona Terminal (xterm-256color)",
        TerminalLaunch::Guest { role, .. } => role,
    }
}

pub fn start_shell(command: &str) -> Result<(Child, Arc<TerminalSession>, File), String> {
    start_terminal(&TerminalLaunch::Shell(command.to_string()))
}

pub fn start_terminal(
    launch: &TerminalLaunch,
) -> Result<(Child, Arc<TerminalSession>, File), String> {
    let (master_fd, slave_fd) = open_pty()?;
    let child = match launch {
        TerminalLaunch::Shell(command) => spawn_on_slave(slave_fd, command),
        TerminalLaunch::Guest { argv, .. } => spawn_direct(slave_fd, argv),
    };
    let child = match child {
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

/// Open a PTY and present the terminal window for a machine launch.
pub fn open_launched(
    parent: &impl IsA<gtk::Window>,
    launch: &TerminalLaunch,
    title: &str,
) -> Result<Child, String> {
    let (child, session, master) = start_terminal(launch)?;
    present(parent, session, master, child.id(), title);
    Ok(child)
}

/// Open a PTY, start `command`, and present the VT screen.
pub fn open_shell(parent: &impl IsA<gtk::Window>, command: &str) -> Result<Child, String> {
    open_launched(
        parent,
        &TerminalLaunch::Shell(command.to_string()),
        "Wawona Terminal",
    )
}

fn quote_sh(text: &str) -> String {
    if text.contains('\'') {
        format!("\"{}\"", text.replace('"', "\\\""))
    } else {
        format!("'{text}'")
    }
}

fn spawn_direct(slave_fd: i32, argv: &[String]) -> Result<Child, String> {
    let program = argv
        .first()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "guest console has no program".to_string())?;
    let slave = unsafe { File::from_raw_fd(slave_fd) };
    let stdin = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let stdout = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let mut command = Command::new(program);
    command
        .args(&argv[1..])
        .stdin(stdin)
        .stdout(stdout)
        .stderr(Stdio::from(slave))
        .env("TERM", "xterm-256color");
    command
        .spawn()
        .map_err(|err| format!("guest console failed to start: {err}"))
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

fn spawn_on_slave(slave_fd: i32, shell_command: &str) -> Result<Child, String> {
    let slave = unsafe { File::from_raw_fd(slave_fd) };
    let stdin = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let stdout = slave
        .try_clone()
        .map_err(|err| err.to_string())
        .map(Stdio::from)?;
    let mut command = if shell_command == "wawona-shell" {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/bash".to_string());
        let mut command = Command::new(shell);
        command.arg("-i");
        command
    } else {
        let mut command = Command::new("/bin/sh");
        command.args(["-c", shell_command]);
        command
    };
    command
        .stdin(stdin)
        .stdout(stdout)
        .stderr(Stdio::from(slave))
        .env("TERM", "xterm-256color");
    if let Ok(runtime) = crate::linux::runtime::read_runtime_state() {
        command.env("XDG_RUNTIME_DIR", runtime.xdg_runtime_dir);
        command.env("WAYLAND_DISPLAY", runtime.wayland_display);
    }
    command
        .spawn()
        .map_err(|err| format!("shell failed to start: {err}"))
}

fn present(
    parent: &impl IsA<gtk::Window>,
    session: Arc<TerminalSession>,
    master: File,
    pid: u32,
    title: &str,
) {
    let window = adw::Window::builder()
        .transient_for(parent)
        .modal(false)
        .default_width(720)
        .default_height(420)
        .title(title)
        .build();
    let close_window: Rc<dyn Fn()> = Rc::new({
        let window = window.clone();
        move || window.close()
    });
    let stop_window: Rc<dyn Fn()> = Rc::new({
        let window = window.clone();
        move || window.close()
    });
    let terminal = build_terminal_view(
        session,
        master,
        pid,
        title,
        "Wawona Terminal (xterm-256color)",
        close_window,
        stop_window,
    );
    window.set_content(Some(&terminal));
    window.present();
}

