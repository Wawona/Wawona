use std::process::{Child, Command, Stdio};

use anyhow::{Context, Result};

use crate::linux::config::{LinuxMachineProfile, LinuxMachineType, LinuxSettings};
use crate::linux::machine_profile::{MachineProfile, MachineType};
use crate::linux::runtime::RuntimeState;
use crate::wlog;

fn machine_target(profile: &LinuxMachineProfile) -> String {
    if profile.ssh_user.is_empty() {
        profile.ssh_host.clone()
    } else {
        format!("{}@{}", profile.ssh_user, profile.ssh_host)
    }
}

pub fn launch(
    profile: &LinuxMachineProfile,
    settings: &LinuxSettings,
    rt: &RuntimeState,
) -> Result<Child> {
    wlog!(
        "LAUNCHER",
        "Launching profile name={} type={:?} id={}",
        profile.name,
        profile.machine_type,
        profile.id
    );
    wlog!(
        "LAUNCHER",
        "Runtime target WAYLAND_DISPLAY={} XDG_RUNTIME_DIR={}",
        rt.wayland_display,
        rt.xdg_runtime_dir
    );

    let mut cmd = match profile.machine_type {
        LinuxMachineType::Native => {
            let run_cmd = rewrite_weston_honeycomb(
                &rewrite_wasm_command(&profile.effective_command(), None),
                rt,
            );
            wlog!("LAUNCHER", "Native launch command={}", run_cmd);
            let mut c = Command::new("sh");
            c.args(["-c", &run_cmd]);
            c
        }
        LinuxMachineType::SshTerminal => {
            let target = machine_target(profile);
            wlog!(
                "LAUNCHER",
                "SSH terminal target={} port={}",
                target,
                profile.ssh_port
            );
            let mut c = Command::new("ssh");
            c.args(["-p", &profile.ssh_port.to_string(), &target]);
            if !profile.remote_command.trim().is_empty() {
                wlog!("LAUNCHER", "SSH remote command={}", profile.remote_command);
                c.arg(profile.remote_command.clone());
            }
            c
        }
        LinuxMachineType::SshWaypipe => {
            let target = machine_target(profile);
            let remote_cmd = if profile.remote_command.trim().is_empty() {
                "weston-terminal".to_string()
            } else {
                profile.remote_command.clone()
            };
            wlog!(
                "LAUNCHER",
                "Waypipe target={} port={} compress={} remote_cmd={}",
                target,
                profile.ssh_port,
                settings.waypipe_compression,
                remote_cmd
            );
            let mut c = Command::new("waypipe");
            c.arg("--compress")
                .arg(settings.waypipe_compression.clone())
                .arg("ssh")
                .arg("-p")
                .arg(profile.ssh_port.to_string())
                .arg(target)
                .arg(remote_cmd);
            if settings.waypipe_debug {
                wlog!("LAUNCHER", "Waypipe debug enabled");
                c.arg("--debug");
            }
            if settings.waypipe_video != "none" {
                wlog!("LAUNCHER", "Waypipe video={}", settings.waypipe_video);
                c.arg("--video").arg(settings.waypipe_video.clone());
            }
            c
        }
    };

    cmd.env("XDG_RUNTIME_DIR", &rt.xdg_runtime_dir);
    cmd.env("WAYLAND_DISPLAY", &rt.wayland_display);
    apply_environment_overrides(&mut cmd, settings);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::inherit());
    cmd.stderr(Stdio::inherit());

    let child = cmd
        .spawn()
        .with_context(|| format!("failed to launch profile '{}'", profile.name))?;
    wlog!(
        "LAUNCHER",
        "Spawned process pid={} for profile '{}'",
        child.id(),
        profile.name
    );
    Ok(child)
}

fn apply_environment_overrides(cmd: &mut Command, settings: &LinuxSettings) {
    for name in &settings.environment_unsets {
        cmd.env_remove(name);
    }
    for (name, value) in &settings.environment_overrides {
        if value.is_empty() {
            cmd.env_remove(name);
        } else {
            cmd.env(name, value);
        }
    }
}

fn canonical_target(profile: &MachineProfile) -> String {
    if profile.ssh_user.is_empty() {
        profile.ssh_host.clone()
    } else {
        format!("{}@{}", profile.ssh_user, profile.ssh_host)
    }
}

