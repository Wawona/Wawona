//! Product domain: machine profiles, validation, store.
//!
//! UniFFI + this module own the schema. `WWNCore*` stays the compositor ABI.
//!
//! `settings_catalog` lives in this file so a dirty git flake (no commit)
//! still ships the module. Nix `git+file` copies tracked files only.

pub mod c_api;
pub mod client_catalog;
pub mod darwin_cli;
pub mod error;
pub mod launch_resolve;
pub mod machine_profile;
pub mod prefs_keys;
pub mod profile_store;
pub mod sanitize_ssh_host;
pub mod tab_overview;
pub mod uniffi_api;
pub mod validation;
pub mod welcome_copy;

pub mod settings_catalog {
    //! Global Settings sidebar catalog. One list for every host UI
    //! (SwiftUI split, Watch list, Android Compose, GTK).

    #[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
    pub enum SettingsHost {
        MacOs,
        Ios,
        TvOs,
        WatchOs,
        VisionOs,
        Android,
        Linux,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
    pub enum SettingsSectionId {
        Display,
        Input,
        Graphics,
        Connection,
        Environment,
        LocalShell,
        Machines,
        ICloudSync,
        AppleWatch,
        Desktop,
        Waypipe,
        Ssh,
        About,
        Dependencies,
    }

    impl SettingsSectionId {
        pub fn title(self) -> &'static str {
            match self {
                Self::Display => "Display",
                Self::Input => "Input",
                Self::Graphics => "Graphics",
                Self::Connection => "Connection",
                Self::Environment => "Env Vars",
                Self::LocalShell => "Local Shell",
                Self::Machines => "Machines",
                Self::ICloudSync => "iCloud Sync",
                Self::AppleWatch => "Apple Watch",
                Self::Desktop => "Desktop",
                Self::Waypipe => "Waypipe",
                Self::Ssh => "SSH",
                Self::About => "About",
                Self::Dependencies => "Dependencies",
            }
        }

