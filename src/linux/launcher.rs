use std::process::{Child, Command, Stdio};

use anyhow::{Context, Result};

use crate::linux::config::{LinuxMachineProfile, LinuxMachineType, LinuxSettings};
use crate::linux::runtime::RuntimeState;
use crate::wlog;

fn machine_target(profile: &LinuxMachineProfile) -> String {
    if profile.ssh_user.is_empty() {
        profile.ssh_host.clone()
    } else {
        format!("{}@{}", profile.ssh_user, profile.ssh_host)
    }
}

pub fn launch(profile: &LinuxMachineProfile, settings: &LinuxSettings, rt: &RuntimeState) -> Result<Child> {
    wlog!("LAUNCHER", "Launching profile name={} type={:?} id={}",
        profile.name, profile.machine_type, profile.id);
    wlog!("LAUNCHER", "Runtime target WAYLAND_DISPLAY={} XDG_RUNTIME_DIR={}",
        rt.wayland_display, rt.xdg_runtime_dir);

    let mut cmd = match profile.machine_type {
        LinuxMachineType::Native => {
            let run_cmd = profile.effective_command();
            wlog!("LAUNCHER", "Native launch command={}", run_cmd);
            let mut c = Command::new("sh");
            c.args(["-c", &run_cmd]);
            c
        }
        LinuxMachineType::SshTerminal => {
            let target = machine_target(profile);
            wlog!("LAUNCHER", "SSH terminal target={} port={}", target, profile.ssh_port);
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
            wlog!("LAUNCHER", "Waypipe target={} port={} compress={} remote_cmd={}",
                target, profile.ssh_port, settings.waypipe_compression, remote_cmd);
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
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::inherit());
    cmd.stderr(Stdio::inherit());

    let child = cmd.spawn()
        .with_context(|| format!("failed to launch profile '{}'", profile.name))?;
    wlog!("LAUNCHER", "Spawned process pid={} for profile '{}'", child.id(), profile.name);
    Ok(child)
}
