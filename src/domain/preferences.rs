use serde::{Deserialize, Serialize};

use super::{MachineProfile, MachineType};

/// Runtime capabilities reported mechanically by the platform adapter.
/// Product behavior is derived from these values in Rust.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlatformCapabilities {
    pub platform: PlatformKind,
    pub gpu_stack: bool,
    pub client_side_decorations: bool,
    pub external_processes: bool,
    pub default_vulkan_driver: String,
}

impl Default for PlatformCapabilities {
    fn default() -> Self {
        Self::for_current_target()
    }
}

impl PlatformCapabilities {
    pub fn for_current_target() -> Self {
        #[cfg(target_os = "macos")]
        {
            return Self {
                platform: PlatformKind::MacOs,
                gpu_stack: true,
                client_side_decorations: true,
                external_processes: true,
                default_vulkan_driver: "moltenvk".into(),
            };
        }
        #[cfg(target_os = "ios")]
        {
            return Self {
                platform: PlatformKind::Ios,
                gpu_stack: true,
                client_side_decorations: false,
                external_processes: false,
                default_vulkan_driver: "moltenvk".into(),
            };
        }
        #[cfg(target_os = "android")]
        {
            return Self {
                platform: PlatformKind::Android,
                gpu_stack: true,
                client_side_decorations: false,
                external_processes: true,
                default_vulkan_driver: "native".into(),
            };
        }
        #[cfg(target_os = "linux")]
        {
            return Self {
                platform: PlatformKind::Linux,
                gpu_stack: true,
                client_side_decorations: true,
                external_processes: true,
                default_vulkan_driver: "native".into(),
            };
        }
        #[allow(unreachable_code)]
        Self {
            platform: PlatformKind::Other,
            gpu_stack: false,
            client_side_decorations: false,
            external_processes: false,
            default_vulkan_driver: "none".into(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlatformKind {
    Ios,
    IpadOs,
    MacOs,
    TvOs,
    WatchOs,
    VisionOs,
    Android,
    Linux,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Preferences {
    pub renderer: String,
    pub vulkan_driver: String,
    pub open_gl_driver: String,
    pub force_ssd: bool,
    pub render_macos_pointer: bool,
    pub nested_compositor_cursor: String,
    pub auto_scale: bool,
    pub color_operations: bool,
    pub wayland_display: String,
    pub ssh_host: String,
    pub ssh_user: String,
    pub ssh_port: i32,
    pub ssh_password: String,
    pub ssh_auth_method: i32,
    pub ssh_key_path: String,
    pub ssh_key_passphrase: String,
    pub ssh_key_type: String,
    pub waypipe_ssh_password: String,
    pub log_level: String,
    pub default_input_profile: String,
    pub default_bundled_app_id: String,
    pub default_waypipe_enabled: bool,
    pub xwayland_support: bool,
    pub shake_to_close_enabled: bool,
    pub swipe_back_to_close_enabled: bool,
    pub has_completed_welcome: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            renderer: "metal".into(),
            vulkan_driver: PlatformCapabilities::for_current_target().default_vulkan_driver,
            open_gl_driver: "angle".into(),
            force_ssd: false,
            render_macos_pointer: false,
            nested_compositor_cursor: "virtual".into(),
            auto_scale: true,
            color_operations: false,
            wayland_display: "wayland-0".into(),
            ssh_host: String::new(),
            ssh_user: String::new(),
            ssh_port: 22,
            ssh_password: String::new(),
            ssh_auth_method: 0,
            ssh_key_path: String::new(),
            ssh_key_passphrase: String::new(),
            ssh_key_type: "ed25519".into(),
            waypipe_ssh_password: String::new(),
            log_level: "info".into(),
            default_input_profile: "Multi-Touch".into(),
            default_bundled_app_id: "weston-terminal".into(),
            default_waypipe_enabled: true,
            xwayland_support: false,
            shake_to_close_enabled: true,
            swipe_back_to_close_enabled: true,
            has_completed_welcome: false,
        }
    }
}

impl Preferences {
    pub fn normalize(&mut self, capabilities: &PlatformCapabilities) {
        self.renderer = nonempty(&self.renderer, "metal");
        self.vulkan_driver = if capabilities.gpu_stack {
            nonempty(&self.vulkan_driver, &capabilities.default_vulkan_driver)
        } else {
            "none".into()
        };
        self.open_gl_driver = if capabilities.gpu_stack {
            nonempty(&self.open_gl_driver, "angle")
        } else {
            "none".into()
        };
        self.nested_compositor_cursor = match self.nested_compositor_cursor.trim() {
            "host" => "host".into(),
            _ => "virtual".into(),
        };
        self.wayland_display = nonempty(&self.wayland_display, "wayland-0");
        self.ssh_port = valid_port(self.ssh_port).unwrap_or(22);
        self.ssh_auth_method = i32::from(self.ssh_auth_method == 1);
        self.ssh_key_type = nonempty(&self.ssh_key_type, "ed25519");
        self.log_level = normalize_log_level(&self.log_level);
        self.default_input_profile = normalize_touch_input(&self.default_input_profile).into();
        if !capabilities.client_side_decorations {
            self.force_ssd = true;
        }
        if !capabilities.external_processes {
            self.xwayland_support = false;
        }
    }

    pub fn resolve(
        &self,
        profile: &MachineProfile,
        capabilities: &PlatformCapabilities,
    ) -> ResolvedMachineSettings {
        let overrides = &profile.runtime_overrides;
        let remote = matches!(
            profile.machine_type,
            MachineType::SshWaypipe | MachineType::SshTerminal
        );
        ResolvedMachineSettings {
            machine_id: profile.id.clone(),
            machine_name: nonempty(&profile.name, "Unnamed"),
            machine_type: profile.machine_type,
            renderer: optional_nonempty(overrides.renderer.as_deref())
                .unwrap_or_else(|| self.renderer.clone()),
            vulkan_driver: if capabilities.gpu_stack {
                optional_nonempty(overrides.vulkan_driver.as_deref())
                    .unwrap_or_else(|| self.vulkan_driver.clone())
            } else {
                "none".into()
            },
            open_gl_driver: if capabilities.gpu_stack {
                optional_nonempty(overrides.open_gl_driver.as_deref())
                    .unwrap_or_else(|| self.open_gl_driver.clone())
            } else {
                "none".into()
            },
            dmabuf_enabled: capabilities.gpu_stack && overrides.dmabuf_enabled.unwrap_or(true),
            force_ssd: if capabilities.client_side_decorations {
                overrides.force_ssd.unwrap_or(self.force_ssd)
            } else {
                true
            },
            render_macos_pointer: overrides
                .render_macos_pointer
                .unwrap_or(self.render_macos_pointer),
            nested_compositor_cursor: optional_nonempty(
                overrides.nested_compositor_cursor.as_deref(),
            )
            .filter(|value| value == "host" || value == "virtual")
            .unwrap_or_else(|| self.nested_compositor_cursor.clone()),
            auto_scale: overrides.auto_scale.unwrap_or(self.auto_scale),
            color_operations: overrides.color_operations.unwrap_or(self.color_operations),
            wayland_display: optional_nonempty(overrides.wayland_display.as_deref())
                .unwrap_or_else(|| self.wayland_display.clone()),
            ssh_host: nonempty_or(&profile.ssh_host, &self.ssh_host),
            ssh_user: nonempty_or(&profile.ssh_user, &self.ssh_user),
            ssh_port: valid_port(profile.ssh_port).unwrap_or(self.ssh_port),
            ssh_password: nonempty_or(&profile.ssh_password, &self.ssh_password),
            waypipe_ssh_password: optional_nonempty(
                overrides.waypipe_ssh_password.as_deref(),
            )
            .unwrap_or_else(|| self.waypipe_ssh_password.clone()),
            remote_command: nonempty(&profile.remote_command, "weston-simple-shm"),
            waypipe_enabled: remote
                && overrides
                    .waypipe_enabled
                    .unwrap_or(self.default_waypipe_enabled),
            bundled_app_id: optional_nonempty(overrides.bundled_app_id.as_deref())
                .unwrap_or_else(|| self.default_bundled_app_id.clone()),
            input_profile: normalize_touch_input(
                optional_nonempty(overrides.input_profile.as_deref())
                    .as_deref()
                    .unwrap_or(&self.default_input_profile),
            )
            .into(),
            log_level: optional_nonempty(overrides.log_level.as_deref())
                .map(|value| normalize_log_level(&value))
                .unwrap_or_else(|| self.log_level.clone()),
            shake_to_close_enabled: overrides
                .shake_to_close_enabled
                .unwrap_or(self.shake_to_close_enabled),
            swipe_back_to_close_enabled: overrides
                .swipe_back_to_close_enabled
                .unwrap_or(self.swipe_back_to_close_enabled),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedMachineSettings {
    pub machine_id: String,
    pub machine_name: String,
    pub machine_type: MachineType,
    pub renderer: String,
    pub vulkan_driver: String,
    pub open_gl_driver: String,
    pub dmabuf_enabled: bool,
    pub force_ssd: bool,
    pub render_macos_pointer: bool,
    pub nested_compositor_cursor: String,
    pub auto_scale: bool,
    pub color_operations: bool,
    pub wayland_display: String,
    pub ssh_host: String,
    pub ssh_user: String,
    pub ssh_port: i32,
    pub ssh_password: String,
    pub waypipe_ssh_password: String,
    pub remote_command: String,
    pub waypipe_enabled: bool,
    pub bundled_app_id: String,
    pub input_profile: String,
    pub log_level: String,
    pub shake_to_close_enabled: bool,
    pub swipe_back_to_close_enabled: bool,
}

pub fn normalize_touch_input(raw: &str) -> &'static str {
    match raw.trim().to_ascii_lowercase().as_str() {
        "touchpad" | "pointer" | "virtual" | "virtual-pointer" | "trackpad" => "Touchpad",
        _ => "Multi-Touch",
    }
}

fn normalize_log_level(raw: &str) -> String {
    match raw.trim().to_ascii_lowercase().as_str() {
        "trace" => "trace",
        "debug" => "debug",
        "warn" => "warn",
        "error" => "error",
        _ => "info",
    }
    .into()
}

fn valid_port(port: i32) -> Option<i32> {
    (1..=65535).contains(&port).then_some(port)
}

fn nonempty(value: &str, fallback: &str) -> String {
    optional_nonempty(Some(value)).unwrap_or_else(|| fallback.into())
}

fn nonempty_or(value: &str, fallback: &str) -> String {
    optional_nonempty(Some(value)).unwrap_or_else(|| fallback.into())
}

fn optional_nonempty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_policy_in_rust() {
        let capabilities = PlatformCapabilities {
            platform: PlatformKind::Ios,
            gpu_stack: true,
            client_side_decorations: false,
            external_processes: false,
            default_vulkan_driver: "swiftshader".into(),
        };
        let mut preferences = Preferences {
            ssh_port: 70_000,
            default_input_profile: "direct".into(),
            force_ssd: false,
            xwayland_support: true,
            vulkan_driver: String::new(),
            ..Default::default()
        };
        preferences.normalize(&capabilities);
        assert_eq!(preferences.ssh_port, 22);
        assert_eq!(preferences.default_input_profile, "Multi-Touch");
        assert_eq!(preferences.vulkan_driver, "swiftshader");
        assert!(preferences.force_ssd);
        assert!(!preferences.xwayland_support);
    }

    #[test]
    fn resolves_profile_overrides_and_platform_policy() {
        let capabilities = PlatformCapabilities {
            platform: PlatformKind::Ios,
            gpu_stack: false,
            client_side_decorations: false,
            external_processes: false,
            default_vulkan_driver: "none".into(),
        };
        let preferences = Preferences::default();
        let mut profile = MachineProfile::new("Phone");
        profile.runtime_overrides.force_ssd = Some(false);
        profile.runtime_overrides.vulkan_driver = Some("swiftshader".into());
        let resolved = preferences.resolve(&profile, &capabilities);
        assert_eq!(resolved.vulkan_driver, "none");
        assert_eq!(resolved.open_gl_driver, "none");
        assert!(resolved.force_ssd);
    }
}
