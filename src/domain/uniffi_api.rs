//! UniFFI product-domain API. Not the compositor `WWNCore*` poll bridge.

use std::sync::{Arc, Mutex};

use super::error::DomainError;
use super::machine_profile::MachineProfile;
use super::profile_store::ProfileDocument;
use super::validation::{
    sanitize_ssh_host, validate_editor, validate_profile, EditorStateView, normalize_ssh_port,
};

#[derive(uniffi::Object)]
pub struct MachineProfileStoreApi {
    inner: Mutex<ProfileDocument>,
}

#[uniffi::export]
impl MachineProfileStoreApi {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(ProfileDocument::default()),
        })
    }

    pub fn load_json(&self, json: String) -> Result<(), DomainError> {
        let doc = ProfileDocument::from_json(&json)?;
        *self.inner.lock().expect("profile store lock") = doc;
        Ok(())
    }

    pub fn save_json(&self) -> Result<String, DomainError> {
        self.inner.lock().expect("profile store lock").to_json()
    }

    pub fn list_profiles(&self) -> Vec<MachineProfile> {
        self.inner.lock().expect("profile store lock").list()
    }

    pub fn get_profile(&self, id: String) -> Option<MachineProfile> {
        self.inner.lock().expect("profile store lock").get(&id)
    }

    pub fn put_profile(&self, profile: MachineProfile) -> Result<(), DomainError> {
        self.inner
            .lock()
            .expect("profile store lock")
            .put(profile)
    }

    pub fn delete_profile(&self, id: String) {
        self.inner.lock().expect("profile store lock").delete(&id);
    }

    pub fn active_id(&self) -> Option<String> {
        self.inner
            .lock()
            .expect("profile store lock")
            .active_machine_id
            .clone()
    }

    pub fn set_active_id(&self, id: Option<String>) {
        self.inner
            .lock()
            .expect("profile store lock")
            .set_active(id);
    }
}

#[uniffi::export]
pub fn machine_profiles_decode_v1(json: String) -> Result<Vec<MachineProfile>, DomainError> {
    Ok(ProfileDocument::from_json(&json)?.list())
}

#[uniffi::export]
pub fn machine_profiles_encode_v1(
    profiles: Vec<MachineProfile>,
) -> Result<String, DomainError> {
    let doc = ProfileDocument {
        profiles,
        active_machine_id: None,
    };
    doc.to_json()
}

#[uniffi::export]
pub fn validate_machine_profile(profile: MachineProfile) -> Result<(), DomainError> {
    validate_profile(&profile).map_err(DomainError::validation)
}

#[uniffi::export]
pub fn sanitize_ssh_host_uniffi(raw: String) -> String {
    sanitize_ssh_host(&raw)
}

#[uniffi::export]
pub fn normalize_ssh_port_uniffi(raw: String, fallback: i32) -> i32 {
    normalize_ssh_port(&raw, fallback)
}

#[uniffi::export]
pub fn validate_machine_editor(
    name: String,
    type_raw: String,
    ssh_host: String,
    ssh_user: String,
    ssh_port_text: String,
) -> Vec<String> {
    validate_editor(EditorStateView {
        name: &name,
        type_raw: &type_raw,
        ssh_host: &ssh_host,
        ssh_user: &ssh_user,
        ssh_port_text: &ssh_port_text,
    })
    .into_iter()
    .map(|i| i.as_str().to_string())
    .collect()
}

#[uniffi::export]
pub fn settings_visible_sections(host: super::settings_catalog::SettingsHost) -> Vec<String> {
    super::settings_catalog::visible_sections(host)
        .into_iter()
        .map(|s| s.slug().to_string())
        .collect()
}

#[uniffi::export]
pub fn capability_gate(platform: String, feature: String) -> String {
    super::capabilities::gate(&platform, &feature).to_string()
}

#[uniffi::export]
pub fn session_is_forbidden_client_id(id: String) -> bool {
    super::validation::is_forbidden_machines_client_id(&id)
}
