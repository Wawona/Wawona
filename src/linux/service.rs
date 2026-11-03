use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;
use std::time::Instant;

use anyhow::{bail, Context, Result};

use crate::linux::runtime::{
    ensure_runtime_dir, now_unix_s, write_runtime_env, write_runtime_state, RuntimeState,
};
use crate::util::logging::{BRIDGE, COMPOSITOR, STATE};
use crate::WawonaCore;

fn user_config_home() -> Result<PathBuf> {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        return Ok(PathBuf::from(xdg));
    }
    let home = std::env::var("HOME").context("HOME is not set")?;
    Ok(Path::new(&home).join(".config"))
}

fn systemd_user_dir() -> Result<PathBuf> {
    Ok(user_config_home()?.join("systemd").join("user"))
}

fn autostart_dir() -> Result<PathBuf> {
    Ok(user_config_home()?.join("autostart"))
}

fn write_file(path: &Path, body: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(path, body).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn remove_file_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err).with_context(|| format!("failed to remove {}", path.display())),
    }
}

/// Resolve the flake ref used by systemd units / tray Open.
///
/// Order: `WAWONA_FLAKE` env, cwd with `flake.nix`, common clones under `$HOME`,
/// then `github:Wawona/Wawona`. Never hardcode a developer home path.
pub fn resolve_flake_ref() -> String {
    if let Ok(v) = std::env::var("WAWONA_FLAKE") {
        let trimmed = v.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        if cwd.join("flake.nix").is_file() {
            return cwd.display().to_string();
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        for rel in ["Wawona", "Wawona/Wawona", "src/Wawona", "code/Wawona"] {
            let candidate = Path::new(&home).join(rel);
            if candidate.join("flake.nix").is_file() {
                return candidate.display().to_string();
            }
        }
    }
    "github:Wawona/Wawona".to_string()
}

/// Pure unit body for the compositor host (testable without systemd).
pub fn render_compositor_unit(flake_ref: &str) -> String {
    format!(
        r#"[Unit]
Description=Wawona Nested Compositor Host
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.nix-profile/bin/nix run {flake_ref}#wawona-linux-compositor-host
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
"#
    )
}

/// Pure unit body for the tray applet (testable without systemd).
pub fn render_tray_unit(flake_ref: &str) -> String {
    format!(
        r#"[Unit]
Description=Wawona Linux Tray Applet
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.nix-profile/bin/nix run {flake_ref}#wawona-linux-tray
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
"#
    )
}

/// XDG autostart: compositor host only. Do not relaunch the GTK Machines UI
/// (Linux analog of macOS #223: KeepAlive for the socket, not the GUI).
pub fn render_autostart_desktop(flake_ref: &str) -> String {
    format!(
        r#"[Desktop Entry]
Type=Application
Name=Wawona Linux Compositor Host
Comment=Keep the Wayland socket alive without opening the Machines window
Exec=nix run {flake_ref}#wawona-linux-compositor-host
Terminal=false
X-GNOME-Autostart-enabled=true
"#
    )
}

pub fn install_user_units() -> Result<()> {
    let flake_ref = resolve_flake_ref();
    crate::wlog!(
        COMPOSITOR,
        "Installing user units and autostart files for flake={}",
        flake_ref
    );
    let unit_dir = systemd_user_dir()?;
    fs::create_dir_all(&unit_dir)
        .with_context(|| format!("failed to create {}", unit_dir.display()))?;

    write_file(
        &unit_dir.join("wawona-compositor.service"),
        &render_compositor_unit(&flake_ref),
    )?;
    write_file(
        &unit_dir.join("wawona-tray.service"),
        &render_tray_unit(&flake_ref),
    )?;

    let auto_dir = autostart_dir()?;
    fs::create_dir_all(&auto_dir)
        .with_context(|| format!("failed to create {}", auto_dir.display()))?;
    write_file(
        &auto_dir.join("wawona.desktop"),
        &render_autostart_desktop(&flake_ref),
    )?;

    run_systemctl_user(["daemon-reload"])?;
    crate::wlog!(COMPOSITOR, "User units installed at {}", unit_dir.display());
    Ok(())
}

pub fn run_systemctl_user<I, S>(args: I) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let args_vec: Vec<String> = args.into_iter().map(|a| a.as_ref().to_string()).collect();
    crate::wlog!(COMPOSITOR, "systemctl --user {}", args_vec.join(" "));
    let mut cmd = Command::new("systemctl");
    cmd.arg("--user");
    for arg in &args_vec {
        cmd.arg(arg);
    }
    let output = cmd.output().context("failed to execute systemctl --user")?;
    if output.status.success() {
        crate::wlog!(COMPOSITOR, "systemctl --user succeeded");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        crate::wlog!(COMPOSITOR, "systemctl --user failed: {}", stderr.trim());
        anyhow::bail!("systemctl --user failed: {}", stderr.trim());
    }
}

