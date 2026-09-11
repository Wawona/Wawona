//! Product domain: machine profiles, validation, store.
//!
//! UniFFI + this module own the schema. `WWNCore*` stays the compositor ABI.
//!
//! `settings_catalog` lives in this file so a dirty git flake (no commit)
//! still ships the module. Nix `git+file` copies tracked files only.

pub mod c_api;
pub mod error;
pub mod machine_profile;
pub mod profile_store;
pub mod uniffi_api;
pub mod validation;

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
        Advanced,
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
                Self::Advanced => "Advanced",
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
                Self::Advanced => "advanced",
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
                Display, Input, Graphics, Connection, Environment, LocalShell, Machines,
                ICloudSync, Advanced, Desktop, Waypipe, Ssh, About, Dependencies,
            ],
            SettingsHost::Ios => vec![
                Display, Input, Graphics, Connection, Environment, LocalShell, Machines,
                ICloudSync, AppleWatch, Advanced, Waypipe, Ssh, About, Dependencies,
            ],
            SettingsHost::VisionOs => vec![
                Display, Input, Graphics, Connection, Environment, LocalShell, Machines,
                ICloudSync, Advanced, Waypipe, Ssh, About, Dependencies,
            ],
            SettingsHost::Android | SettingsHost::Linux => vec![
                Display, Input, Graphics, Connection, Environment, LocalShell, Machines,
                Advanced, Waypipe, Ssh, About, Dependencies,
            ],
            SettingsHost::TvOs => vec![
                Display, Input, Graphics, Connection, Environment, Machines, Advanced,
                Waypipe, Ssh, About, Dependencies,
            ],
            SettingsHost::WatchOs => vec![
                Display, Input, Graphics, Connection, Environment, Machines, ICloudSync,
                Waypipe, Ssh, Advanced, About, Dependencies,
            ],
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn macos_has_desktop_ios_does_not() {
            let mac = visible_sections(SettingsHost::MacOs);
            let ios = visible_sections(SettingsHost::Ios);
            assert!(mac.contains(&SettingsSectionId::Desktop));
            assert!(!ios.contains(&SettingsSectionId::Desktop));
            assert!(ios.contains(&SettingsSectionId::AppleWatch));
            assert!(!mac.contains(&SettingsSectionId::AppleWatch));
        }

        #[test]
        fn tvos_has_no_icloud_or_local_shell() {
            let tv = visible_sections(SettingsHost::TvOs);
            assert!(!tv.contains(&SettingsSectionId::ICloudSync));
            assert!(!tv.contains(&SettingsSectionId::LocalShell));
            assert!(!tv.contains(&SettingsSectionId::Desktop));
        }

        #[test]
        fn android_and_linux_share_store_catalog() {
            assert_eq!(
                visible_sections(SettingsHost::Android),
                visible_sections(SettingsHost::Linux)
            );
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
            (_, "desktop") => "forbidden",
            (_, "swinging_bridge") if matches!(p.as_str(), "macos" | "android") => "planned",
            (_, "swinging_bridge") => "forbidden",
            _ => "available",
        }
    }
}
