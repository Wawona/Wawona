//! Canonical cross-platform machine-profile model for Linux.
//!
//! This is the Rust mirror of the shared `wawona.machineProfiles.v1` schema
//! defined in `Sources/WawonaModel/MachineProfile.swift` (Apple) and
//! `android/app/.../MachineProfiles.kt` (Android). The serde field names match
//! the Swift `Codable` JSON keys byte-for-byte (including acronym casing such
//! as `openGLDriver`, `bundledAppID`, `forceSSD`, `renderMacOSPointer`,
//! `waypipeSSHPassword`) so a profile written by any platform decodes on the
//! others. Linux persistence + migration lives in `profile_store.rs`.

use serde::{Deserialize, Serialize};

/// Machine connection type. Serialized as snake_case to match the Swift
/// `MachineType` rawValues (`native`, `ssh_waypipe`, `ssh_terminal`,
/// `virtual_machine`, `container`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MachineType {
    Native,
    SshWaypipe,
    SshTerminal,
    VirtualMachine,
    Container,
}

impl Default for MachineType {
    fn default() -> Self {
        Self::Native
    }
}

impl MachineType {
    /// Human-readable name for pickers/lists (matches the macOS editor wording).
    pub fn user_facing_name(&self) -> &'static str {
        match self {
            Self::Native => "Native",
            Self::SshWaypipe => "SSH + Waypipe",
            Self::SshTerminal => "SSH Terminal",
            Self::VirtualMachine => "Virtual Machine",
            Self::Container => "Container",
        }
    }

    /// Symbolic icon name. Maps the shared SF Symbol concept to a freedesktop
    /// icon name so GTK can render the same intent as iOS/watchOS.
    pub fn icon_name(&self) -> &'static str {
        match self {
            Self::Native => "computer-symbolic",
            Self::SshWaypipe => "network-workgroup-symbolic",
            Self::SshTerminal => "utilities-terminal-symbolic",
            Self::VirtualMachine => "computer-apple-ipad-symbolic",
            Self::Container => "package-x-generic-symbolic",
        }
    }

    /// True for connection types that target a remote host over SSH.
    pub fn is_remote(&self) -> bool {
        matches!(self, Self::SshWaypipe | Self::SshTerminal)
    }

    /// True for on-device machine types (mirrors Android `MachineType.isLocal`).
    pub fn is_local(self) -> bool {
        matches!(self, Self::Native | Self::VirtualMachine | Self::Container)
    }

    /// All cases in display order (mirrors Swift `CaseIterable`).
    pub fn all() -> &'static [MachineType] {
        &[
            Self::Native,
            Self::SshWaypipe,
            Self::SshTerminal,
            Self::VirtualMachine,
            Self::Container,
        ]
    }
}

/// Live machine session status (mirrors Swift `MachineStatus`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MachineStatus {
    Disconnected,
    Connecting,
    Connected,
    Degraded,
    Error,
}

impl Default for MachineStatus {
    fn default() -> Self {
        Self::Disconnected
    }
}

/// Per-machine runtime overrides. Every field is optional and omitted when
/// `None` to match Swift's `JSONEncoder` (which drops nil optionals). JSON keys
/// are renamed explicitly because the Swift property names use irregular
/// acronym casing that `camelCase` auto-derivation cannot reproduce.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MachineRuntimeOverrides {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub renderer: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "vulkanDriver")]
    pub vulkan_driver: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "openGLDriver")]
    pub open_gl_driver: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "dmabufEnabled")]
    pub dmabuf_enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "inputProfile")]
    pub input_profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "bundledAppID")]
    pub bundled_app_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "waypipeEnabled")]
    pub waypipe_enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "forceSSD")]
    pub force_ssd: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "renderMacOSPointer")]
    pub render_macos_pointer: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "autoScale")]
    pub auto_scale: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "waylandDisplay")]
    pub wayland_display: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "colorOperations")]
    pub color_operations: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "waypipeSSHPassword")]
    pub waypipe_ssh_password: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "logLevel")]
    pub log_level: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "shakeToCloseEnabled")]
    pub shake_to_close_enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "swipeBackToCloseEnabled")]
    pub swipe_back_to_close_enabled: Option<bool>,
}