pub fn service_is_active(name: &str) -> bool {
    let out = Command::new("systemctl")
        .args(["--user", "is-active", name])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output();
    match out {
        Ok(output) => {
            output.status.success() && String::from_utf8_lossy(&output.stdout).trim() == "active"
        }
        Err(_) => false,
    }
}

pub fn start_compositor_service() -> Result<()> {
    crate::wlog!(COMPOSITOR, "Request: start compositor service");
    run_systemctl_user(["start", "wawona-compositor.service"])
}

pub fn stop_compositor_service() -> Result<()> {
    crate::wlog!(COMPOSITOR, "Request: stop compositor service");
    run_systemctl_user(["stop", "wawona-compositor.service"])
}

pub fn restart_compositor_service() -> Result<()> {
    crate::wlog!(COMPOSITOR, "Request: restart compositor service");
    run_systemctl_user(["restart", "wawona-compositor.service"])
}

pub fn start_tray_service() -> Result<()> {
    crate::wlog!(COMPOSITOR, "Request: start tray service");
    run_systemctl_user(["start", "wawona-tray.service"])
}

pub fn stop_tray_service() -> Result<()> {
    crate::wlog!(COMPOSITOR, "Request: stop tray service");
    // Ignore "not loaded". Quit/uninstall should still remove unit files.
    let _ = run_systemctl_user(["stop", "wawona-tray.service"]);
    Ok(())
}

/// Stop tray + compositor user units, disable them, and delete unit/autostart
/// files so systemd / XDG autostart cannot reopen Wawona until reinstalled.
///
/// Mirrors macOS `stopCompositorAndMenuAgents`.
pub fn stop_compositor_and_tray_services() -> Result<()> {
    crate::wlog!(
        COMPOSITOR,
        "Request: stop compositor + tray services and remove autostart"
    );

    // Tray first: unloading our own unit before exit prevents Restart= respawn.
    let _ = run_systemctl_user(["stop", "wawona-tray.service"]);
    let _ = run_systemctl_user(["disable", "wawona-tray.service"]);
    let _ = run_systemctl_user(["stop", "wawona-compositor.service"]);
    let _ = run_systemctl_user(["disable", "wawona-compositor.service"]);

    let unit_dir = systemd_user_dir()?;
    remove_file_if_exists(&unit_dir.join("wawona-tray.service"))?;
    remove_file_if_exists(&unit_dir.join("wawona-compositor.service"))?;
    remove_file_if_exists(&autostart_dir()?.join("wawona.desktop"))?;

    let _ = run_systemctl_user(["daemon-reload"]);
    crate::wlog!(COMPOSITOR, "User units and autostart removed");
    Ok(())
}

/// Alias for Settings / docs: uninstall systemd user units + XDG autostart.
pub fn uninstall_user_units() -> Result<()> {
    stop_compositor_and_tray_services()
}

