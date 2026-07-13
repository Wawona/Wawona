//! Pure, GTK-free view-model helpers for the Linux UI.
//!
//! All presentation logic that does not require a live widget lives here so it
//! can be unit-tested on any host (the GTK shell in `bin/wawona-linux-ui.rs`
//! only wires these decisions into widgets). This mirrors the view-model layer
//! used by the SwiftUI/Compose front-ends.

use crate::linux::machine_profile::MachineProfile;

/// Adaptive layout mode, chosen from the window width. Mirrors the
/// iOS/Android compact vs. macOS expanded split: below the Adwaita mobile
/// breakpoint we present the single-column, bottom-sheet layout used on
/// phones (Phosh / gnome-mobile / postmarketOS); at or above it we use the
/// multi-pane desktop layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutMode {
    Compact,
    Expanded,
}

/// Adwaita's standard mobile breakpoint is 600px. At/above it we expand.
pub const ADAPTIVE_BREAKPOINT_PX: i32 = 600;

impl LayoutMode {
    pub fn for_width(width: i32) -> LayoutMode {
        if width >= ADAPTIVE_BREAKPOINT_PX {
            LayoutMode::Expanded
        } else {
            LayoutMode::Compact
        }
    }

    pub fn is_compact(self) -> bool {
        matches!(self, LayoutMode::Compact)
    }
}

/// Home-screen scope filter, mirroring `MachineScopeFilter` / `WWNMachineFilter`
/// on Android and macOS.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MachineScope {
    All,
    Local,
    Remote,
}

impl Default for MachineScope {
    fn default() -> Self {
        Self::All
    }
}

impl MachineScope {
    pub fn title(self) -> &'static str {
        match self {
            Self::All => "All Machines",
            Self::Local => "Local",
            Self::Remote => "Remote",
        }
    }

    pub fn all() -> &'static [MachineScope] {
        &[Self::All, Self::Local, Self::Remote]
    }

    /// The sensible machine type to default to when adding a new profile from
    /// this filter (mirrors `WWNMachineFilter.defaultMachineType`).
    pub fn default_machine_type(self) -> crate::linux::machine_profile::MachineType {
        match self {
            Self::Remote => crate::linux::machine_profile::MachineType::SshWaypipe,
            _ => crate::linux::machine_profile::MachineType::Native,
        }
    }

    pub fn matches(self, machine_type: crate::linux::machine_profile::MachineType) -> bool {
        match self {
            Self::All => true,
            Self::Local => machine_type.is_local(),
            Self::Remote => machine_type.is_remote(),
        }
    }
}

/// Scope chip label (mirrors `machineScopeLabel(for:)` on macOS).
pub fn machine_scope_label(machine_type: crate::linux::machine_profile::MachineType) -> &'static str {
    if machine_type.is_local() {
        "Local"
    } else {
        "Remote"
    }
}

/// Display label for a native profile's configured client: the bundled client
/// name, a custom command, or `None` (mirrors `selectedClientName(for:)`).
fn native_client_label(profile: &MachineProfile) -> Option<String> {
    use crate::linux::bundled_clients;
    if let Some(id) = profile
        .runtime_overrides
        .bundled_app_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        return Some(bundled_clients::label_for(id));
    }
    let custom = profile.remote_command.trim();
    if custom.is_empty() {
        None
    } else {
        Some(custom.to_string())
    }
}

/// Card subtitle (mirrors `machineSubtitle(for:)` on macOS).
pub fn machine_subtitle(profile: &MachineProfile) -> String {
    use crate::linux::machine_profile::MachineType;
    match profile.machine_type {
        MachineType::Native => match native_client_label(profile) {
            Some(label) => label,
            None => "No client configured".to_string(),
        },
        MachineType::VirtualMachine => "VM profile (QEMU/KVM)".to_string(),
        MachineType::Container => "Container profile (crun)".to_string(),
        MachineType::SshWaypipe | MachineType::SshTerminal => {
            if profile.ssh_host.is_empty() {
                "SSH endpoint not configured".to_string()
            } else {
                let user = if profile.ssh_user.is_empty() {
                    "user"
                } else {
                    &profile.ssh_user
                };
                format!("{}@{}", user, profile.ssh_host)
            }
        }
    }
}

/// Card summary line (mirrors `machineConfigurationSummary(for:)` on macOS).
pub fn machine_configuration_summary(profile: &MachineProfile) -> String {
    use crate::linux::machine_profile::MachineType;
    match profile.machine_type {
        MachineType::Native => match native_client_label(profile) {
            Some(label) => format!("Runs: {}", label),
            None => "No client configured — edit to select one".to_string(),
        },
        MachineType::SshWaypipe => {
            let command = if profile.remote_command.is_empty() {
                "weston-simple-shm"
            } else {
                &profile.remote_command
            };
            format!("Waypipe command: {}", command)
        }
        MachineType::SshTerminal => {
            let command = if profile.remote_command.is_empty() {
                "terminal default"
            } else {
                &profile.remote_command
            };
            format!("SSH terminal command: {}", command)
        }
        MachineType::VirtualMachine => "Backend: QEMU/KVM".to_string(),
        MachineType::Container => "Backend: crun".to_string(),
    }
}

/// Whether "Start" is enabled for this profile (mirrors `launchSupported(for:)`).
pub fn launch_supported(profile: &MachineProfile) -> bool {
    use crate::linux::machine_profile::MachineType;
    match profile.machine_type {
        MachineType::Native => {
            profile
                .runtime_overrides
                .bundled_app_id
                .as_deref()
                .map(str::trim)
                .is_some_and(|s| !s.is_empty())
                || !profile.remote_command.trim().is_empty()
        }
        _ => true,
    }
}