/// A configured Wayland client launcher (mirrors Swift `ClientLauncher`). The
/// `id` is emitted as an RFC-4122 v4 string so Apple's `UUID` decoder accepts
/// launchers authored on Linux.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClientLauncher {
    #[serde(default = "new_uuid")]
    pub id: String,
    pub name: String,
    #[serde(rename = "executablePath")]
    pub executable_path: String,
    #[serde(default)]
    pub arguments: Vec<String>,
    #[serde(default, rename = "autoLaunch")]
    pub auto_launch: bool,
    #[serde(rename = "displayName")]
    pub display_name: String,
}

impl ClientLauncher {
    pub fn new(name: &str, executable_path: &str, display_name: &str) -> Self {
        Self {
            id: new_uuid(),
            name: name.to_string(),
            executable_path: executable_path.to_string(),
            arguments: Vec::new(),
            auto_launch: false,
            display_name: display_name.to_string(),
        }
    }
}

/// Canonical machine profile. Field order, names, and defaults mirror the Swift
/// `MachineProfile` `CodingKeys` + `decodeIfPresent` fallbacks so partial JSON
/// from any platform decodes successfully.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MachineProfile {
    #[serde(default = "new_uuid")]
    pub id: String,
    #[serde(default = "default_name")]
    pub name: String,
    #[serde(rename = "type", default)]
    pub machine_type: MachineType,
    #[serde(rename = "sshHost", default)]
    pub ssh_host: String,
    #[serde(rename = "sshUser", default)]
    pub ssh_user: String,
    #[serde(rename = "sshPort", default = "default_ssh_port")]
    pub ssh_port: i32,
    #[serde(rename = "sshPassword", default)]
    pub ssh_password: String,
    #[serde(rename = "remoteCommand", default = "default_remote_command")]
    pub remote_command: String,
    #[serde(rename = "vmSubtype", default)]
    pub vm_subtype: String,
    #[serde(rename = "containerSubtype", default)]
    pub container_subtype: String,
    #[serde(default)]
    pub launchers: Vec<ClientLauncher>,
    #[serde(default)]
    pub favorite: bool,
    #[serde(rename = "runtimeOverrides", default)]
    pub runtime_overrides: MachineRuntimeOverrides,
}

impl MachineProfile {
    /// Create a new profile with Swift-matching defaults.
    pub fn new(name: &str) -> Self {
        Self {
            id: new_uuid(),
            name: name.to_string(),
            machine_type: MachineType::Native,
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            remote_command: default_remote_command(),
            vm_subtype: String::new(),
            container_subtype: String::new(),
            launchers: Vec::new(),
            favorite: false,
            runtime_overrides: MachineRuntimeOverrides::default(),
        }
    }

    /// One-line subtitle for cards/rows (mirrors the Linux `summary()` helper).
    pub fn summary(&self) -> String {
        match self.machine_type {
            MachineType::Native => "Nested local Wayland client".to_string(),
            MachineType::SshWaypipe | MachineType::SshTerminal => {
                format!("{}@{}:{}", self.ssh_user, self.ssh_host, self.ssh_port)
            }
            MachineType::VirtualMachine => {
                if self.vm_subtype.is_empty() {
                    "Virtual machine".to_string()
                } else {
                    format!("VM · {}", self.vm_subtype)
                }
            }
            MachineType::Container => {
                if self.container_subtype.is_empty() {
                    "Container".to_string()
                } else {
                    format!("Container · {}", self.container_subtype)
                }
            }
        }
    }

    /// Resolve the command/client this profile launches for native machines,
    /// preferring an explicit `remoteCommand` then the bundled-app override.
    pub fn effective_command(&self) -> String {
        match self.machine_type {
            MachineType::Native => {
                let custom = self.remote_command.trim();
                if !custom.is_empty() {
                    custom.to_string()
                } else if let Some(app) = self
                    .runtime_overrides
                    .bundled_app_id
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    app.to_string()
                } else {
                    "weston-terminal".to_string()
                }
            }
            _ => self.remote_command.clone(),
        }
    }
}

