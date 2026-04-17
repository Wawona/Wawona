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
            selected_launcher: "weston-terminal".to_string(),
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
                    "weston-terminal".to_string()
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LinuxSettings {
    // Display
    pub wayland_display: String,
    pub auto_scale: bool,
    // Input
    pub input_profile: String,
    pub key_repeat: u32,
    // Graphics
    pub renderer: String,
    pub force_ssd: bool,
    pub color_operations: bool,
    // Connection
    pub ssh_host: String,
    pub ssh_user: String,
    pub ssh_port: u16,
    pub ssh_password: String,
    pub ssh_auth_method: String,
    pub ssh_key_path: String,
    // Waypipe
    pub waypipe_compression: String,
    pub waypipe_video: String,
    pub waypipe_debug: bool,
    pub waypipe_enabled: bool,
    // Advanced
    pub log_level: String,
}

impl Default for LinuxSettings {
    fn default() -> Self {
        Self {
            wayland_display: "wawona-0".to_string(),
            auto_scale: true,
            input_profile: "direct".to_string(),
            key_repeat: 30,
            renderer: "vulkan".to_string(),
            force_ssd: true,
            color_operations: false,
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            ssh_auth_method: "public_key".to_string(),
            ssh_key_path: "~/.ssh/id_ed25519".to_string(),
            waypipe_compression: "lz4".to_string(),
            waypipe_video: "none".to_string(),
            waypipe_debug: false,
            waypipe_enabled: true,
            log_level: "info".to_string(),
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
    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
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
    fs::write(&path, serialized)
        .with_context(|| format!("failed to write {}", path.display()))?;
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
    fn native_effective_command_prefers_custom_command_override() {
        let mut profile = LinuxMachineProfile::new("Local");
        profile.machine_type = LinuxMachineType::Native;
        profile.selected_launcher = "weston-terminal".to_string();
        profile.remote_command = "foot --server".to_string();

        assert_eq!(profile.effective_command(), "foot --server");
    }
}