        pub fn slug(self) -> &'static str {
            match self {
                Self::Display => "display",
                Self::Input => "input",
                Self::Graphics => "graphics",
                Self::Connection => "connection",
                Self::Environment => "environment",
                Self::LocalShell => "localShell",
                Self::Machines => "machines",
                Self::ICloudSync => "iCloudSync",
                Self::AppleWatch => "appleWatch",
                Self::Desktop => "desktop",
                Self::Waypipe => "waypipe",
                Self::Ssh => "ssh",
                Self::About => "about",
                Self::Dependencies => "dependencies",
            }
        }
    }

    /// Parse the host slug used by C / UniFFI callers (`macos`, `ios`, …).
    pub fn host_from_slug(slug: &str) -> Option<SettingsHost> {
        match slug {
            "macos" | "macOS" | "MacOs" => Some(SettingsHost::MacOs),
            "ios" | "iOS" | "Ios" => Some(SettingsHost::Ios),
            "tvos" | "tvOS" | "TvOs" => Some(SettingsHost::TvOs),
            "watchos" | "watchOS" | "WatchOs" => Some(SettingsHost::WatchOs),
            "visionos" | "visionOS" | "VisionOs" => Some(SettingsHost::VisionOs),
            "android" | "Android" => Some(SettingsHost::Android),
            "linux" | "Linux" => Some(SettingsHost::Linux),
            _ => None,
        }
    }

    /// Sidebar order for a host. Swift `GlobalSettingsCatalog.visibleSections`
    /// and Android / GTK sidebars must match this list (Linux extras such as
    /// Launch Agent stay after About / Dependencies).
    pub fn visible_sections(host: SettingsHost) -> Vec<SettingsSectionId> {
        use SettingsSectionId::*;
        match host {
            SettingsHost::MacOs => vec![
                Display,
                Input,
                Graphics,
                Environment,
                ICloudSync,
                Desktop,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
            SettingsHost::Ios => {
                let mut sections = vec![
                    Display,
                    Input,
                    Graphics,
                    Environment,
                    ICloudSync,
                    AppleWatch,
                ];
                // Store IPA must not list Desktop. TrollStore tipa and Sileo
                // Mode B compile with profile-ios-mode-b (IOMFB + igetty).
                #[cfg(feature = "profile-ios-mode-b")]
                sections.push(Desktop);
                sections.extend([Waypipe, Ssh, About, Dependencies]);
                sections
            }
            SettingsHost::VisionOs => vec![
                Display,
                Input,
                Graphics,
                Environment,
                ICloudSync,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
            // Android Mode A: Default Home + LockScreen replacement (no SIP).
            // Linux: Desktop/LockScreen forbidden (product map).
            SettingsHost::Android => vec![
                Display,
                Input,
                Graphics,
                Environment,
                Desktop,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
            SettingsHost::Linux => vec![
                Display,
                Input,
                Graphics,
                Environment,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
            SettingsHost::TvOs => vec![
                Display,
                Input,
                Graphics,
                Environment,
                ICloudSync,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
            SettingsHost::WatchOs => vec![
                Display,
                Input,
                Graphics,
                Environment,
                ICloudSync,
                Waypipe,
                Ssh,
                About,
                Dependencies,
            ],
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn macos_has_desktop_ios_store_does_not() {
            let mac = visible_sections(SettingsHost::MacOs);
            let ios = visible_sections(SettingsHost::Ios);
            assert!(mac.contains(&SettingsSectionId::Desktop));
            #[cfg(not(feature = "profile-ios-mode-b"))]
            assert!(!ios.contains(&SettingsSectionId::Desktop));
            #[cfg(feature = "profile-ios-mode-b")]
            assert!(ios.contains(&SettingsSectionId::Desktop));
            assert!(ios.contains(&SettingsSectionId::AppleWatch));
            assert!(!mac.contains(&SettingsSectionId::AppleWatch));
        }

        #[test]
        fn tvos_has_cloudkit_sync_but_no_local_shell() {
            let tv = visible_sections(SettingsHost::TvOs);
            assert!(tv.contains(&SettingsSectionId::ICloudSync));
            assert!(visible_sections(SettingsHost::WatchOs).contains(&SettingsSectionId::ICloudSync));
            assert!(!visible_sections(SettingsHost::Android).contains(&SettingsSectionId::ICloudSync));
            assert!(!visible_sections(SettingsHost::Linux).contains(&SettingsSectionId::ICloudSync));
            assert!(!tv.contains(&SettingsSectionId::LocalShell));
            assert!(!tv.contains(&SettingsSectionId::Desktop));
        }

        #[test]
        fn android_has_desktop_linux_does_not() {
            let android = visible_sections(SettingsHost::Android);
            let linux = visible_sections(SettingsHost::Linux);
            assert!(android.contains(&SettingsSectionId::Desktop));
            assert!(!linux.contains(&SettingsSectionId::Desktop));
            assert_eq!(host_from_slug("ios"), Some(SettingsHost::Ios));
        }
    }
}

#[cfg(test)]
mod capability_tests {
    use super::capabilities::gate;

    #[test]
    fn visionos_vm_and_container_forbidden() {
        assert_eq!(gate("visionos", "vm"), "forbidden");
        assert_eq!(gate("visionos", "container"), "forbidden");
        assert_eq!(gate("tvos", "vm"), "forbidden");
        assert_eq!(gate("watchos", "container"), "forbidden");
    }

    #[test]
    fn macos_container_available_vm_planned() {
        assert_eq!(gate("macos", "container"), "available");
        assert_eq!(gate("macos", "vm"), "planned");
        assert_eq!(gate("ios", "container"), "planned");
    }

    #[test]
    fn watchos_gpu_blocked_wasm_available() {
        assert_eq!(gate("watchos", "gpu"), "blocked");
        assert_eq!(gate("watchos", "wasm"), "available");
        assert_eq!(gate("watchos", "watch_present"), "available");
        assert_eq!(gate("macos", "watch_present"), "forbidden");
        assert_eq!(gate("ios", "apple_containerization"), "forbidden");
        assert_eq!(gate("macos", "apple_containerization"), "available");
    }

    #[test]
    fn cloudkit_sync_on_every_apple_target_drive_home_blocked_on_tv_watch() {
        for p in ["macos", "ios", "ipados", "tvos", "watchos", "visionos"] {
            assert_eq!(gate(p, "cloudkit_sync"), "available", "{p}");
        }
        assert_eq!(gate("android", "cloudkit_sync"), "forbidden");
        assert_eq!(gate("linux", "cloudkit_sync"), "forbidden");
        assert_eq!(gate("watchos", "icloud_drive_home"), "blocked");
        assert_eq!(gate("tvos", "icloud_drive_home"), "blocked");
        assert_eq!(gate("ios", "icloud_drive_home"), "available");
    }
}

/// CloudKit sync policy. Hosts own CKRecord transport only. Which keys
/// travel, what is redacted, which HOME paths are skipped, and who wins a
/// conflict are decided here so every Apple target agrees.
pub mod cloud_sync {
    use super::error::DomainError;
    use super::machine_profile::MachineProfile;

    pub const PROFILES_KEY: &str = "wawona.machineProfiles.v1";

    /// UserDefaults keys mirrored through the private CloudKit database.
    /// Device-shaped prefs (renderer, drivers, display scale, touch mode,
    /// compositor backend, welcome flags, key file paths) stay local.
    /// Passwords and passphrases never leave the device.
    pub const SYNCED_DEFAULTS_KEYS: &[&str] = &[
        PROFILES_KEY,
        "wawona.machines.tags",
        "wawona.machines.tagAssignments",
        "wawona.machines.pinnedMachineIds",
        "wawona.pref.environment.v1",
        "ForceServerSideDecorations",
        "wawona.pref.forceSSD",
        "ColorOperations",
        "wawona.pref.colorOperations",
        "NestedCompositorsSupport",
        "wawona.pref.nestedCompositorsSupport",
        "MultipleClients",
        "wawona.pref.multipleClients",
        "UniversalClipboard",
        "wawona.pref.universalClipboard",
        "MachineSessionThumbnailsEnabled",
        "wawona.pref.machineSessionThumbnailsEnabled",
        "wawona.pref.shakeToCloseEnabled",
        "wawona.pref.swipeBackToCloseEnabled",
        "wawona.pref.logLevel",
        "wawona.pref.diagnostics",
        "wawona.pref.defaultWaypipeEnabled",
        "WaypipeCompress",
        "wawona.pref.waypipeCompress",
        "WaypipeDebug",
        "wawona.pref.waypipeDebug",
        "WaypipeNoGpu",
        "wawona.pref.waypipeNoGpu",
        "WaypipeVideo",
        "wawona.pref.waypipeVideo",
        "WaypipeXwls",
        "wawona.pref.xwaylandSupport",
        "WaypipeRemoteCommand",
        "wawona.pref.waypipeRemoteCommand",
        "WaypipeSSHAuthMethod",
        "SSHHost",
        "wawona.pref.sshHost",
        "SSHUser",
        "wawona.pref.sshUser",
        "SSHPort",
        "wawona.pref.sshPort",
        "SSHAuthMethod",
        "wawona.pref.sshAuthMethod",
        "SSHKeyType",
        "wawona.pref.sshKeyType",
    ];

    pub fn is_synced_defaults_key(key: &str) -> bool {
        SYNCED_DEFAULTS_KEYS.contains(&key)
    }

    /// Largest single HOME file mirrored as a CKAsset.
    pub const HOME_MAX_FILE_BYTES: u64 = 25 * 1024 * 1024;

    /// Most HOME files mirrored per device. Keeps a stray `node_modules`
    /// from turning one sync into thousands of uploads.
    pub const HOME_MAX_FILES: u32 = 2_000;

    /// `rel` is relative to HOME with `/` separators.
    pub fn home_path_excluded(rel: &str) -> bool {
        let rel = rel.trim_start_matches('/');
        if rel.is_empty() {
            return true;
        }
        const SKIP_DIRS: &[&str] = &[".cache", ".Trash", "inbox", ".local/state", ".zsh_sessions"];
        if SKIP_DIRS
            .iter()
            .any(|d| rel == *d || rel.starts_with(&format!("{d}/")))
        {
            return true;
        }
        let name = rel.rsplit('/').next().unwrap_or(rel);
        matches!(name, ".DS_Store" | ".zcompdump") || name.starts_with(".zcompdump-") || name.ends_with(".icloud")
    }

    /// Last writer wins. A key or file this device never synced yields to
    /// the cloud copy so a fresh install does not overwrite real data with
    /// defaults. Ties keep the local value.
    pub fn prefer_remote(local_modified_ms: i64, remote_modified_ms: i64, local_ever_synced: bool) -> bool {
        if !local_ever_synced {
            return true;
        }
        remote_modified_ms > local_modified_ms
    }

    fn redact(p: &mut MachineProfile) {
        p.ssh_password.clear();
        p.ssh_key_passphrase.clear();
        p.runtime_overrides.waypipe_ssh_password = None;
    }

    fn parse(json: &str) -> Result<Vec<MachineProfile>, DomainError> {
        let trimmed = json.trim();
        if trimmed.is_empty() {
            return Ok(Vec::new());
        }
        serde_json::from_str(trimmed).map_err(|e| DomainError::invalid_json(e.to_string()))
    }

    fn render(list: &[MachineProfile]) -> Result<String, DomainError> {
        serde_json::to_string(list).map_err(|e| DomainError::invalid_json(e.to_string()))
    }

    /// Profiles document as uploaded: secrets stripped.
    pub fn redact_profiles_json(json: &str) -> Result<String, DomainError> {
        let mut list = parse(json)?;
        list.iter_mut().for_each(redact);
        render(&list)
    }

    /// Apply a cloud profiles document onto the local one. Remote order and
    /// fields win; secrets for the same machine id come from local. On the
    /// first sync (`bootstrap`) local-only machines are kept so a device's
    /// own machines join the shared set instead of disappearing.
    pub fn merge_remote_profiles_json(local: &str, remote: &str, bootstrap: bool) -> Result<String, DomainError> {
        let local = parse(local)?;
        let mut merged = parse(remote)?;
        for p in merged.iter_mut() {
            redact(p);
            if let Some(l) = local.iter().find(|l| l.id == p.id) {
                p.ssh_password = l.ssh_password.clone();
                p.ssh_key_passphrase = l.ssh_key_passphrase.clone();
                p.runtime_overrides.waypipe_ssh_password = l.runtime_overrides.waypipe_ssh_password.clone();
            }
        }
        if bootstrap {
            for l in local {
                if !merged.iter().any(|m| m.id == l.id) {
                    merged.push(l);
                }
            }
        }
        render(&merged)
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn secrets_and_device_prefs_never_sync() {
            for k in ["SSHPassword", "SSHKeyPassphrase", "wawona.pref.waypipeSSHPassword", "SSHKeyPath",
                      "VulkanDriver", "OpenGLDriver", "TouchInputType", "AutoScale", "CompositorBackend",
                      "wawona.pref.cloudKitSyncEnabled", "wawona.pref.localShellICloudSyncEnabled"] {
                assert!(!is_synced_defaults_key(k), "{k}");
            }
            assert!(is_synced_defaults_key(PROFILES_KEY));
            assert!(is_synced_defaults_key("wawona.machines.pinnedMachineIds"));
        }

        #[test]
        fn home_exclusions() {
            assert!(home_path_excluded(".cache/zsh/x"));
            assert!(home_path_excluded("inbox"));
            assert!(home_path_excluded("a/.DS_Store"));
            assert!(home_path_excluded(".zcompdump-host-5.9"));
            assert!(!home_path_excluded(".zshrc"));
            assert!(!home_path_excluded("notes/todo.txt"));
            assert!(!home_path_excluded(".cacheable"));
        }

        #[test]
        fn fresh_device_yields_then_last_writer_wins() {
            assert!(prefer_remote(10_000, 1, false));
            assert!(prefer_remote(1, 2, true));
            assert!(!prefer_remote(2, 2, true));
            assert!(!prefer_remote(3, 2, true));
        }

        #[test]
        fn profiles_redact_and_merge_keep_local_secrets() {
            let local = r#"[{"id":"a","name":"A","sshPassword":"pw","sshKeyPassphrase":"kp","runtimeOverrides":{"waypipeSSHPassword":"wp"}},{"id":"local","name":"L"}]"#;
            let up = redact_profiles_json(local).unwrap();
            assert!(!up.contains("pw") && !up.contains("kp") && !up.contains("\"wp\""));

            let remote = r#"[{"id":"a","name":"Renamed","sshPassword":"leak"},{"id":"b","name":"B"}]"#;
            let merged: Vec<MachineProfile> =
                serde_json::from_str(&merge_remote_profiles_json(local, remote, false).unwrap()).unwrap();
            assert_eq!(merged.len(), 2);
            assert_eq!(merged[0].name, "Renamed");
            assert_eq!(merged[0].ssh_password, "pw");
            assert_eq!(merged[0].runtime_overrides.waypipe_ssh_password.as_deref(), Some("wp"));
            assert_eq!(merged[1].ssh_password, "");

            let boot: Vec<MachineProfile> =
                serde_json::from_str(&merge_remote_profiles_json(local, remote, true).unwrap()).unwrap();
            assert!(boot.iter().any(|p| p.id == "local"));
        }
    }
}

/// Four-state product gates. Swift `PlatformCapabilities` reads this when
/// rust is linked. visionOS / tvOS / watchOS VM and container stay forbidden.
pub mod capabilities {
    pub fn gate(platform: &str, feature: &str) -> &'static str {
        let p = platform.to_ascii_lowercase();
        let f = feature.to_ascii_lowercase();
        match (p.as_str(), f.as_str()) {
            ("visionos" | "tvos" | "watchos", "vm" | "virtual_machine" | "container") => {
                "forbidden"
            }
            ("macos", "container") => "available",
            (_, "vm" | "virtual_machine" | "container") => "planned",
            (_, "desktop") if matches!(p.as_str(), "macos" | "android") => "planned",
            // Mode B iOS Desktop is a separate compile profile; store iOS stays forbidden.
            ("ios" | "ipados", "desktop") => "forbidden",
            (_, "desktop") => "forbidden",
            (_, "swinging_bridge") if matches!(p.as_str(), "macos" | "android") => "planned",
            (_, "swinging_bridge") => "forbidden",
            // GPU stack: watchOS blocked (no Metal). tvOS planned until bundled.
            ("watchos", "gpu" | "gpu_stack" | "gles" | "vulkan") => "blocked",
            ("tvos", "gpu" | "gpu_stack") => "planned",
            (_, "gpu" | "gpu_stack" | "gles" | "vulkan") => "available",
            // Relay Wasm is mandatory on every product target.
            (_, "wasm" | "wasm_runtime") => "available",
            // SpriteKit Wayland SHM present is watchOS-only.
            ("watchos", "watch_present" | "watch_present_accelerator") => "available",
            (_, "watch_present" | "watch_present_accelerator") => "forbidden",
            // Apple Containerization.framework is macOS-only.
            ("macos", "apple_containerization") => "available",
            (_, "apple_containerization") => "forbidden",
            // CloudKit private database sync (prefs, machines, HOME) is the
            // Apple-account product path. Android and Linux use their own hosts.
            ("android" | "linux", "cloudkit_sync" | "icloud_sync") => "forbidden",
            (_, "cloudkit_sync" | "icloud_sync") => "available",
            // iCloud Drive ubiquity HOME: Apple QA1935, no Drive on tvOS / watchOS.
            ("tvos" | "watchos", "icloud_drive_home") => "blocked",
            ("macos" | "ios" | "ipados" | "visionos", "icloud_drive_home") => "available",
            (_, "icloud_drive_home") => "forbidden",
            _ => "available",
        }
    }
}