/// Case-insensitive match of a query against a profile's user-visible text
/// (name, host, user, command, type label).
fn profile_matches_query(profile: &MachineProfile, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }
    let needle = needle.to_lowercase();
    let haystacks = [
        profile.name.to_lowercase(),
        profile.ssh_host.to_lowercase(),
        profile.ssh_user.to_lowercase(),
        profile.remote_command.to_lowercase(),
        profile.machine_type.user_facing_name().to_lowercase(),
        profile.summary().to_lowercase(),
    ];
    haystacks.iter().any(|h| h.contains(&needle))
}

/// Filter + order machines for display: favorites first, then by name, after
/// applying the scope and search query. Returns borrowed references in display
/// order.
pub fn visible_machines<'a>(
    machines: &'a [MachineProfile],
    query: &str,
    scope: MachineScope,
) -> Vec<&'a MachineProfile> {
    let mut out: Vec<&MachineProfile> = machines
        .iter()
        .filter(|m| scope.matches(m.machine_type))
        .filter(|m| profile_matches_query(m, query))
        .collect();
    out.sort_by(|a, b| {
        b.favorite
            .cmp(&a.favorite)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    out
}

/// Placeholder text shown when the filtered list is empty (mirrors the macOS
/// `ContentUnavailableView` in `WWNMachinesGridView`).
pub fn empty_state_text(
    _scope: MachineScope,
    _has_any: bool,
    _has_query: bool,
) -> (&'static str, &'static str) {
    (
        "No Matching Machines",
        "Adjust search/filter settings or add a new machine profile.",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::linux::machine_profile::{MachineProfile, MachineType};

    fn machine(name: &str, favorite: bool, mt: MachineType) -> MachineProfile {
        let mut m = MachineProfile::new(name);
        m.favorite = favorite;
        m.machine_type = mt;
        m
    }

    #[test]
    fn layout_breakpoint_picks_compact_below_600() {
        assert_eq!(LayoutMode::for_width(320), LayoutMode::Compact);
        assert_eq!(LayoutMode::for_width(599), LayoutMode::Compact);
        assert_eq!(LayoutMode::for_width(600), LayoutMode::Expanded);
        assert_eq!(LayoutMode::for_width(1280), LayoutMode::Expanded);
    }

    #[test]
    fn scope_filters_local_remote_and_orders() {
        let machines = vec![
            machine("zeta", false, MachineType::Native),
            machine("alpha", true, MachineType::Native),
            machine("remote", false, MachineType::SshWaypipe),
        ];
        let all = visible_machines(&machines, "", MachineScope::All);
        // Favorite first, then alphabetical.
        assert_eq!(all[0].name, "alpha");
        assert_eq!(all[1].name, "remote");
        assert_eq!(all[2].name, "zeta");

        let local = visible_machines(&machines, "", MachineScope::Local);
        assert_eq!(local.len(), 2);

        let remote = visible_machines(&machines, "", MachineScope::Remote);
        assert_eq!(remote.len(), 1);
        assert_eq!(remote[0].name, "remote");
    }

    #[test]
    fn search_matches_name_and_host() {
        let mut m = machine("Workstation", false, MachineType::SshWaypipe);
        m.ssh_host = "build.example.com".into();
        let machines = vec![m];
        assert_eq!(visible_machines(&machines, "work", MachineScope::All).len(), 1);
        assert_eq!(visible_machines(&machines, "example", MachineScope::All).len(), 1);
        assert_eq!(visible_machines(&machines, "nope", MachineScope::All).len(), 0);
    }

    #[test]
    fn empty_state_matches_macos_content_unavailable_view() {
        assert_eq!(
            empty_state_text(MachineScope::All, false, false).0,
            "No Matching Machines"
        );
        assert_eq!(
            empty_state_text(MachineScope::Remote, true, true).0,
            "No Matching Machines"
        );
    }

    #[test]
    fn card_labels_match_macos_view_model() {
        let mut native = machine("Local", false, MachineType::Native);
        native.remote_command.clear();
        native.runtime_overrides.bundled_app_id = Some("foot".into());
        assert_eq!(machine_subtitle(&native), "Foot Terminal");
        assert_eq!(machine_configuration_summary(&native), "Runs: Foot Terminal");
        assert!(launch_supported(&native));
        assert_eq!(machine_scope_label(native.machine_type), "Local");

        let mut unconfigured = machine("Empty", false, MachineType::Native);
        unconfigured.remote_command.clear();
        assert_eq!(machine_subtitle(&unconfigured), "No client configured");
        assert!(!launch_supported(&unconfigured));

        let mut ssh = machine("Remote", false, MachineType::SshWaypipe);
        ssh.ssh_host = "host".into();
        ssh.ssh_user = "me".into();
        assert_eq!(machine_subtitle(&ssh), "me@host");
        assert_eq!(machine_scope_label(ssh.machine_type), "Remote");
        assert_eq!(
            machine_configuration_summary(&ssh),
            "Waypipe command: weston-simple-shm"
        );
    }

    #[test]
    fn scope_default_machine_type_mirrors_macos_filter() {
        assert_eq!(MachineScope::Remote.default_machine_type(), MachineType::SshWaypipe);
        assert_eq!(MachineScope::All.default_machine_type(), MachineType::Native);
        assert_eq!(MachineScope::Local.default_machine_type(), MachineType::Native);
    }
}
