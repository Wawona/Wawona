//! Canonical `wawona.machineProfiles.v1` schema.
//!
//! Source of truth for Apple, Android, and Linux. Serde keys match Swift
//! `Codable` byte-for-byte (including `openGLDriver`, `bundledAppID`,
//! `forceSSD`, `renderMacOSPointer`, `waypipeSSHPassword`). UniFFI exports the
//! same records. Do not add fields only in Swift, Kotlin, or
//! `src/linux/machine_profile.rs`.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

/// Machine connection type. Serialized as snake_case to match Swift
/// `MachineType` rawValues.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum MachineType {
    Native,
    Wasm,
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
    pub fn user_facing_name(&self) -> &'static str {
        match self {
            Self::Native => "Native",
            Self::Wasm => "Wasm",
            Self::SshWaypipe => "SSH + Waypipe",
            Self::SshTerminal => "SSH Terminal",
            Self::VirtualMachine => "Virtual Machine",
            Self::Container => "Container",
        }
    }

    /// Freedesktop icon name (Linux GTK).
    pub fn icon_name(&self) -> &'static str {
        match self {
            Self::Native => "computer-symbolic",
            Self::Wasm => "application-x-executable-symbolic",
            Self::SshWaypipe => "network-workgroup-symbolic",
            Self::SshTerminal => "utilities-terminal-symbolic",
            Self::VirtualMachine => "computer-apple-ipad-symbolic",
            Self::Container => "package-x-generic-symbolic",
        }
    }

    pub fn is_remote(&self) -> bool {
        matches!(self, Self::SshWaypipe | Self::SshTerminal)
    }

    pub fn is_local(self) -> bool {
        matches!(
            self,
            Self::Native | Self::Wasm | Self::VirtualMachine | Self::Container
        )
    }

    pub fn all() -> &'static [MachineType] {
        &[
            Self::Native,
            Self::Wasm,
            Self::SshWaypipe,
            Self::SshTerminal,
            Self::VirtualMachine,
            Self::Container,
        ]
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
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

/// Persisted env override. JSON `{ "action": "set"|"unset", "value": "..." }`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct DomainEnvironmentOverride {
    pub action: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct MachineRuntimeOverrides {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub renderer: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "vulkanDriver"
    )]
    pub vulkan_driver: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "openGLDriver"
    )]
    pub open_gl_driver: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "dmabufEnabled"
    )]
    pub dmabuf_enabled: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "inputProfile"
    )]
    pub input_profile: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "bundledAppID"
    )]
    pub bundled_app_id: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "wasmModulePath"
    )]
    pub wasm_module_path: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "wasmLaunchMode"
    )]
    pub wasm_launch_mode: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "wasmPackage"
    )]
    pub wasm_package: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "wasmCommand"
    )]
    pub wasm_command: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "waypipeEnabled"
    )]
    pub waypipe_enabled: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "forceSSD")]
    pub force_ssd: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "renderMacOSPointer"
    )]
    pub render_macos_pointer: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "nestedCompositorCursor"
    )]
    pub nested_compositor_cursor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "autoScale")]
    pub auto_scale: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "waylandDisplay"
    )]
    pub wayland_display: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "colorOperations"
    )]
    pub color_operations: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "waypipeSSHPassword"
    )]
    pub waypipe_ssh_password: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "logLevel")]
    pub log_level: Option<String>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "shakeToCloseEnabled"
    )]
    pub shake_to_close_enabled: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "swipeBackToCloseEnabled"
    )]
    pub swipe_back_to_close_enabled: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "resizeDisplayForVirtualKeyboard"
    )]
    pub resize_display_for_virtual_keyboard: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "compositorBackend"
    )]
    pub compositor_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub environment: Option<HashMap<String, DomainEnvironmentOverride>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct ContainerMachineSettings {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "containerRef")]
    pub container_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "entryCommand")]
    pub entry_command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "shmSize")]
    pub shm_size: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mounts: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ports: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "readOnly")]
    pub read_only: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "initProcess")]
    pub init_process: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub remove: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "kernelPath")]
    pub kernel_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "initfsPath")]
    pub initfs_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "vsockPort")]
    pub vsock_port: Option<i32>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "desktopSession"
    )]
    pub desktop_session: Option<bool>,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "imageArchivePath"
    )]
    pub image_archive_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
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
    #[serde(default, rename = "requiresGpuStack")]
    pub requires_gpu_stack: bool,
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
            requires_gpu_stack: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
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
    #[serde(rename = "sshAuthMethod", default)]
    pub ssh_auth_method: i32,
    #[serde(rename = "sshKeyPath", default)]
    pub ssh_key_path: String,
    #[serde(rename = "sshKeyPassphrase", default)]
    pub ssh_key_passphrase: String,
    #[serde(rename = "remoteCommand", default = "default_remote_command")]
    pub remote_command: String,
    #[serde(default)]
    pub launchers: Vec<ClientLauncher>,
    #[serde(default)]
    pub favorite: bool,
    #[serde(rename = "runtimeOverrides", default)]
    pub runtime_overrides: MachineRuntimeOverrides,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        rename = "containerSettings"
    )]
    pub container_settings: Option<ContainerMachineSettings>,
}