/// Launch a session for a canonical [`MachineProfile`] (the cross-platform
/// schema). Handles all five machine types: Native (local Wayland client),
/// SSH+Waypipe, SSH Terminal, and VM/Container (treated as a local launch
/// command, mirroring how the Apple/Android front-ends spawn their hypervisor
/// or container runtime command).
pub fn launch_profile(
    profile: &MachineProfile,
    settings: &LinuxSettings,
    rt: &RuntimeState,
) -> Result<Child> {
    wlog!(
        "LAUNCHER",
        "Launching canonical profile name={} type={:?} id={}",
        profile.name,
        profile.machine_type,
        profile.id
    );

    let mut cmd = match profile.machine_type {
        MachineType::Native | MachineType::Wasm => {
            let run_cmd = if profile.machine_type == MachineType::Wasm {
                crate::linux::wasm_launch::effective_wasm_command(profile)
            } else {
                rewrite_weston_honeycomb(
                    &rewrite_wasm_command(
                        &profile.effective_command(),
                        profile.runtime_overrides.wasm_module_path.as_deref(),
                    ),
                    rt,
                )
            };
            wlog!("LAUNCHER", "Local launch command={}", run_cmd);
            let mut c = Command::new("sh");
            c.args(["-c", &run_cmd]);
            c
        }
        MachineType::VirtualMachine | MachineType::Container => {
            let kind = if profile.machine_type == MachineType::Container {
                crate::linux::relay::RelayKind::Container
            } else {
                crate::linux::relay::RelayKind::Vm
            };
            let backend = crate::linux::relay::resolve_backend(kind)?;
            wlog!("LAUNCHER", "Relay backend={}", backend.as_str());
            let run_cmd = profile.effective_command();
            if run_cmd.trim().is_empty() {
                anyhow::bail!(
                    "Relay {} needs a guest command. No QEMU fallback",
                    backend.as_str()
                );
            }
            let mut c = Command::new("sh");
            c.args(["-c", &run_cmd]);
            c
        }
        MachineType::SshTerminal => {
            let target = canonical_target(profile);
            wlog!(
                "LAUNCHER",
                "SSH terminal target={} port={}",
                target,
                profile.ssh_port
            );
            let mut c = Command::new("ssh");
            c.args(["-p", &profile.ssh_port.to_string(), &target]);
            if !profile.remote_command.trim().is_empty() {
                c.arg(profile.remote_command.clone());
            }
            c
        }
        MachineType::SshWaypipe => {
            let target = canonical_target(profile);
            let remote_cmd = if profile.remote_command.trim().is_empty() {
                "weston-terminal".to_string()
            } else {
                profile.remote_command.clone()
            };
            wlog!(
                "LAUNCHER",
                "Waypipe target={} port={} compress={} remote_cmd={}",
                target,
                profile.ssh_port,
                settings.waypipe_compression,
                remote_cmd
            );
            let mut c = Command::new("waypipe");
            c.arg("--compress")
                .arg(settings.waypipe_compression.clone())
                .arg("ssh")
                .arg("-p")
                .arg(profile.ssh_port.to_string())
                .arg(target)
                .arg(remote_cmd);
            if settings.waypipe_debug {
                c.arg("--debug");
            }
            if settings.waypipe_video != "none" {
                c.arg("--video").arg(settings.waypipe_video.clone());
            }
            c
        }
    };

    cmd.env("XDG_RUNTIME_DIR", &rt.xdg_runtime_dir);
    cmd.env("WAYLAND_DISPLAY", &rt.wayland_display);
    apply_environment_overrides(&mut cmd, settings);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::inherit());
    cmd.stderr(Stdio::inherit());

    let child = cmd
        .spawn()
        .with_context(|| format!("failed to launch profile '{}'", profile.name))?;
    wlog!(
        "LAUNCHER",
        "Spawned process pid={} for canonical profile '{}'",
        child.id(),
        profile.name
    );
    Ok(child)
}

fn rewrite_wasm_command(command: &str, explicit_wasm: Option<&str>) -> String {
    let token = command.trim();
    if token.starts_with("wasm ") || token.starts_with("wpm ") {
        if token.starts_with("wpm ") {
            return format!(
                "wasm {}",
                crate::linux::wasm_launch::wasm_arg_from_command(token)
            );
        }
        return command.to_string();
    }
    if token != "wawona-wasm" && token != "hello-wasi-gui" && token != "wasm" {
        return command.to_string();
    }
    if let Some(path) = explicit_wasm.map(str::trim).filter(|s| !s.is_empty()) {
        if std::path::Path::new(path).is_file() {
            return format!("wasm {}", shell_quote(path));
        }
    }
    match write_bundled_hello_wasi_gui() {
        Ok(path) => format!("wasm {}", shell_quote(&path)),
        Err(err) => {
            wlog!("LAUNCHER", "hello-wasi-gui extract failed: {err}");
            "wasm hello-wasi-gui.wasm".to_string()
        }
    }
}

fn write_bundled_hello_wasi_gui() -> Result<String> {
    const BYTES: &[u8] = include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/resources/wasm/hello-wasi-gui.wasm"
    ));
    let dest = std::env::temp_dir().join("wawona-hello-wasi-gui.wasm");
    if dest.is_file() && dest.metadata().map(|m| m.len() as usize).unwrap_or(0) == BYTES.len() {
        return Ok(dest.display().to_string());
    }
    std::fs::write(&dest, BYTES).with_context(|| format!("write {}", dest.display()))?;
    Ok(dest.display().to_string())
}

fn shell_quote(path: &str) -> String {
    format!("'{}'", path.replace('\'', "'\\''"))
}

fn rewrite_weston_honeycomb(command: &str, rt: &RuntimeState) -> String {
    let token = command
        .split_whitespace()
        .next()
        .unwrap_or(command)
        .trim();
    let base = std::path::Path::new(token)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(token);
    if base != "weston" {
        return command.to_string();
    }
    let Some(data) = crate::core::weston_ini::weston_data_dir() else {
        wlog!("LAUNCHER", "weston honeycomb skipped: no share/weston/background.png");
        return command.to_string();
    };
    let ini = std::path::Path::new(&rt.xdg_runtime_dir).join("weston.ini");
    match crate::core::weston_ini::write_honeycomb_ini(&ini, &data, false, None, None) {
        Ok(_) => {
            std::env::set_var("WESTON_CONFIG_FILE", &ini);
            crate::core::weston_ini::with_config_arg(command, &ini)
        }
        Err(err) => {
            wlog!("LAUNCHER", "weston honeycomb ini failed: {err}");
            command.to_string()
        }
    }
}
