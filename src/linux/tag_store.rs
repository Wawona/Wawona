//! Linux file persistence for machine tags and per-machine tag assignments.
//!
//! Mirrors `WWNMachineTag` and `WWNMachineTagStore` on Apple and Kotlin on Android.
//! File format stores `wawona.machines.tags` and `wawona.machines.tagAssignments`.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// 12-color Finder-style palette matching Apple and Android.
pub const PALETTE_HEX: &[&str] = &[
    "FF3B30", "FF9500", "FFCC00", "34C759", "00C7A6", "30B0C7",
    "007AFF", "5957D6", "AF52DE", "FF2D55", "A3855E", "8E8E93",
];

/// A colored tag applicable to one or more machines.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MachineTag {
    pub id: String,
    pub name: String,
    pub color_hex: String,
}

impl MachineTag {
    pub fn new(name: impl Into<String>, color_hex: impl Into<String>) -> Self {
        Self {
            id: crate::domain::machine_profile::new_uuid(),
            name: name.into(),
            color_hex: color_hex.into(),
        }
    }
}

fn base_dir() -> Result<PathBuf> {
    let base = if let Ok(custom) = std::env::var("XDG_CONFIG_HOME") {
        PathBuf::from(custom)
    } else {
        let home = std::env::var("HOME").context("HOME is not set")?;
        Path::new(&home).join(".config")
    };
    Ok(base.join("wawona"))
}

pub fn tags_path() -> Result<PathBuf> {
    Ok(base_dir()?.join("machine-tags-v1.json"))
}

pub fn assignments_path() -> Result<PathBuf> {
    Ok(base_dir()?.join("machine-tag-assignments-v1.json"))
}

#[derive(Debug, Clone)]
pub struct TagStore {
    pub tags: Vec<MachineTag>,
    /// machine_id -> list of tag_ids
    pub tag_ids_by_machine: HashMap<String, Vec<String>>,
}

impl Default for TagStore {
    fn default() -> Self {
        Self {
            tags: default_tags(),
            tag_ids_by_machine: HashMap::new(),
        }
    }
}

fn default_tags() -> Vec<MachineTag> {
    vec![
        MachineTag {
            id: "tag-work".to_string(),
            name: "Work".to_string(),
            color_hex: "007AFF".to_string(),
        },
        MachineTag {
            id: "tag-personal".to_string(),
            name: "Personal".to_string(),
            color_hex: "34C759".to_string(),
        },
        MachineTag {
            id: "tag-production".to_string(),
            name: "Production".to_string(),
            color_hex: "FF3B30".to_string(),
        },
        MachineTag {
            id: "tag-testing".to_string(),
            name: "Testing".to_string(),
            color_hex: "FF9500".to_string(),
        },
        MachineTag {
            id: "tag-lab".to_string(),
            name: "Lab".to_string(),
            color_hex: "AF52DE".to_string(),
        },
    ]
}

impl TagStore {
    pub fn load() -> Self {
        let mut store = Self::default();

        if let Ok(path) = tags_path() {
            if path.exists() {
                if let Ok(text) = fs::read_to_string(&path) {
                    if let Ok(loaded_tags) = serde_json::from_str::<Vec<MachineTag>>(&text) {
                        if !loaded_tags.is_empty() {
                            store.tags = loaded_tags;
                        }
                    }
                }
            }
        }

        if let Ok(path) = assignments_path() {
            if path.exists() {
                if let Ok(text) = fs::read_to_string(&path) {
                    if let Ok(loaded_map) = serde_json::from_str::<HashMap<String, Vec<String>>>(&text) {
                        store.tag_ids_by_machine = loaded_map;
                    }
                }
            }
        }

        store
    }

    pub fn save(&self) -> Result<()> {
        let dir = base_dir()?;
        fs::create_dir_all(&dir)
            .with_context(|| format!("failed to create config dir {}", dir.display()))?;

        let tags_file = tags_path()?;
        let tags_json = serde_json::to_string_pretty(&self.tags)
            .context("failed to serialize machine tags")?;
        fs::write(&tags_file, tags_json)
            .with_context(|| format!("failed to write {}", tags_file.display()))?;

        let assign_file = assignments_path()?;
        let assign_json = serde_json::to_string_pretty(&self.tag_ids_by_machine)
            .context("failed to serialize tag assignments")?;
        fs::write(&assign_file, assign_json)
            .with_context(|| format!("failed to write {}", assign_file.display()))?;

        Ok(())
    }

    pub fn tags_for_machine(&self, machine_id: &str) -> Vec<MachineTag> {
        let Some(ids) = self.tag_ids_by_machine.get(machine_id) else {
            return Vec::new();
        };
        self.tags
            .iter()
            .filter(|t| ids.contains(&t.id))
            .cloned()
            .collect()
    }

    pub fn is_assigned(&self, tag_id: &str, machine_id: &str) -> bool {
        self.tag_ids_by_machine
            .get(machine_id)
            .map(|ids| ids.iter().any(|id| id == tag_id))
            .unwrap_or(false)
    }

    pub fn set_assigned(&mut self, assigned: bool, tag_id: &str, machine_id: &str) {
        let ids = self.tag_ids_by_machine.entry(machine_id.to_string()).or_default();
        if assigned {
            if !ids.iter().any(|id| id == tag_id) {
                ids.push(tag_id.to_string());
            }
        } else {
            ids.retain(|id| id != tag_id);
        }
        if ids.is_empty() {
            self.tag_ids_by_machine.remove(machine_id);
        }
    }

    pub fn toggle_assignment(&mut self, tag_id: &str, machine_id: &str) -> bool {
        let assigned = self.is_assigned(tag_id, machine_id);
        let new_state = !assigned;
        self.set_assigned(new_state, tag_id, machine_id);
        new_state
    }

    pub fn create_tag(&mut self, name: &str, color_hex: &str) -> MachineTag {
        let trimmed = name.trim();
        let tag = MachineTag::new(trimmed, color_hex);
        if !trimmed.is_empty() {
            self.tags.push(tag.clone());
        }
        tag
    }

    pub fn delete_tag(&mut self, tag_id: &str) {
        self.tags.retain(|t| t.id != tag_id);
        for ids in self.tag_ids_by_machine.values_mut() {
            ids.retain(|id| id != tag_id);
        }
    }

    pub fn prune_assignments(&mut self, keeping_machine_ids: &[String]) {
        self.tag_ids_by_machine
            .retain(|mid, _| keeping_machine_ids.contains(mid));
    }
}