impl Default for MachineProfile {
    fn default() -> Self {
        Self::new("Unnamed")
    }
}

impl MachineProfile {
    pub fn new(name: &str) -> Self {
        Self {
            id: new_uuid(),
            name: name.to_string(),
            machine_type: MachineType::Native,
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            ssh_auth_method: 0,
            ssh_key_path: String::new(),
            ssh_key_passphrase: String::new(),
            remote_command: default_remote_command(),
            launchers: Vec::new(),
            favorite: false,
            runtime_overrides: MachineRuntimeOverrides::default(),
            container_settings: None,
        }
    }

    pub fn summary(&self) -> String {
        match self.machine_type {
            MachineType::Native => "Nested local Wayland client".to_string(),
            MachineType::Wasm => "Relay WASI (wasm / wpm)".to_string(),
            MachineType::SshWaypipe | MachineType::SshTerminal => {
                format!("{}@{}:{}", self.ssh_user, self.ssh_host, self.ssh_port)
            }
            MachineType::VirtualMachine => "Virtual machine".to_string(),
            MachineType::Container => "Container".to_string(),
        }
    }

    pub fn effective_command(&self) -> String {
        match self.machine_type {
            MachineType::Native => {
                if let Some(app) = self
                    .runtime_overrides
                    .bundled_app_id
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    app.to_string()
                } else {
                    let custom = self.remote_command.trim();
                    if custom.is_empty() {
                        "weston-terminal".to_string()
                    } else {
                        custom.to_string()
                    }
                }
            }
            MachineType::Wasm => self
                .runtime_overrides
                .wasm_command
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(|s| s.to_string())
                .unwrap_or_else(|| "wasm hello-wasi-gui".to_string()),
            _ => self.remote_command.clone(),
        }
    }

    pub fn resolved_native_client_id(&self) -> String {
        if let Some(candidate) = self
            .runtime_overrides
            .bundled_app_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            return candidate.to_ascii_lowercase();
        }
        if let Some(auto) = self
            .launchers
            .iter()
            .find(|l| l.auto_launch)
            .or_else(|| self.launchers.first())
        {
            let name = auto.name.trim();
            if !name.is_empty() {
                return name.to_ascii_lowercase();
            }
        }
        self.remote_command
            .trim()
            .to_ascii_lowercase()
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

