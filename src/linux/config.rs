use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LinuxMachineType {
    Native,
    SshWaypipe,
    SshTerminal,
}

impl Default for LinuxMachineType {
    fn default() -> Self {
        Self::Native
    }
}

impl LinuxMachineType {
    pub fn user_facing_name(&self) -> &'static str {
        match self {
            Self::Native => "Native",
            Self::SshWaypipe => "SSH + Waypipe",
            Self::SshTerminal => "SSH Terminal",
        }
    }
}

/// Wayland client presets for native machine type (mirrors `ClientLauncher.presets` from SwiftUI).
pub const LAUNCHER_PRESETS: &[(&str, &str)] = &[
    ("wawona-shell", "Native Shell"),
    ("weston-terminal", "Weston Terminal"),
    ("weston-simple-shm", "Weston Simple SHM"),
    ("foot", "Foot Terminal"),
    ("weston", "Weston"),
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinuxMachineProfile {
    pub id: String,
    pub name: String,
    pub machine_type: LinuxMachineType,
    pub selected_launcher: String,
    pub ssh_host: String,
    pub ssh_user: String,
    pub ssh_port: u16,
    pub ssh_password: String,
    pub remote_command: String,
}

impl LinuxMachineProfile {
    pub fn new(name: &str) -> Self {
        Self {
            id: generate_id(),
            name: name.to_string(),
            machine_type: LinuxMachineType::Native,
            selected_launcher: "wawona-shell".to_string(),
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            remote_command: String::new(),
        }
    }

    pub fn summary(&self) -> String {
        match self.machine_type {
            LinuxMachineType::Native => "Nested local Wayland client".to_string(),
            LinuxMachineType::SshWaypipe | LinuxMachineType::SshTerminal => {
                format!("{}@{}:{}", self.ssh_user, self.ssh_host, self.ssh_port)
            }
        }
    }

    pub fn effective_command(&self) -> String {
        match self.machine_type {
            LinuxMachineType::Native => {
                let custom_command = self.remote_command.trim();
                if !custom_command.is_empty() {
                    custom_command.to_string()
                } else if self.selected_launcher.trim().is_empty() {
                    "wawona-shell".to_string()
                } else {
                    self.selected_launcher.clone()
                }
            }
            _ => self.remote_command.clone(),
        }
    }
}

fn generate_id() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let r: u32 = (ts as u32).wrapping_mul(2654435761);
    format!("{ts:X}-{r:08X}")
}

