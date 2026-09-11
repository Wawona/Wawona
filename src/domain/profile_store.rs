//! In-memory `wawona.machineProfiles.v1` document.
//!
//! Hosts persist the JSON blob (UserDefaults, SharedPreferences, or
//! `~/.config/wawona/machine-profiles-v1.json`). Mutations and decode live here.

use super::error::DomainError;
use super::machine_profile::MachineProfile;
use super::validation::{is_igetty_console_not_a_machine, validate_profile};

#[derive(Debug, Clone, Default)]
pub struct ProfileDocument {
    pub profiles: Vec<MachineProfile>,
    pub active_machine_id: Option<String>,
}

impl ProfileDocument {
    pub fn from_json(json: &str) -> Result<Self, DomainError> {
        let trimmed = json.trim();
        if trimmed.is_empty() {
            return Ok(Self::default());
        }
        let parsed: Vec<MachineProfile> =
            serde_json::from_str(trimmed).map_err(|e| DomainError::invalid_json(e.to_string()))?;
        Ok(Self {
            profiles: parsed
                .into_iter()
                .filter(|p| !is_igetty_console_not_a_machine(p))
                .collect(),
            active_machine_id: None,
        })
    }

    pub fn to_json(&self) -> Result<String, DomainError> {
        serde_json::to_string(&self.profiles).map_err(|e| DomainError::invalid_json(e.to_string()))
    }

    pub fn list(&self) -> Vec<MachineProfile> {
        self.profiles.clone()
    }

    pub fn get(&self, id: &str) -> Option<MachineProfile> {
        self.profiles.iter().find(|p| p.id == id).cloned()
    }

    pub fn put(&mut self, profile: MachineProfile) -> Result<(), DomainError> {
        if is_igetty_console_not_a_machine(&profile) {
            self.delete(&profile.id);
            return Err(DomainError::refused(
                "wwn-igetty / Mode B TTY is the console, not a machine",
            ));
        }
        validate_profile(&profile).map_err(DomainError::validation)?;
        if let Some(idx) = self.profiles.iter().position(|p| p.id == profile.id) {
            self.profiles[idx] = profile;
        } else {
            self.profiles.push(profile);
        }
        Ok(())
    }

    pub fn delete(&mut self, id: &str) {
        self.profiles.retain(|p| p.id != id);
        if self.active_machine_id.as_deref() == Some(id) {
            self.active_machine_id = None;
        }
    }

    pub fn set_active(&mut self, id: Option<String>) {
        self.active_machine_id = id;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::machine_profile::MachineType;

    #[test]
    fn empty_json_is_empty_store() {
        let doc = ProfileDocument::from_json("").unwrap();
        assert!(doc.list().is_empty());
    }

    #[test]
    fn load_put_delete_round_trip() {
        let json = r#"[{"id":"a","name":"One"}]"#;
        let mut doc = ProfileDocument::from_json(json).unwrap();
        assert_eq!(doc.list().len(), 1);
        assert_eq!(doc.get("a").unwrap().name, "One");

        let mut two = crate::domain::machine_profile::MachineProfile::new("Two");
        two.id = "b".into();
        two.machine_type = MachineType::Native;
        doc.put(two).unwrap();
        assert_eq!(doc.list().len(), 2);

        doc.delete("a");
        assert!(doc.get("a").is_none());
        let out = doc.to_json().unwrap();
        assert!(out.contains("\"id\":\"b\""));
        assert!(!out.contains("\"id\":\"a\""));
    }

    #[test]
    fn purges_igetty_on_load_and_refuses_put() {
        let json = r#"[
          {"id":"ok","name":"Desk"},
          {"id":"bad","name":"Mode B TTY","runtimeOverrides":{"bundledAppID":"igettyd"}}
        ]"#;
        let mut doc = ProfileDocument::from_json(json).unwrap();
        assert_eq!(doc.list().len(), 1);
        assert_eq!(doc.list()[0].id, "ok");

        let mut tty = crate::domain::machine_profile::MachineProfile::new("Mode B TTY");
        tty.id = "tty".into();
        assert!(doc.put(tty).is_err());
        assert!(doc.get("tty").is_none());
    }

    #[test]
    fn old_v1_array_still_decodes() {
        let json = r#"[{"id":"x","name":"Mini","type":"native"}]"#;
        let doc = ProfileDocument::from_json(json).unwrap();
        let p = doc.get("x").unwrap();
        assert_eq!(p.remote_command, "weston-simple-shm");
        assert_eq!(p.ssh_port, 22);
    }
}
