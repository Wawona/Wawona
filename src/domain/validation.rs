//! Editor and store validation. One implementation for every target.
//!
//! Mirrors `MachineEditorValidation` in `Sources/WawonaUIContracts` (frozen
//! Swift fallback for SPM tests). Do not add rules only in Swift or Kotlin.

use super::machine_profile::{MachineProfile, MachineType};

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

/// Drop accidental scheme, path, query, and `host:port` so host and port stay split.
pub fn sanitize_ssh_host(raw: &str) -> String {
    let mut value = raw.trim().to_string();
    if value.is_empty() {
        return String::new();
    }

    if let Some(idx) = value.find("://") {
        value = value[idx + 3..].to_string();
    }
    if let Some(idx) = value.find('/') {
        value.truncate(idx);
    }
    if let Some(idx) = value.find('?') {
        value.truncate(idx);
    }
    if let Some(idx) = value.find('#') {
        value.truncate(idx);
    }

    value = value
        .chars()
        .filter(|c| !c.is_whitespace() && !"\"'`$;&|<>\\".contains(*c))
        .collect();

    if value.starts_with('[') {
        if let Some(closing) = value.find(']') {
            let after = closing + 1;
            if after < value.len() && value.as_bytes()[after] == b':' {
                let suffix = &value[after + 1..];
                if !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()) {
                    value.truncate(closing + 1);
                }
            }
        }
    } else if let Some(colon) = value.rfind(':') {
        let host_part = &value[..colon];
        let port_part = &value[colon + 1..];
        if !host_part.contains(':')
            && !port_part.is_empty()
            && port_part.chars().all(|c| c.is_ascii_digit())
        {
            value.truncate(colon);
        }
    }

    value
}

pub fn normalize_ssh_port(raw: &str, fallback: i32) -> i32 {
    let trimmed = raw.trim();
    match trimmed.parse::<i32>() {
        Ok(parsed) if (1..=65535).contains(&parsed) => parsed,
        _ => fallback,
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_strips_scheme_and_port() {
        assert_eq!(sanitize_ssh_host(" ssh://host.example:2222/path "), "host.example");
        assert_eq!(sanitize_ssh_host("[::1]:22"), "[::1]");
        assert_eq!(sanitize_ssh_host("10.0.0.1"), "10.0.0.1");
    }

    #[test]
    fn normalize_port_bounds() {
        assert_eq!(normalize_ssh_port("22", 1), 22);
        assert_eq!(normalize_ssh_port("0", 22), 22);
        assert_eq!(normalize_ssh_port("65536", 22), 22);
        assert_eq!(normalize_ssh_port("abc", 22), 22);
    }

    #[test]
    fn igetty_ids_are_forbidden_machines_clients() {
        assert!(is_forbidden_machines_client_id("igettyd"));
        assert!(is_forbidden_machines_client_id(" ModeB-TTY "));
        assert!(!is_forbidden_machines_client_id("weston-terminal"));
    }
}
