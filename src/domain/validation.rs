//! Editor and store validation. One implementation for every target.
//!
//! Mirrors `MachineEditorValidation` in `Sources/WawonaUIContracts` (frozen
//! Swift fallback for SPM tests). Do not add rules only in Swift or Kotlin.

use super::machine_profile::{MachineProfile, MachineType};
pub use super::sanitize_ssh_host::{normalize_ssh_port, sanitize_ssh_host};

/// UserDefaults / SharedPreferences key. Byte-identical across Apple, Android, Linux.
pub const PROFILES_KEY: &str = "wawona.machineProfiles.v1";
/// Active machine id key. Byte-identical across hosts.
pub const ACTIVE_MACHINE_ID_KEY: &str = "wawona.activeMachineId.v1";

const IGETTY_IDS: &[&str] = &[
    "modeb-tty",
    "modeb-ttyd",
    "igetty",
    "igettyd",
    "modeb-getty",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EditorIssue {
    MissingName,
    MissingSshHost,
    MissingSshUser,
    InvalidSshPort,
}

impl EditorIssue {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::MissingName => "missingName",
            Self::MissingSshHost => "missingSSHHost",
            Self::MissingSshUser => "missingSSHUser",
            Self::InvalidSshPort => "invalidSSHPort",
        }
    }
}

pub struct EditorStateView<'a> {
    pub name: &'a str,
    pub type_raw: &'a str,
    pub ssh_host: &'a str,
    pub ssh_user: &'a str,
    pub ssh_port_text: &'a str,
}

pub fn validate_editor(state: EditorStateView<'_>) -> Vec<EditorIssue> {
    let mut issues = Vec::new();
    if state.name.trim().is_empty() {
        issues.push(EditorIssue::MissingName);
    }
    // Legacy storage kinds, or Native Shell session mapped by Apple
    // `callEditorValidate` to ssh_terminal / ssh_waypipe when Use SSH is on.
    let is_ssh = state.type_raw == "ssh_waypipe" || state.type_raw == "ssh_terminal";
    if is_ssh {
        if sanitize_ssh_host(state.ssh_host).is_empty() {
            issues.push(EditorIssue::MissingSshHost);
        }
        if state.ssh_user.trim().is_empty() {
            issues.push(EditorIssue::MissingSshUser);
        }
        let port = normalize_ssh_port(state.ssh_port_text, -1);
        if !(1..=65535).contains(&port) {
            issues.push(EditorIssue::InvalidSshPort);
        }
    }
    issues
}

/// Client / bundled id that must never appear as a Machines profile.
pub fn is_forbidden_machines_client_id(id: &str) -> bool {
    IGETTY_IDS.contains(&id.trim().to_ascii_lowercase().as_str())
}

/// wwn-igetty / Mode B TTY / Doorman PAM console. Not a Machines row.
pub fn is_igetty_console_not_a_machine(profile: &MachineProfile) -> bool {
    if profile.name.trim().eq_ignore_ascii_case("Mode B TTY") {
        return true;
    }
    let client = profile.resolved_native_client_id();
    if IGETTY_IDS.contains(&client.as_str()) {
        return true;
    }
    let bundled = profile
        .runtime_overrides
        .bundled_app_id
        .as_deref()
        .map(str::trim)
        .unwrap_or("")
        .to_ascii_lowercase();
    IGETTY_IDS.contains(&bundled.as_str())
}

/// Store put / decode filter. Editor validation plus igetty refuse.
pub fn validate_profile(profile: &MachineProfile) -> Result<(), String> {
    if is_igetty_console_not_a_machine(profile) {
        return Err("wwn-igetty / Mode B TTY is the console, not a machine".into());
    }
    if profile.name.trim().is_empty() {
        return Err("missingName".into());
    }
    if matches!(
        profile.machine_type,
        MachineType::SshWaypipe | MachineType::SshTerminal
    ) {
        if sanitize_ssh_host(&profile.ssh_host).is_empty() {
            return Err("missingSSHHost".into());
        }
        if profile.ssh_user.trim().is_empty() {
            return Err("missingSSHUser".into());
        }
        if !(1..=65535).contains(&profile.ssh_port) {
            return Err("invalidSSHPort".into());
        }
    }
    Ok(())
}

/// Validate profile overrides for a specific host platform.
/// Ensures platform-specific driver rules are respected (e.g. no KosmicKrisp on Linux or Android).
pub fn validate_profile_for_host(
    host: super::settings_catalog::SettingsHost,
    profile: &MachineProfile,
) -> Result<(), String> {
    validate_profile(profile)?;

    if let Some(ref vk) = profile.runtime_overrides.vulkan_driver {
        let trimmed = vk.trim();
        if !trimmed.is_empty()
            && trimmed != "auto"
            && !super::settings_catalog::is_valid_vulkan_driver(host, trimmed)
        {
            return Err(format!(
                "Vulkan driver '{trimmed}' is not supported on {host:?}. Allowed options: {:?}",
                super::settings_catalog::allowed_vulkan_drivers(host)
            ));
        }
    }

    if let Some(ref gl) = profile.runtime_overrides.open_gl_driver {
        let trimmed = gl.trim();
        if !trimmed.is_empty()
            && trimmed != "auto"
            && !super::settings_catalog::is_valid_opengl_driver(host, trimmed)
        {
            return Err(format!(
                "OpenGL driver '{trimmed}' is not supported on {host:?}. Allowed options: {:?}",
                super::settings_catalog::allowed_opengl_drivers(host)
            ));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn igetty_ids_are_forbidden_machines_clients() {
        assert!(is_forbidden_machines_client_id("igettyd"));
        assert!(is_forbidden_machines_client_id(" ModeB-TTY "));
        assert!(!is_forbidden_machines_client_id("weston-terminal"));
    }

    #[test]
    fn validate_profile_for_host_rejects_invalid_drivers() {
        use super::super::settings_catalog::SettingsHost;

        let mut profile = MachineProfile::default();
        profile.name = "Test".into();
        profile.runtime_overrides.vulkan_driver = Some("kosmickrisp".into());

        // KosmicKrisp is forbidden on Linux and Android
        assert!(validate_profile_for_host(SettingsHost::Linux, &profile).is_err());
        assert!(validate_profile_for_host(SettingsHost::Android, &profile).is_err());

        // KosmicKrisp is allowed on macOS
        assert!(validate_profile_for_host(SettingsHost::MacOs, &profile).is_ok());

        // System driver is allowed on Linux and Android
        profile.runtime_overrides.vulkan_driver = Some("system".into());
        assert!(validate_profile_for_host(SettingsHost::Linux, &profile).is_ok());
        assert!(validate_profile_for_host(SettingsHost::Android, &profile).is_ok());
    }
}
