//! Canonical machine-profile persistence for Linux.
//!
//! Stores the shared `wawona.machineProfiles.v1` payload as a JSON array at
//! `~/.config/wawona/machine-profiles-v1.json` (byte-compatible with what the
//! Apple/Android `MachineProfileStore` writes) plus the active machine id at
//! `~/.config/wawona/active-machine-id-v1`. On first run it migrates the legacy
//! `linux-config-v1.json` (`LinuxAppConfig` in `config.rs`) into the canonical
//! schema, leaving the old file untouched as a backup.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

use crate::linux::config::{self, LinuxMachineType};
use crate::linux::machine_profile::{MachineProfile, MachineType};

/// Schema key parity with Apple/Android (`UserDefaults`/`SharedPreferences`).
pub const PROFILES_KEY: &str = "wawona.machineProfiles.v1";
pub const ACTIVE_MACHINE_ID_KEY: &str = "wawona.activeMachineId.v1";

fn base_dir() -> Result<PathBuf> {
    let base = if let Ok(custom) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(custom)
    } else {
        let home = std::env::var("HOME").context("HOME is not set")?;
        Path::new(&home).join(".config")
    };
    Ok(base.join("wawona"))
}

/// Path to the canonical `[MachineProfile]` JSON array.
pub fn profiles_path() -> Result<PathBuf> {
    Ok(base_dir()?.join("machine-profiles-v1.json"))
}

/// Path to the active-machine-id marker file.
pub fn active_machine_path() -> Result<PathBuf> {
    Ok(base_dir()?.join("active-machine-id-v1"))
}

/// In-memory canonical store mirroring Swift `MachineProfileStore`.
#[derive(Debug, Clone, Default)]
pub struct ProfileStore {
    pub profiles: Vec<MachineProfile>,
    pub active_machine_id: Option<String>,
}

impl ProfileStore {
    /// Load canonical profiles, migrating from the legacy Linux config on first
    /// run. Never fails on a missing store (returns empty).
    pub fn load() -> Result<Self> {
        let path = profiles_path()?;
        if path.exists() {
            let text = fs::read_to_string(&path)
                .with_context(|| format!("failed to read {}", path.display()))?;
            let profiles: Vec<MachineProfile> = serde_json::from_str(&text)
                .with_context(|| format!("failed to parse {}", path.display()))?;
            let active = read_active_id()?;
            return Ok(Self {
                profiles,
                active_machine_id: active,
            });
        }

        // No canonical store yet: migrate from legacy linux-config-v1.json.
        let migrated = migrate_from_legacy()?;
        if let Some(store) = migrated {
            store.save()?;
            return Ok(store);
        }

        Ok(Self::default())
    }

    /// Persist the canonical array + active id.
    pub fn save(&self) -> Result<()> {
        let path = profiles_path()?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        let serialized = serde_json::to_string_pretty(&self.profiles)?;
        fs::write(&path, serialized)
            .with_context(|| format!("failed to write {}", path.display()))?;
        write_active_id(self.active_machine_id.as_deref())?;
        Ok(())
    }

    /// Insert or replace a profile by id, then persist (mirrors Swift `upsert`).
    pub fn upsert(&mut self, profile: MachineProfile) -> Result<()> {
        if let Some(idx) = self.profiles.iter().position(|p| p.id == profile.id) {
            self.profiles[idx] = profile;
        } else {
            self.profiles.push(profile);
        }
        self.save()
    }

    /// Delete a profile by id, clearing the active id if it matched.
    pub fn delete(&mut self, id: &str) -> Result<()> {
        self.profiles.retain(|p| p.id != id);
        if self.active_machine_id.as_deref() == Some(id) {
            self.active_machine_id = None;
        }
        self.save()
    }

    pub fn profile(&self, id: &str) -> Option<&MachineProfile> {
        self.profiles.iter().find(|p| p.id == id)
    }

    pub fn set_active(&mut self, id: Option<String>) -> Result<()> {
        self.active_machine_id = id;
        self.save()
    }
}

fn read_active_id() -> Result<Option<String>> {
    let path = active_machine_path()?;
    if !path.exists() {
        return Ok(None);
    }
    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let trimmed = text.trim();
    Ok(if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    })
}