pub fn run_compositor_host(socket_name: Option<String>) -> Result<()> {
    let runtime_dir = ensure_runtime_dir()?;
    let requested_socket = socket_name
        .clone()
        .unwrap_or_else(|| "wawona-0".to_string());
    crate::wlog!(
        COMPOSITOR,
        "Launching nested compositor host runtime_dir={} socket={}",
        runtime_dir.display(),
        requested_socket
    );
    let socket_candidates: Vec<String> = if socket_name.is_some() {
        vec![requested_socket.clone()]
    } else {
        (0..4).map(|idx| format!("wawona-{idx}")).collect()
    };

    let mut selected_socket = None;
    let mut selected_core = None;
    for candidate in socket_candidates {
        crate::wlog!(BRIDGE, "Creating WawonaCore via direct C API");
        let core = WawonaCore::new();
        core.set_force_ssd(true);
        core.set_advertise_fullscreen_shell(true);
        core.set_output_size(1280, 800, 1.0);
        crate::wlog!(
            COMPOSITOR,
            "Configured default output=1280x800 scale=1.0 force_ssd=true"
        );
        match core.start(Some(candidate.clone())) {
            Ok(_) => {
                crate::wlog!(COMPOSITOR, "Compositor host started socket={}", candidate);
                selected_socket = Some(candidate);
                selected_core = Some(core);
                break;
            }
            Err(err) => {
                crate::wlog!(
                    COMPOSITOR,
                    "Failed to start compositor host socket={} error={}",
                    candidate,
                    err
                );
            }
        }
    }

    let Some(socket_name) = selected_socket else {
        bail!(
            "failed to start compositor host: all socket candidates exhausted (requested={})",
            requested_socket
        );
    };
    let core = selected_core.expect("core should be set when socket is selected");

    write_runtime_env(&runtime_dir, &socket_name)?;
    let socket_path = core.get_socket_path();
    crate::wlog!(
        STATE,
        "Runtime environment exported xdg_runtime_dir={} wayland_display={} socket_path={}",
        runtime_dir.display(),
        socket_name,
        socket_path
    );

    let state = RuntimeState {
        healthy: true,
        pid: std::process::id(),
        mode: "compositor-host".to_string(),
        xdg_runtime_dir: runtime_dir.display().to_string(),
        wayland_display: socket_name.clone(),
        socket_path: socket_path.clone(),
        started_at_unix_s: now_unix_s(),
        dispatch_timeout_ms: 16,
        tick_interval_ms: 8,
        last_tick_unix_s: now_unix_s(),
        last_error: None,
    };
    write_runtime_state(&state)?;
    crate::wlog!(STATE, "Runtime state marked healthy pid={}", state.pid);

    let mut last_persist = Instant::now();
    let mut live_state = state.clone();
    loop {
        if !core.is_running() {
            crate::wlog!(COMPOSITOR, "Core reported not running; exiting host loop");
            break;
        }
        let _had_events = core.dispatch_events(16);
        live_state.last_tick_unix_s = now_unix_s();
        if last_persist.elapsed() >= Duration::from_secs(1) {
            let _ = write_runtime_state(&live_state);
            crate::wtrace!(
                STATE,
                "Heartbeat persisted tick_unix_s={} socket={}",
                live_state.last_tick_unix_s,
                live_state.wayland_display
            );
            last_persist = Instant::now();
        }
        thread::sleep(Duration::from_millis(8));
    }

    let down_state = RuntimeState {
        healthy: false,
        pid: std::process::id(),
        mode: "compositor-host".to_string(),
        xdg_runtime_dir: runtime_dir.display().to_string(),
        wayland_display: socket_name,
        socket_path,
        started_at_unix_s: now_unix_s(),
        dispatch_timeout_ms: 16,
        tick_interval_ms: 8,
        last_tick_unix_s: now_unix_s(),
        last_error: Some("host loop exited".to_string()),
    };
    write_runtime_state(&down_state)?;
    crate::wlog!(
        STATE,
        "Runtime state marked unhealthy reason={}",
        down_state.last_error.as_deref().unwrap_or("unknown")
    );
    crate::wlog!(COMPOSITOR, "Compositor host shutdown complete");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_flake_ref_prefers_wawona_flake_env() {
        let prev = std::env::var("WAWONA_FLAKE").ok();
        std::env::set_var("WAWONA_FLAKE", "github:Wawona/Wawona/development");
        assert_eq!(
            resolve_flake_ref(),
            "github:Wawona/Wawona/development".to_string()
        );
        match prev {
            Some(v) => std::env::set_var("WAWONA_FLAKE", v),
            None => std::env::remove_var("WAWONA_FLAKE"),
        }
    }

    #[test]
    fn resolve_flake_ref_never_hardcodes_alex_home() {
        let prev = std::env::var("WAWONA_FLAKE").ok();
        std::env::remove_var("WAWONA_FLAKE");
        let resolved = resolve_flake_ref();
        assert!(
            !resolved.contains("/home/alex"),
            "resolved flake must not hardcode /home/alex, got {resolved}"
        );
        match prev {
            Some(v) => std::env::set_var("WAWONA_FLAKE", v),
            None => std::env::remove_var("WAWONA_FLAKE"),
        }
    }

    #[test]
    fn compositor_unit_targets_graphical_session_not_default() {
        let unit = render_compositor_unit("github:Wawona/Wawona");
        assert!(unit.contains("WantedBy=graphical-session.target"));
        assert!(!unit.contains("WantedBy=default.target"));
        assert!(unit.contains("#wawona-linux-compositor-host"));
    }

    #[test]
    fn tray_unit_targets_graphical_session() {
        let unit = render_tray_unit("/tmp/Wawona");
        assert!(unit.contains("WantedBy=graphical-session.target"));
        assert!(unit.contains("#wawona-linux-tray"));
    }

    #[test]
    fn autostart_starts_compositor_host_not_gui() {
        let desktop = render_autostart_desktop("github:Wawona/Wawona");
        let exec = desktop
            .lines()
            .find(|l| l.starts_with("Exec="))
            .expect("desktop must have Exec=");
        assert!(
            exec.ends_with("#wawona-linux-compositor-host"),
            "autostart must keep the Wayland socket, got {exec}"
        );
        assert!(
            !exec.ends_with("#wawona-linux"),
            "autostart must not reopen the GTK Machines UI, got {exec}"
        );
    }
}
