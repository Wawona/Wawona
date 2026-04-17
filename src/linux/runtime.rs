use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeState {
    pub healthy: bool,
    pub pid: u32,
    pub mode: String,
    pub xdg_runtime_dir: String,
    pub wayland_display: String,
    pub socket_path: String,
    pub started_at_unix_s: u64,
    pub dispatch_timeout_ms: u32,
    pub tick_interval_ms: u32,
    pub last_tick_unix_s: u64,
    pub last_error: Option<String>,
}

pub fn ensure_runtime_dir() -> Result<PathBuf> {
    if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
        let path = PathBuf::from(&dir);
        fs::create_dir_all(&path).with_context(|| format!("failed creating {}", dir))?;
        return Ok(path);
    }

    let uid = unsafe { libc::getuid() };
    let fallback = PathBuf::from(format!("/tmp/wawona-{uid}"));
    fs::create_dir_all(&fallback)
        .with_context(|| format!("failed creating {}", fallback.display()))?;
    std::env::set_var("XDG_RUNTIME_DIR", &fallback);
    Ok(fallback)
}

pub fn runtime_state_path(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("wawona-runtime-state.json")
}

pub fn runtime_env_path(runtime_dir: &Path) -> PathBuf {
    runtime_dir.join("wawona-env.sh")
}

pub fn write_runtime_state(state: &RuntimeState) -> Result<()> {
    let runtime_dir = PathBuf::from(&state.xdg_runtime_dir);
    fs::create_dir_all(&runtime_dir)?;
    let path = runtime_state_path(&runtime_dir);
    fs::write(&path, serde_json::to_string_pretty(state)?)
        .with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

pub fn write_runtime_env(runtime_dir: &Path, wayland_display: &str) -> Result<()> {
    let env_path = runtime_env_path(runtime_dir);
    let script = format!(
        "#!/bin/sh\nexport XDG_RUNTIME_DIR=\"{}\"\nexport WAYLAND_DISPLAY=\"{}\"\n",
        runtime_dir.display(),
        wayland_display
    );
    fs::write(&env_path, script).with_context(|| format!("failed to write {}", env_path.display()))?;
    Ok(())
}

pub fn read_runtime_state() -> Result<RuntimeState> {
    let runtime_dir = ensure_runtime_dir()?;
    let path = runtime_state_path(&runtime_dir);
    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let state = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(state)
}

pub fn now_unix_s() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