pub fn new_uuid() -> String {
    let mut bytes = [0u8; 16];
    if getrandom::getrandom(&mut bytes).is_err() {
        use std::time::{SystemTime, UNIX_EPOCH};
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let le = nanos.to_le_bytes();
        bytes[..16.min(le.len())].copy_from_slice(&le[..16.min(le.len())]);
    }
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
        assert_eq!(
            serde_json::to_string(&MachineType::Wasm).unwrap(),
            "\"wasm\""
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
        assert!(!json.contains("renderer"), "{json}");
    }

    #[test]
    fn runtime_overrides_rename_resize_display_for_virtual_keyboard() {
        let ov = MachineRuntimeOverrides {
            resize_display_for_virtual_keyboard: Some(false),
            ..Default::default()
        };
        let json = serde_json::to_string(&ov).unwrap();
        assert!(
            json.contains("\"resizeDisplayForVirtualKeyboard\":false"),
            "{json}"
        );
        let decoded: MachineRuntimeOverrides = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.resize_display_for_virtual_keyboard, Some(false));
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
        assert!(json.contains("\"sshAuthMethod\":0"), "{json}");
        assert!(json.contains("\"runtimeOverrides\":{}"), "{json}");
        assert!(json.contains("\"executablePath\":\"foot\""), "{json}");

        let decoded: MachineProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded, p);
    }

    #[test]
    fn decodes_partial_json_with_swift_defaults() {
        let decoded: MachineProfile =
            serde_json::from_str(r#"{"id":"abc","name":"Mini"}"#).unwrap();
        assert_eq!(decoded.name, "Mini");
        assert_eq!(decoded.machine_type, MachineType::Native);
        assert_eq!(decoded.ssh_port, 22);
        assert_eq!(decoded.remote_command, "weston-simple-shm");
        assert_eq!(decoded.ssh_auth_method, 0);
        assert!(decoded.launchers.is_empty());
        assert!(!decoded.favorite);
        assert!(decoded.container_settings.is_none());
    }

    #[test]
    fn decodes_legacy_apple_v1_blob() {
        // Keys as written by Sources/WawonaModel MachineProfile.encode before
        // the rust lift. Extra / older keys must not fail decode.
        let json = r#"[
          {
            "id": "legacy-1",
            "name": "Office",
            "type": "ssh_waypipe",
            "sshHost": "box.local",
            "sshUser": "ada",
            "sshPort": 2222,
            "sshPassword": "",
            "sshAuthMethod": 1,
            "sshKeyPath": "/tmp/id_ed25519",
            "sshKeyPassphrase": "",
            "remoteCommand": "weston-terminal",
            "vmSubtype": "qemu",
            "containerSubtype": "docker",
            "launchers": [],
            "favorite": true,
            "runtimeOverrides": {
              "bundledAppID": "weston-terminal",
              "openGLDriver": "zink",
              "forceSSD": true,
              "wasmCommand": "wasm hello-wasi-gui",
              "environment": {
                "WAYLAND_DISPLAY": { "action": "set", "value": "wayland-1" }
              }
            },
            "containerSettings": {
              "containerRef": "alpine:3.20",
              "desktopSession": true
            }
          }
        ]"#;
        let decoded: Vec<MachineProfile> = serde_json::from_str(json).unwrap();
        assert_eq!(decoded.len(), 1);
        let p = &decoded[0];
        assert_eq!(p.id, "legacy-1");
        assert_eq!(p.name, "Office");
        assert_eq!(p.machine_type, MachineType::SshWaypipe);
        assert_eq!(p.ssh_host, "box.local");
        assert_eq!(p.ssh_user, "ada");
        assert_eq!(p.ssh_port, 2222);
        assert_eq!(p.ssh_auth_method, 1);
        assert_eq!(p.ssh_key_path, "/tmp/id_ed25519");
        assert_eq!(p.remote_command, "weston-terminal");
        assert!(p.favorite);
        assert_eq!(
            p.runtime_overrides.bundled_app_id.as_deref(),
            Some("weston-terminal")
        );
        assert_eq!(p.runtime_overrides.open_gl_driver.as_deref(), Some("zink"));
        assert_eq!(p.runtime_overrides.force_ssd, Some(true));
        let env = p.runtime_overrides.environment.as_ref().unwrap();
        assert_eq!(env["WAYLAND_DISPLAY"].action, "set");
        assert_eq!(env["WAYLAND_DISPLAY"].value.as_deref(), Some("wayland-1"));
        assert_eq!(
            p.container_settings
                .as_ref()
                .and_then(|c| c.container_ref.as_deref()),
            Some("alpine:3.20")
        );
        assert_eq!(
            p.container_settings
                .as_ref()
                .and_then(|c| c.desktop_session),
            Some(true)
        );
    }

    #[test]
    fn new_uuid_is_v4_shaped() {
        let id = new_uuid();
        assert_eq!(id.len(), 36);
        let parts: Vec<&str> = id.split('-').collect();
        assert_eq!(
            parts.iter().map(|p| p.len()).collect::<Vec<_>>(),
            vec![8, 4, 4, 4, 12]
        );
        assert!(id.as_bytes()[14] == b'4');
    }
}