fn default_name() -> String {
    "Unnamed".to_string()
}

fn default_ssh_port() -> i32 {
    22
}

fn default_remote_command() -> String {
    "weston-simple-shm".to_string()
}

/// Generate an RFC-4122 version-4 UUID string (lowercase, hyphenated). Avoids a
/// new crate dependency by using `getrandom`, which is already in the tree.
pub fn new_uuid() -> String {
    let mut bytes = [0u8; 16];
    // getrandom is infallible on the platforms we target; fall back to a
    // time-seeded value only if the OS RNG is somehow unavailable.
    if getrandom::getrandom(&mut bytes).is_err() {
        use std::time::{SystemTime, UNIX_EPOCH};
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        bytes.copy_from_slice(&nanos.to_le_bytes()[..16.min(16)]);
    }
    // Set version (4) and variant (RFC 4122) bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn machine_type_serializes_to_swift_raw_values() {
        assert_eq!(
            serde_json::to_string(&MachineType::SshWaypipe).unwrap(),
            "\"ssh_waypipe\""
        );
        assert_eq!(
            serde_json::to_string(&MachineType::VirtualMachine).unwrap(),
            "\"virtual_machine\""
        );
    }

    #[test]
    fn runtime_overrides_use_swift_acronym_keys() {
        let ov = MachineRuntimeOverrides {
            open_gl_driver: Some("zink".into()),
            bundled_app_id: Some("foot".into()),
            force_ssd: Some(true),
            render_macos_pointer: Some(false),
            waypipe_ssh_password: Some("secret".into()),
            ..Default::default()
        };
        let json = serde_json::to_string(&ov).unwrap();
        assert!(json.contains("\"openGLDriver\":\"zink\""), "{json}");
        assert!(json.contains("\"bundledAppID\":\"foot\""), "{json}");
        assert!(json.contains("\"forceSSD\":true"), "{json}");
        assert!(json.contains("\"renderMacOSPointer\":false"), "{json}");
        assert!(json.contains("\"waypipeSSHPassword\":\"secret\""), "{json}");
        // None fields are omitted, matching Swift's nil-drop behavior.
        assert!(!json.contains("renderer"), "{json}");
    }

    #[test]
    fn profile_round_trips_with_swift_keys() {
        let mut p = MachineProfile::new("Desk");
        p.machine_type = MachineType::SshWaypipe;
        p.ssh_host = "host".into();
        p.ssh_user = "user".into();
        p.favorite = true;
        p.launchers
            .push(ClientLauncher::new("foot", "foot", "Foot Terminal"));

        let json = serde_json::to_string(&p).unwrap();
        assert!(json.contains("\"type\":\"ssh_waypipe\""), "{json}");
        assert!(json.contains("\"sshHost\":\"host\""), "{json}");
        assert!(json.contains("\"runtimeOverrides\":{}"), "{json}");
        assert!(json.contains("\"executablePath\":\"foot\""), "{json}");

        let decoded: MachineProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded, p);
    }

    #[test]
    fn decodes_partial_json_with_swift_defaults() {
        // A profile authored by an older/other platform with only a name.
        let decoded: MachineProfile =
            serde_json::from_str(r#"{"id":"abc","name":"Mini"}"#).unwrap();
        assert_eq!(decoded.name, "Mini");
        assert_eq!(decoded.machine_type, MachineType::Native);
        assert_eq!(decoded.ssh_port, 22);
        assert_eq!(decoded.remote_command, "weston-simple-shm");
        assert!(decoded.launchers.is_empty());
        assert!(!decoded.favorite);
    }

    #[test]
    fn new_uuid_is_v4_shaped() {
        let id = new_uuid();
        assert_eq!(id.len(), 36);
        let parts: Vec<&str> = id.split('-').collect();
        assert_eq!(parts.iter().map(|p| p.len()).collect::<Vec<_>>(), vec![8, 4, 4, 4, 12]);
        assert!(id.as_bytes()[14] == b'4'); // version nibble
    }
}
