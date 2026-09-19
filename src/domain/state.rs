use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use super::{
    new_uuid, MachineProfile, MachineStatus, PlatformCapabilities, Preferences,
    ResolvedMachineSettings, SettingsDiagnosticCategory, SettingsDiagnosticEntry,
    SettingsDiagnosticMode,
};

pub const DOMAIN_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DurableState {
    pub schema_version: u32,
    pub profiles: Vec<MachineProfile>,
    pub active_machine_id: Option<String>,
    pub preferences: Preferences,
}

impl Default for DurableState {
    fn default() -> Self {
        Self {
            schema_version: DOMAIN_SCHEMA_VERSION,
            profiles: Vec::new(),
            active_machine_id: None,
            preferences: Preferences::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MachineSession {
    pub id: String,
    pub machine_id: String,
    pub status: MachineStatus,
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub failure_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSnapshot {
    pub schema_version: u32,
    pub revision: u64,
    pub profiles: Vec<MachineProfile>,
    pub active_machine_id: Option<String>,
    pub preferences: Preferences,
    pub sessions: Vec<MachineSession>,
    pub active_session_id: Option<String>,
    pub frame_presented_count: u64,
    pub connected_client_count: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AppState {
    durable: DurableState,
    capabilities: PlatformCapabilities,
    sessions: Vec<MachineSession>,
    active_session_id: Option<String>,
    frame_presented_count: u64,
    connected_client_count: u64,
    revision: u64,
}

impl Default for AppState {
    fn default() -> Self {
        let capabilities = PlatformCapabilities::default();
        let mut durable = DurableState::default();
        durable.preferences.normalize(&capabilities);
        Self {
            durable,
            capabilities,
            sessions: Vec::new(),
            active_session_id: None,
            frame_presented_count: 0,
            connected_client_count: 0,
            revision: 1,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AppIntent {
    ImportDurableState { state: DurableState },
    SetCapabilities { capabilities: PlatformCapabilities },
    ImportLegacyPreferences {
        values: HashMap<String, serde_json::Value>,
    },
    UpsertProfile { profile: MachineProfile },
    DeleteProfile { id: String },
    SetActiveMachine { id: Option<String> },
    UpdatePreferences { preferences: Preferences },
    RecordDiagnostic {
        category: SettingsDiagnosticCategory,
        mode: SettingsDiagnosticMode,
        target: String,
        success: bool,
        message: String,
        details: HashMap<String, String>,
    },
    RunSshDiagnostic {
        host: String,
        user: String,
        port: i32,
        password_provided: bool,
        runtime_probe: bool,
        runtime_available: bool,
    },
    RunWaypipeDiagnostic {
        command: String,
        runtime_probe: bool,
        binary_available: bool,
    },
    RunDependencyDiagnostic {
        runtime_probe: bool,
        availability: HashMap<String, bool>,
    },
    Connect { machine_id: String },
    ConnectionFailed { machine_id: String, reason: String },
    SetSessionStatus {
        session_id: String,
        status: MachineStatus,
        reason: Option<String>,
    },
    Disconnect { session_id: String },
    FramePresented { session_id: Option<String> },
    ClientConnected { session_id: Option<String> },
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DomainError {
    #[error("machine profile {0} does not exist")]
    UnknownMachine(String),
    #[error("session {0} does not exist")]
    UnknownSession(String),
    #[error("active machine must reference an existing profile")]
    InvalidActiveMachine,
    #[error("profile id and name are required")]
    InvalidProfile,
    #[error("unsupported durable state schema {0}")]
    UnsupportedSchema(u32),
    #[error("invalid JSON: {0}")]
    InvalidJson(String),
}

impl AppState {
    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn snapshot(&self) -> AppSnapshot {
        AppSnapshot {
            schema_version: DOMAIN_SCHEMA_VERSION,
            revision: self.revision,
            profiles: self.durable.profiles.clone(),
            active_machine_id: self.durable.active_machine_id.clone(),
            preferences: self.durable.preferences.clone(),
            sessions: self.sessions.clone(),
            active_session_id: self.active_session_id.clone(),
            frame_presented_count: self.frame_presented_count,
            connected_client_count: self.connected_client_count,
        }
    }

    pub fn snapshot_json(&self) -> Result<String, DomainError> {
        serde_json::to_string(&self.snapshot()).map_err(json_error)
    }

    pub fn durable_json(&self) -> Result<String, DomainError> {
        serde_json::to_string(&self.durable).map_err(json_error)
    }

    pub fn apply_json(&mut self, json: &str) -> Result<(), DomainError> {
        let intent: AppIntent = serde_json::from_str(json).map_err(json_error)?;
        self.apply(intent)
    }

    pub fn resolved_settings(
        &self,
        machine_id: &str,
    ) -> Result<ResolvedMachineSettings, DomainError> {
        let profile = self
            .durable
            .profiles
            .iter()
            .find(|profile| profile.id == machine_id)
            .ok_or_else(|| DomainError::UnknownMachine(machine_id.into()))?;
        Ok(self
            .durable
            .preferences
            .resolve(profile, &self.capabilities))
    }

    pub fn resolved_settings_json(&self, machine_id: &str) -> Result<String, DomainError> {
        serde_json::to_string(&self.resolved_settings(machine_id)?).map_err(json_error)
    }

    pub fn resolve_profile_json(&self, profile_json: &str) -> Result<String, DomainError> {
        let mut profile: MachineProfile =
            serde_json::from_str(profile_json).map_err(json_error)?;
        normalize_profile(&mut profile)?;
        serde_json::to_string(
            &self
                .durable
                .preferences
                .resolve(&profile, &self.capabilities),
        )
        .map_err(json_error)
    }

    pub fn apply(&mut self, intent: AppIntent) -> Result<(), DomainError> {
        match intent {
            AppIntent::ImportDurableState { mut state } => {
                if state.schema_version > DOMAIN_SCHEMA_VERSION {
                    return Err(DomainError::UnsupportedSchema(state.schema_version));
                }
                validate_profiles(&state.profiles)?;
                if state.active_machine_id.as_ref().is_some_and(|id| {
                    !state.profiles.iter().any(|profile| &profile.id == id)
                }) {
                    state.active_machine_id = None;
                }
                state.schema_version = DOMAIN_SCHEMA_VERSION;
                state.preferences.normalize(&self.capabilities);
                self.durable = state;
            }
            AppIntent::SetCapabilities { capabilities } => {
                self.capabilities = capabilities;
                self.durable.preferences.normalize(&self.capabilities);
            }
            AppIntent::ImportLegacyPreferences { values } => {
                self.durable
                    .preferences
                    .import_legacy_values(&values, &self.capabilities);
            }
            AppIntent::UpsertProfile { mut profile } => {
                normalize_profile(&mut profile)?;
                if let Some(existing) = self
                    .durable
                    .profiles
                    .iter_mut()
                    .find(|existing| existing.id == profile.id)
                {
                    *existing = profile;
                } else {
                    self.durable.profiles.push(profile);
                }
            }
            AppIntent::DeleteProfile { id } => {
                self.durable.profiles.retain(|profile| profile.id != id);
                if self.durable.active_machine_id.as_deref() == Some(&id) {
                    self.durable.active_machine_id = None;
                }
                self.sessions.retain(|session| session.machine_id != id);
                if self.active_session_id.as_ref().is_some_and(|active| {
                    !self.sessions.iter().any(|session| &session.id == active)
                }) {
                    self.active_session_id = None;
                }
            }
            AppIntent::SetActiveMachine { id } => {
                if id
                    .as_ref()
                    .is_some_and(|id| !self.durable.profiles.iter().any(|p| &p.id == id))
                {
                    return Err(DomainError::InvalidActiveMachine);
                }
                self.durable.active_machine_id = id;
            }
            AppIntent::UpdatePreferences { mut preferences } => {
                preferences.normalize(&self.capabilities);
                self.durable.preferences = preferences;
            }
            AppIntent::RecordDiagnostic {
                category,
                mode,
                target,
                success,
                message,
                details,
            } => {
                self.record_diagnostic(
                    category, mode, target, success, message, details,
                );
            }
            AppIntent::RunSshDiagnostic {
                host,
                user,
                port,
                password_provided,
                runtime_probe,
                runtime_available,
            } => {
                let host = host.trim().to_owned();
                let user = user.trim().to_owned();
                let valid = !host.is_empty()
                    && !user.is_empty()
                    && (1..=65535).contains(&port);
                let success = valid && (!runtime_probe || runtime_available);
                let message = if runtime_probe {
                    if success {
                        "Runtime transport is available and SSH settings are valid."
                    } else {
                        "Runtime probe failed: transport is unavailable or host/user/port are invalid."
                    }
                } else if success {
                    "SSH settings are valid for connection attempt."
                } else {
                    "SSH settings require a host, user, and port from 1 through 65535."
                };
                self.record_diagnostic(
                    SettingsDiagnosticCategory::Ssh,
                    if runtime_probe {
                        SettingsDiagnosticMode::RuntimeProbe
                    } else {
                        SettingsDiagnosticMode::ConfigLint
                    },
                    format!("{user}@{host}:{port}"),
                    success,
                    message.into(),
                    HashMap::from([
                        ("runtimeProbe".into(), runtime_probe.to_string()),
                        ("host".into(), host),
                        ("user".into(), user),
                        ("port".into(), port.to_string()),
                        ("passwordProvided".into(), password_provided.to_string()),
                    ]),
                );
            }
            AppIntent::RunWaypipeDiagnostic {
                command,
                runtime_probe,
                binary_available,
            } => {
                let command = command.trim().to_owned();
                let binary = command.split_whitespace().next().unwrap_or("").to_owned();
                let configured = !binary.is_empty();
                let success = configured && (!runtime_probe || binary_available);
                let message = if runtime_probe {
                    if success {
                        "Runtime probe: command binary is available."
                    } else {
                        "Runtime probe failed: command is empty or binary was not found."
                    }
                } else if success {
                    "Waypipe command is configured."
                } else {
                    "Waypipe command is empty."
                };
                self.record_diagnostic(
                    SettingsDiagnosticCategory::Waypipe,
                    if runtime_probe {
                        SettingsDiagnosticMode::RuntimeProbe
                    } else {
                        SettingsDiagnosticMode::ConfigLint
                    },
                    if command.is_empty() {
                        "waypipe".into()
                    } else {
                        command
                    },
                    success,
                    message.into(),
                    HashMap::from([
                        ("runtimeProbe".into(), runtime_probe.to_string()),
                        ("binary".into(), binary),
                    ]),
                );
            }
            AppIntent::RunDependencyDiagnostic {
                runtime_probe,
                availability,
            } => {
                let mut names = availability.keys().cloned().collect::<Vec<_>>();
                names.sort();
                let success = !runtime_probe || availability.values().all(|available| *available);
                let details = availability
                    .into_iter()
                    .map(|(name, available)| {
                        (name, if available { "present" } else { "missing" }.into())
                    })
                    .collect();
                let message = if runtime_probe {
                    format!("Runtime dependency probe completed for: {}", names.join(", "))
                } else {
                    format!("Configured dependencies: {}", names.join(", "))
                };
                self.record_diagnostic(
                    SettingsDiagnosticCategory::Dependency,
                    if runtime_probe {
                        SettingsDiagnosticMode::RuntimeProbe
                    } else {
                        SettingsDiagnosticMode::ConfigLint
                    },
                    "global-dependencies".into(),
                    success,
                    message,
                    details,
                );
            }
            AppIntent::Connect { machine_id } => {
                if !self
                    .durable
                    .profiles
                    .iter()
                    .any(|profile| profile.id == machine_id)
                {
                    return Err(DomainError::UnknownMachine(machine_id));
                }
                let id = new_uuid();
                self.sessions.push(MachineSession {
                    id: id.clone(),
                    machine_id: machine_id.clone(),
                    status: MachineStatus::Connected,
                    bytes_sent: 0,
                    bytes_received: 0,
                    failure_reason: None,
                });
                self.active_session_id = Some(id);
                self.durable.active_machine_id = Some(machine_id);
            }
            AppIntent::ConnectionFailed { machine_id, reason } => {
                if !self
                    .durable
                    .profiles
                    .iter()
                    .any(|profile| profile.id == machine_id)
                {
                    return Err(DomainError::UnknownMachine(machine_id));
                }
                self.sessions.push(MachineSession {
                    id: new_uuid(),
                    machine_id,
                    status: MachineStatus::Error,
                    bytes_sent: 0,
                    bytes_received: 0,
                    failure_reason: Some(reason),
                });
            }
            AppIntent::SetSessionStatus {
                session_id,
                status,
                reason,
            } => {
                let session = self
                    .sessions
                    .iter_mut()
                    .find(|session| session.id == session_id)
                    .ok_or_else(|| DomainError::UnknownSession(session_id.clone()))?;
                session.status = status;
                session.failure_reason = reason;
                if status == MachineStatus::Connected {
                    self.active_session_id = Some(session_id);
                }
            }
            AppIntent::Disconnect { session_id } => {
                let session = self
                    .sessions
                    .iter_mut()
                    .find(|session| session.id == session_id)
                    .ok_or_else(|| DomainError::UnknownSession(session_id.clone()))?;
                session.status = MachineStatus::Disconnected;
                if self.active_session_id.as_deref() == Some(&session_id) {
                    self.active_session_id = self
                        .sessions
                        .iter()
                        .find(|candidate| candidate.status == MachineStatus::Connected)
                        .map(|candidate| candidate.id.clone());
                }
            }
            AppIntent::FramePresented { session_id } => {
                if let Some(id) = session_id {
                    ensure_session(&self.sessions, &id)?;
                }
                self.frame_presented_count = self.frame_presented_count.saturating_add(1);
            }
            AppIntent::ClientConnected { session_id } => {
                if let Some(id) = session_id {
                    ensure_session(&self.sessions, &id)?;
                }
                self.connected_client_count = self.connected_client_count.saturating_add(1);
            }
        }
        self.revision = self.revision.wrapping_add(1).max(1);
        Ok(())
    }

    fn record_diagnostic(
        &mut self,
        category: SettingsDiagnosticCategory,
        mode: SettingsDiagnosticMode,
        target: String,
        success: bool,
        message: String,
        details: HashMap<String, String>,
    ) {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_secs_f64() - 978_307_200.0)
            .unwrap_or(0.0);
        self.durable.preferences.diagnostics.insert(
            0,
            SettingsDiagnosticEntry {
                id: new_uuid(),
                timestamp,
                category,
                mode,
                target,
                success,
                message,
                details,
            },
        );
        self.durable.preferences.diagnostics.truncate(100);
    }
}

fn normalize_profile(profile: &mut MachineProfile) -> Result<(), DomainError> {
    profile.id = profile.id.trim().to_owned();
    profile.name = profile.name.trim().to_owned();
    if profile.id.is_empty() || profile.name.is_empty() {
        return Err(DomainError::InvalidProfile);
    }
    profile.ssh_host = profile.ssh_host.trim().to_owned();
    profile.ssh_user = profile.ssh_user.trim().to_owned();
    profile.ssh_port = if (1..=65535).contains(&profile.ssh_port) {
        profile.ssh_port
    } else {
        22
    };
    profile.remote_command = if profile.remote_command.trim().is_empty() {
        "weston-simple-shm".into()
    } else {
        profile.remote_command.trim().into()
    };
    Ok(())
}

fn validate_profiles(profiles: &[MachineProfile]) -> Result<(), DomainError> {
    let mut ids = std::collections::HashSet::new();
    for profile in profiles {
        if profile.id.trim().is_empty()
            || profile.name.trim().is_empty()
            || !ids.insert(profile.id.as_str())
        {
            return Err(DomainError::InvalidProfile);
        }
    }
    Ok(())
}

fn ensure_session(sessions: &[MachineSession], id: &str) -> Result<(), DomainError> {
    sessions
        .iter()
        .any(|session| session.id == id)
        .then_some(())
        .ok_or_else(|| DomainError::UnknownSession(id.into()))
}

fn json_error(error: serde_json::Error) -> DomainError {
    DomainError::InvalidJson(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intents_own_profile_and_session_lifecycle() {
        let mut state = AppState::default();
        let profile = MachineProfile::new("Local");
        let id = profile.id.clone();
        state.apply(AppIntent::UpsertProfile { profile }).unwrap();
        state
            .apply(AppIntent::SetActiveMachine {
                id: Some(id.clone()),
            })
            .unwrap();
        state
            .apply(AppIntent::Connect {
                machine_id: id.clone(),
            })
            .unwrap();
        let snapshot = state.snapshot();
        assert_eq!(snapshot.active_machine_id.as_deref(), Some(id.as_str()));
        assert_eq!(snapshot.sessions.len(), 1);
        assert_eq!(snapshot.sessions[0].status, MachineStatus::Connected);
        assert!(snapshot.revision > 1);
    }

    #[test]
    fn import_rejects_future_schema() {
        let mut state = AppState::default();
        let error = state
            .apply(AppIntent::ImportDurableState {
                state: DurableState {
                    schema_version: DOMAIN_SCHEMA_VERSION + 1,
                    ..Default::default()
                },
            })
            .unwrap_err();
        assert!(matches!(error, DomainError::UnsupportedSchema(_)));
    }

    #[test]
    fn json_intent_and_snapshot_are_stable() {
        let mut state = AppState::default();
        let profile = MachineProfile::new("Desk");
        let json = serde_json::json!({
            "type": "upsert_profile",
            "profile": profile,
        })
        .to_string();
        state.apply_json(&json).unwrap();
        let snapshot: AppSnapshot = serde_json::from_str(&state.snapshot_json().unwrap()).unwrap();
        assert_eq!(snapshot.profiles[0].name, "Desk");
    }
}
