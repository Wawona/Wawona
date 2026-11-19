//! UniFFI product-domain API. Not the compositor `WWNCore*` poll bridge.

use std::sync::{Arc, Mutex};

use super::error::DomainError;
use super::machine_profile::MachineProfile;
use super::profile_store::ProfileDocument;
use super::validation::{
    normalize_ssh_port, sanitize_ssh_host, split_ssh_host_and_port, validate_editor,
    validate_profile, EditorStateView, SshHostPort,
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
        self.inner.lock().expect("profile store lock").put(profile)
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
pub fn machine_profiles_encode_v1(profiles: Vec<MachineProfile>) -> Result<String, DomainError> {
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

#[derive(uniffi::Record)]
pub struct SshHostPortView {
    pub host: String,
    pub port: i32,
}

impl From<SshHostPort> for SshHostPortView {
    fn from(value: SshHostPort) -> Self {
        Self {
            host: value.host,
            port: value.port,
        }
    }
}

#[uniffi::export]
pub fn split_ssh_host_and_port_uniffi(
    raw_host: String,
    raw_port: Option<String>,
    fallback: i32,
) -> SshHostPortView {
    split_ssh_host_and_port(&raw_host, raw_port.as_deref(), fallback).into()
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
pub fn settings_allowed_vulkan_drivers(host: super::settings_catalog::SettingsHost) -> Vec<String> {
    super::settings_catalog::allowed_vulkan_drivers(host)
        .iter()
        .map(|&s| s.to_string())
        .collect()
}

#[uniffi::export]
pub fn settings_allowed_opengl_drivers(host: super::settings_catalog::SettingsHost) -> Vec<String> {
    super::settings_catalog::allowed_opengl_drivers(host)
        .iter()
        .map(|&s| s.to_string())
        .collect()
}

#[uniffi::export]
pub fn settings_default_vulkan_driver(host: super::settings_catalog::SettingsHost) -> String {
    super::settings_catalog::default_vulkan_driver(host).to_string()
}

#[uniffi::export]
pub fn settings_default_opengl_driver(host: super::settings_catalog::SettingsHost) -> String {
    super::settings_catalog::default_opengl_driver(host).to_string()
}

#[uniffi::export]
pub fn settings_is_field_allowed(
    field: super::settings_catalog::SettingsFieldId,
    host: super::settings_catalog::SettingsHost,
) -> bool {
    super::settings_catalog::is_field_allowed(field, host)
}

#[uniffi::export]
pub fn capability_gate(platform: String, feature: String) -> String {
    super::capabilities::gate(&platform, &feature).to_string()
}

#[uniffi::export]
pub fn session_is_forbidden_client_id(id: String) -> bool {
    super::validation::is_forbidden_machines_client_id(&id)
}

#[uniffi::export]
pub fn darwin_cli_parse_json(args: Vec<String>) -> String {
    super::darwin_cli::parse_to_json(&args)
}

#[uniffi::export]
pub fn darwin_cli_help_text() -> String {
    super::darwin_cli::help_text().to_string()
}

#[uniffi::export]
pub fn client_catalog_json() -> String {
    super::client_catalog::catalog_json()
}

#[uniffi::export]
pub fn prefs_defaults_json() -> String {
    super::prefs_keys::defaults_json()
}

#[uniffi::export]
pub fn prefs_keys_csv() -> String {
    super::prefs_keys::all_keys_csv()
}

#[uniffi::export]
pub fn launch_resolve_backend_json(
    pref: String,
    classic_own_display: bool,
    cli_override: Option<String>,
) -> String {
    super::launch_resolve::resolve_backend_json(&pref, classic_own_display, cli_override.as_deref())
}

#[uniffi::export]
pub fn launch_nested_cursor_policy_json(
    is_nested_compositor: bool,
    show_virtual_cursor: bool,
) -> String {
    super::launch_resolve::nested_cursor_json(is_nested_compositor, show_virtual_cursor)
}

/// Resolve touch / cursor / grab for Start and Focus.
/// `surface`: `primary` | `limited_touch` | `pointer_remote`.
#[uniffi::export]
pub fn launch_session_input_policy_json(
    is_nested_compositor: bool,
    show_virtual_cursor: bool,
    touch_input_override: Option<String>,
    surface: String,
) -> String {
    use super::launch_resolve::PresentSurfaceClass;
    let surface = match surface.trim().to_ascii_lowercase().as_str() {
        "limited_touch" | "limited" | "carplay" => PresentSurfaceClass::LimitedTouch,
        "pointer_remote" | "airplay" | "remote" => PresentSurfaceClass::PointerRemote,
        _ => PresentSurfaceClass::Primary,
    };
    super::launch_resolve::session_input_json(
        is_nested_compositor,
        show_virtual_cursor,
        touch_input_override.as_deref(),
        surface,
    )
}

/// Add/Edit Kind picker labels (Native Shell / VM / Container only).
#[uniffi::export]
pub fn machine_kind_picker_json() -> String {
    use super::machine_profile::MachineType;
    let rows: Vec<serde_json::Value> = MachineType::selectable_for_ui()
        .iter()
        .map(|t| {
            serde_json::json!({
                "id": serde_json::to_value(t).unwrap_or(serde_json::Value::Null),
                "label": t.user_facing_name(),
            })
        })
        .collect();
    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into())
}

#[uniffi::export]
pub fn welcome_title() -> String {
    super::welcome_copy::TITLE.to_string()
}

#[uniffi::export]
pub fn welcome_message() -> String {
    super::welcome_copy::MESSAGE.to_string()
}

#[uniffi::export]
pub fn welcome_continue_label() -> String {
    super::welcome_copy::CONTINUE.to_string()
}

/// Session phase step. `op` is `start` or `stop`. `phase` is `idle`, `running`, or `stopped`.
#[uniffi::export]
pub fn machine_phase_apply(op: String, phase: String) -> String {
    wawona_laws::apply_phase(&op, &phase).unwrap_or("").to_string()
}

/// Route-root step. Exact's navigator still owns the live stack.
#[uniffi::export]
pub fn nav_place_apply(op: String, place: String) -> String {
    wawona_laws::apply_nav(&op, &place).unwrap_or("").to_string()
}
