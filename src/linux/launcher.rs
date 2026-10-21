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
                if !settings.waypipe_remote_command.trim().is_empty() {
                    settings.waypipe_remote_command.clone()
                } else {
                    "weston-terminal".to_string()
                }
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
            configure_waypipe_command(
                &mut c,
                settings,
                profile.ssh_port as i32,
                &target,
                &remote_cmd,
            );
            c
        }
    };

    cmd.env("XDG_RUNTIME_DIR", &rt.xdg_runtime_dir);
    cmd.env("WAYLAND_DISPLAY", &rt.wayland_display);
    apply_settings_environment(&mut cmd, settings);
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

fn configure_waypipe_command(
    c: &mut Command,
    settings: &LinuxSettings,
    port: i32,
    target: &str,
    remote_cmd: &str,
) {
    let comp = if settings.waypipe_compress_level > 0 {
        format!(
            "{}:{}",
            settings.waypipe_compression, settings.waypipe_compress_level
        )
    } else {
        settings.waypipe_compression.clone()
    };
    c.arg("--compress").arg(comp);
    if settings.waypipe_threads > 0 {
        c.arg("--threads").arg(settings.waypipe_threads.to_string());
    }
    if settings.waypipe_display > 0 {
        c.arg("--display")
            .arg(format!("wayland-{}", settings.waypipe_display));
    }
    if !settings.waypipe_socket.trim().is_empty() {
        c.arg("--socket").arg(settings.waypipe_socket.trim());
    }
    if settings.waypipe_no_gpu {
        c.arg("--no-gpu");
    }
    if settings.waypipe_oneshot {
        c.arg("--oneshot");
    }
    if settings.waypipe_unlink_socket {
        c.arg("--unlink-socket");
    }
    if settings.waypipe_login_shell {
        c.arg("--login-shell");
    }
    if !settings.waypipe_title_prefix.trim().is_empty() {
        c.arg("--title-prefix")
            .arg(settings.waypipe_title_prefix.trim());
    }
    if settings.waypipe_debug {
        c.arg("--debug");
    }
    if settings.waypipe_video != "none" && !settings.waypipe_video.is_empty() {
        let mut v = settings.waypipe_video.clone();
        if !settings.waypipe_video_bpf.is_empty() && settings.waypipe_video_bpf != "0" {
            v.push_str(&format!(":bpf={}", settings.waypipe_video_bpf));
        }
        c.arg("--video").arg(v);
    }
    c.arg("ssh")
        .arg("-p")
        .arg(port.to_string())
        .arg(target)
        .arg(remote_cmd);
}

fn apply_settings_environment(cmd: &mut Command, settings: &LinuxSettings) {
    for name in &settings.environment_unsets {
        cmd.env_remove(name);
    }
    if !settings.compositor_backend.is_empty() && settings.compositor_backend != "auto" {
        let niri_val = match settings.compositor_backend.trim().to_lowercase().as_str() {
            "drm" | "tty" => "tty",
            _ => "nested",
        };
        cmd.env("NIRI_BACKEND", niri_val);
    }
    if !settings.vulkan_driver.is_empty() && settings.vulkan_driver != "auto" {
        cmd.env("VK_ICD_FILENAMES", &settings.vulkan_driver);
        cmd.env("VK_DRIVER_FILES", &settings.vulkan_driver);
        cmd.env("WWN_VULKAN_DRIVER", &settings.vulkan_driver);
    }
    if !settings.opengl_driver.is_empty() && settings.opengl_driver != "auto" {
        cmd.env("WWN_OPENGL_DRIVER", &settings.opengl_driver);
    }
    for (name, value) in &settings.environment_overrides {
        if value.is_empty() {
            cmd.env_remove(name);
        } else {
            cmd.env(name, value);
        }
    }
}

fn apply_profile_runtime_overrides(cmd: &mut Command, profile: &MachineProfile) {
    let ro = &profile.runtime_overrides;
    if let Some(ref backend) = ro.compositor_backend {
        let trimmed = backend.trim();
        if !trimmed.is_empty() && trimmed != "auto" {
            let niri_val = match trimmed.to_lowercase().as_str() {
                "drm" | "tty" => "tty",
                _ => "nested",
            };
            cmd.env("NIRI_BACKEND", niri_val);
        }
    }
    if let Some(ref vk) = ro.vulkan_driver {
        let trimmed = vk.trim();
        if !trimmed.is_empty() && trimmed != "auto" {
            cmd.env("VK_ICD_FILENAMES", trimmed);
            cmd.env("VK_DRIVER_FILES", trimmed);
            cmd.env("WWN_VULKAN_DRIVER", trimmed);
        }
    }
    if let Some(ref gl) = ro.open_gl_driver {
        let trimmed = gl.trim();
        if !trimmed.is_empty() && trimmed != "auto" {
            cmd.env("WWN_OPENGL_DRIVER", trimmed);
        }
    }
    if let Some(ref env_map) = ro.environment {
        for (key, entry) in env_map {
            if entry.action == "unset" {
                cmd.env_remove(key);
            } else if entry.action == "set" {
                if let Some(ref val) = entry.value {
                    if val.is_empty() {
                        cmd.env_remove(key);
                    } else {
                        cmd.env(key, val);
                    }
                } else {
                    cmd.env_remove(key);
                }
            }
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
                if !settings.waypipe_remote_command.trim().is_empty() {
                    settings.waypipe_remote_command.clone()
                } else {
                    "weston-terminal".to_string()
                }
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
            configure_waypipe_command(&mut c, settings, profile.ssh_port, &target, &remote_cmd);
            c
        }
    };

    let wayland_display = profile
        .runtime_overrides
        .wayland_display
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or(&rt.wayland_display);

    cmd.env("XDG_RUNTIME_DIR", &rt.xdg_runtime_dir);
    cmd.env("WAYLAND_DISPLAY", wayland_display);
    apply_settings_environment(&mut cmd, settings);
    apply_profile_runtime_overrides(&mut cmd, profile);
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
    let token = command.split_whitespace().next().unwrap_or(command).trim();
    let base = std::path::Path::new(token)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(token);
    if base != "weston" {
        return command.to_string();
    }
    let Some(data) = crate::core::weston_ini::weston_data_dir() else {
        wlog!(
            "LAUNCHER",
            "weston honeycomb skipped: no share/weston/background.png"
        );
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
