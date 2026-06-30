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

    pub fn matches(self, machine_type: crate::linux::machine_profile::MachineType) -> bool {
        match self {
            Self::All => true,
            Self::Local => machine_type.is_local(),
            Self::Remote => machine_type.is_remote(),
        }
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

/// Placeholder text shown when a filtered list is empty, matching the empty
/// states used elsewhere.
pub fn empty_state_text(scope: MachineScope, has_any: bool, has_query: bool) -> (&'static str, &'static str) {
    if has_query {
        ("No matches", "No machines match your search.")
    } else if !has_any {
        ("No machines yet", "Tap + to add your first machine.")
    } else {
        match scope {
            MachineScope::Local => ("No local machines", "Add a native, VM, or container profile."),
            MachineScope::Remote => ("No remote machines", "Add an SSH or Waypipe profile."),
            MachineScope::All => ("No machines yet", "Tap + to add your first machine."),
        }
    }
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
    fn empty_state_varies_by_context() {
        assert_eq!(empty_state_text(MachineScope::All, false, false).0, "No machines yet");
        assert_eq!(empty_state_text(MachineScope::Remote, true, false).0, "No remote machines");
        assert_eq!(empty_state_text(MachineScope::All, true, true).0, "No matches");
    }
}