fn write_active_id(id: Option<&str>) -> Result<()> {
    let path = active_machine_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::write(&path, id.unwrap_or("")).with_context(|| {
        format!("failed to write {}", path.display())
    })?;
    Ok(())
}

/// Convert a legacy `LinuxAppConfig` into canonical profiles. Returns `None`
/// when there is no legacy file to migrate.
pub fn migrate_from_legacy() -> Result<Option<ProfileStore>> {
    let legacy_path = config::config_path()?;
    if !legacy_path.exists() {
        return Ok(None);
    }
    let legacy = config::load_or_default()?;
    let profiles = legacy
        .machines
        .iter()
        .map(canonical_from_legacy)
        .collect::<Vec<_>>();
    Ok(Some(ProfileStore {
        profiles,
        active_machine_id: legacy.selected_machine_id.clone(),
    }))
}

/// Map a single legacy profile into the canonical schema.
pub fn canonical_from_legacy(legacy: &config::LinuxMachineProfile) -> MachineProfile {
    let machine_type = match legacy.machine_type {
        LinuxMachineType::Native => MachineType::Native,
        LinuxMachineType::SshWaypipe => MachineType::SshWaypipe,
        LinuxMachineType::SshTerminal => MachineType::SshTerminal,
    };

    // For native machines the legacy `selected_launcher` is the client to run;
    // canonical native machines carry that in `remote_command`.
    let remote_command = if machine_type == MachineType::Native {
        let cmd = legacy.remote_command.trim();
        if !cmd.is_empty() {
            cmd.to_string()
        } else if !legacy.selected_launcher.trim().is_empty() {
            legacy.selected_launcher.clone()
        } else {
            "weston-terminal".to_string()
        }
    } else {
        legacy.remote_command.clone()
    };

    MachineProfile {
        id: legacy.id.clone(),
        name: legacy.name.clone(),
        machine_type,
        ssh_host: legacy.ssh_host.clone(),
        ssh_user: legacy.ssh_user.clone(),
        ssh_port: legacy.ssh_port as i32,
        ssh_password: legacy.ssh_password.clone(),
        remote_command,
        launchers: Vec::new(),
        favorite: false,
        runtime_overrides: Default::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::linux::config::{LinuxMachineProfile, LinuxMachineType};

    #[test]
    fn migrates_native_launcher_into_remote_command() {
        let mut legacy = LinuxMachineProfile::new("Local");
        legacy.machine_type = LinuxMachineType::Native;
        legacy.selected_launcher = "foot".to_string();
        legacy.remote_command.clear();

        let canonical = canonical_from_legacy(&legacy);
        assert_eq!(canonical.machine_type, MachineType::Native);
        assert_eq!(canonical.remote_command, "foot");
        assert!(canonical.launchers.is_empty());
        assert!(!canonical.favorite);
    }

    #[test]
    fn migrates_ssh_fields() {
        let mut legacy = LinuxMachineProfile::new("Remote");
        legacy.machine_type = LinuxMachineType::SshWaypipe;
        legacy.ssh_host = "example.com".to_string();
        legacy.ssh_user = "ada".to_string();
        legacy.ssh_port = 2222;
        legacy.remote_command = "weston-terminal".to_string();

        let canonical = canonical_from_legacy(&legacy);
        assert_eq!(canonical.machine_type, MachineType::SshWaypipe);
        assert_eq!(canonical.ssh_host, "example.com");
        assert_eq!(canonical.ssh_user, "ada");
        assert_eq!(canonical.ssh_port, 2222);
        assert_eq!(canonical.remote_command, "weston-terminal");
    }

    #[test]
    fn migrated_profiles_round_trip_through_canonical_json() {
        let mut legacy = LinuxMachineProfile::new("Local");
        legacy.selected_launcher = "weston-flower".to_string();
        legacy.remote_command.clear();

        let canonical = canonical_from_legacy(&legacy);
        let json = serde_json::to_string(&canonical).unwrap();
        let decoded: MachineProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded, canonical);
    }
}