fn default_true() -> bool {
    true
}
fn default_compositor_backend() -> String {
    "auto".to_string()
}
fn default_vulkan_driver() -> String {
    "system".to_string()
}
fn default_opengl_driver() -> String {
    "system".to_string()
}
fn default_tcp_port() -> u16 {
    6000
}
fn default_ssh_key_type() -> String {
    "ed25519".to_string()
}
fn default_vm_vsock_port() -> u32 {
    1024
}
fn default_container_image_store() -> String {
    "~/.local/share/wawona/oci".to_string()
}
fn default_compress_level() -> u32 {
    7
}
fn default_video_encoding() -> String {
    "hw".to_string()
}
fn default_video_decoding() -> String {
    "hw".to_string()
}
fn default_start_behavior() -> String {
    "prompt".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinuxSettings {
    // Display
    pub wayland_display: String,
    pub auto_scale: bool,
    #[serde(default = "default_compositor_backend")]
    pub compositor_backend: String,
    #[serde(default = "default_true")]
    pub nested_compositors: bool,
    #[serde(default = "default_true")]
    pub multiple_clients: bool,

    // Input
    pub input_profile: String,
    pub key_repeat: u32,
    #[serde(default)]
    pub touch_pointer_emulation: bool,
    #[serde(default)]
    pub show_virtual_cursor: bool,
    #[serde(default = "default_true")]
    pub universal_clipboard: bool,

    // Graphics
    pub renderer: String,
    pub force_ssd: bool,
    pub color_operations: bool,
    #[serde(default = "default_vulkan_driver")]
    pub vulkan_driver: String,
    #[serde(default = "default_opengl_driver")]
    pub opengl_driver: String,
    #[serde(default = "default_true")]
    pub dmabuf_enabled: bool,

    // Connection
    #[serde(default = "default_tcp_port")]
    pub tcp_port: u16,
    pub ssh_host: String,
    pub ssh_user: String,
    pub ssh_port: u16,
    pub ssh_password: String,
    pub ssh_auth_method: String,
    pub ssh_key_path: String,
    #[serde(default)]
    pub ssh_key_passphrase: String,
    #[serde(default = "default_ssh_key_type")]
    pub ssh_key_type: String,

    // Machines defaults
    #[serde(default = "default_true")]
    pub session_thumbnails: bool,
    #[serde(default)]
    pub shake_to_close: bool,
    #[serde(default)]
    pub swipe_back_to_close: bool,
    #[serde(default = "default_vm_vsock_port")]
    pub vm_vsock_port: u32,
    #[serde(default = "default_container_image_store")]
    pub container_image_store: String,
    #[serde(default = "default_start_behavior")]
    pub start_behavior: String,

    // Waypipe
    pub waypipe_compression: String,
    pub waypipe_video: String,
    pub waypipe_debug: bool,
    pub waypipe_enabled: bool,
    #[serde(default)]
    pub waypipe_display: u32,
    #[serde(default)]
    pub waypipe_socket: String,
    #[serde(default = "default_compress_level")]
    pub waypipe_compress_level: u32,
    #[serde(default)]
    pub waypipe_threads: u32,
    #[serde(default = "default_video_encoding")]
    pub waypipe_video_encoding: String,
    #[serde(default = "default_video_decoding")]
    pub waypipe_video_decoding: String,
    #[serde(default)]
    pub waypipe_video_bpf: String,
    #[serde(default)]
    pub waypipe_no_gpu: bool,
    #[serde(default)]
    pub waypipe_oneshot: bool,
    #[serde(default)]
    pub waypipe_unlink_socket: bool,
    #[serde(default)]
    pub waypipe_login_shell: bool,
    #[serde(default)]
    pub waypipe_title_prefix: String,
    #[serde(default)]
    pub waypipe_remote_command: String,

    // Advanced
    pub log_level: String,
    /// Global environment overrides (#157): name → value. Empty value means unset.
    #[serde(default)]
    pub environment_overrides: std::collections::BTreeMap<String, String>,
    /// Names to unset even if present in the host environment.
    #[serde(default)]
    pub environment_unsets: Vec<String>,
    /// First-launch welcome alert dismissed (`wawona-welcome-alert`).
    #[serde(default)]
    pub has_seen_welcome: bool,
}

impl Default for LinuxSettings {
    fn default() -> Self {
        Self {
            wayland_display: "wawona-0".to_string(),
            auto_scale: true,
            compositor_backend: "auto".to_string(),
            nested_compositors: true,
            multiple_clients: true,
            input_profile: "direct".to_string(),
            key_repeat: 30,
            touch_pointer_emulation: false,
            show_virtual_cursor: false,
            universal_clipboard: true,
            renderer: "vulkan".to_string(),
            force_ssd: true,
            color_operations: false,
            vulkan_driver: "system".to_string(),
            opengl_driver: "system".to_string(),
            dmabuf_enabled: true,
            tcp_port: 6000,
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            ssh_auth_method: "public_key".to_string(),
            ssh_key_path: "~/.ssh/id_ed25519".to_string(),
            ssh_key_passphrase: String::new(),
            ssh_key_type: "ed25519".to_string(),
            session_thumbnails: true,
            shake_to_close: false,
            swipe_back_to_close: false,
            vm_vsock_port: 1024,
            container_image_store: "~/.local/share/wawona/oci".to_string(),
            start_behavior: "prompt".to_string(),
            waypipe_compression: "lz4".to_string(),
            waypipe_video: "none".to_string(),
            waypipe_debug: false,
            waypipe_enabled: true,
            waypipe_display: 0,
            waypipe_socket: String::new(),
            waypipe_compress_level: 7,
            waypipe_threads: 0,
            waypipe_video_encoding: "hw".to_string(),
            waypipe_video_decoding: "hw".to_string(),
            waypipe_video_bpf: String::new(),
            waypipe_no_gpu: false,
            waypipe_oneshot: false,
            waypipe_unlink_socket: false,
            waypipe_login_shell: false,
            waypipe_title_prefix: String::new(),
            waypipe_remote_command: String::new(),
            log_level: "info".to_string(),
            environment_overrides: std::collections::BTreeMap::new(),
            environment_unsets: Vec::new(),
            has_seen_welcome: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinuxAppConfig {
    pub schema_version: u32,
    pub selected_machine_id: Option<String>,
    pub machines: Vec<LinuxMachineProfile>,
    pub settings: LinuxSettings,
}

impl Default for LinuxAppConfig {
    fn default() -> Self {
        Self {
            schema_version: 2,
            selected_machine_id: None,
            machines: vec![],
            settings: LinuxSettings::default(),
        }
    }
}

pub fn config_path() -> Result<PathBuf> {
    let base = if let Ok(custom) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(custom)
    } else {
        let home = std::env::var("HOME").context("HOME is not set")?;
        Path::new(&home).join(".config")
    };
    Ok(base.join("wawona").join("linux-config-v1.json"))
}

pub fn load_or_default() -> Result<LinuxAppConfig> {
    let path = config_path()?;
    if !path.exists() {
        return Ok(LinuxAppConfig::default());
    }
    let text =
        fs::read_to_string(&path).with_context(|| format!("failed to read {}", path.display()))?;
    let cfg: LinuxAppConfig = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse {}", path.display()))?;

    let mut migrated = cfg;
    if migrated.settings.wayland_display == "wayland-0" {
        migrated.settings.wayland_display = "wawona-0".to_string();
    }
    if migrated.schema_version < 2 {
        migrated.schema_version = 2;
        for m in &mut migrated.machines {
            if m.selected_launcher.is_empty() && m.machine_type == LinuxMachineType::Native {
                m.selected_launcher = if m.remote_command.is_empty() {
                    "weston-terminal".to_string()
                } else {
                    m.remote_command.clone()
                };
            }
        }
    }
    Ok(migrated)
}

pub fn save(cfg: &LinuxAppConfig) -> Result<()> {
    let path = config_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    let serialized = serde_json::to_string_pretty(cfg)?;
    fs::write(&path, serialized).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{LinuxMachineProfile, LinuxMachineType};

    #[test]
    fn native_effective_command_uses_selected_launcher_by_default() {
        let mut profile = LinuxMachineProfile::new("Local");
        profile.selected_launcher = "foot".to_string();
        profile.remote_command.clear();

        assert_eq!(profile.effective_command(), "foot");
    }

    #[test]
    fn test_settings_persistence_display_backend_and_waypipe_threads() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let path = tmp.path().join("linux-config-v1.json");

        let mut cfg = super::LinuxAppConfig::default();
        cfg.settings.compositor_backend = "drm".to_string();
        cfg.settings.waypipe_threads = 4;

        let json = serde_json::to_string_pretty(&cfg).expect("serialize");
        std::fs::write(&path, &json).expect("write");

        let loaded_text = std::fs::read_to_string(&path).expect("read");
        let loaded: super::LinuxAppConfig =
            serde_json::from_str(&loaded_text).expect("deserialize");

        assert_eq!(loaded.settings.compositor_backend, "drm");
        assert_eq!(loaded.settings.waypipe_threads, 4);
    }
}
