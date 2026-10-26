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

/// Width below which an `AdwOverlaySplitView` collapses, matching the main
/// Machines sidebar breakpoint.
pub const SPLIT_COLLAPSE_BELOW_PX: i32 = 760;

/// True when a split view should overlay its sidebar instead of taking a column.
/// Inclusive, matching `AdwBreakpoint` `max-width: 760px`.
pub fn split_should_collapse(width: i32) -> bool {
    width > 0 && width <= SPLIT_COLLAPSE_BELOW_PX
}

/// Sidebar width from a pointer X measured in the split view.
///
/// `grab` is `pointer_x - edge` captured at drag start. The edge is the
/// sidebar's trailing edge when the sidebar is packed at the start, and its
/// leading edge when packed at the end. Using the split view's coordinates
/// keeps the width stable while the handle itself moves.
pub fn sidebar_width_from_pointer(
    pointer_x: f64,
    grab: f64,
    total: f64,
    sidebar_at_end: bool,
    min_w: f64,
    max_w: f64,
) -> f64 {
    if !total.is_finite() || total <= 1.0 {
        return if min_w.is_finite() {
            min_w.max(0.0)
        } else {
            0.0
        };
    }
    let edge = pointer_x - grab;
    let raw = if sidebar_at_end { total - edge } else { edge };
    let min_w = if min_w.is_finite() {
        min_w.max(0.0)
    } else {
        0.0
    };
    let max_w = if max_w.is_finite() {
        max_w.max(min_w)
    } else {
        min_w
    };
    let room = (total - 48.0).max(min_w);
    let hi = max_w.min(room).max(min_w);
    raw.clamp(min_w, hi)
}

/// Scope chip label (mirrors `machineScopeLabel(for:)` on macOS).
pub fn machine_scope_label(
    machine_type: crate::linux::machine_profile::MachineType,
) -> &'static str {
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
        MachineType::Wasm => profile
            .runtime_overrides
            .wasm_command
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("wasm hello-wasi-gui")
            .to_string(),
        MachineType::VirtualMachine => "VM profile (Relay KVM)".to_string(),
        MachineType::Container => "Container profile (OCI-in-VM)".to_string(),
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
            None => "No client configured. Edit to select one".to_string(),
        },
        MachineType::Wasm => format!(
            "Runs: {}",
            profile
                .runtime_overrides
                .wasm_command
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or("wasm hello-wasi-gui")
        ),
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
        MachineType::VirtualMachine => "Backend: Relay KVM (cloud-hypervisor)".to_string(),
        MachineType::Container => "Backend: OCI on the same KVM VM".to_string(),
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
/// Boundary characters used for token-boundary bonus in fzf scoring.
const BOUNDARY_CHARS: &[char] = &[' ', '_', '-', '/', '.', ':'];

/// Lightweight fzf-style subsequence matcher.
/// Returns `None` if pattern is not a subsequence of candidate.
/// Bonuses: adjacency (+14), token boundary (+9), position 0 (+10).
/// Earlier first-match gets `max(0, 24 - firstMatch)` bonus.
pub fn fzf_score(pattern: &str, candidate: &str) -> Option<i32> {
    if pattern.is_empty() {
        return Some(0);
    }
    let p: Vec<char> = pattern.to_lowercase().chars().collect();
    let c: Vec<char> = candidate.to_lowercase().chars().collect();
    if p.len() > c.len() {
        return None;
    }
    let mut score: i32 = 0;
    let mut pi = 0usize;
    let mut ci = 0usize;
    let mut last_match: Option<usize> = None;
    let mut first_match: Option<usize> = None;

    while pi < p.len() && ci < c.len() {
        if p[pi] == c[ci] {
            if first_match.is_none() {
                first_match = Some(ci);
            }
            score += 8;
            if let Some(lm) = last_match {
                let gap = (ci - lm) as i32 - 1;
                if gap == 0 {
                    score += 14; // adjacency bonus
                } else {
                    score -= gap.min(10);
                }
            }
            if ci == 0 {
                score += 10; // start-of-string bonus
            } else if BOUNDARY_CHARS.contains(&c[ci - 1]) {
                score += 9; // token boundary bonus
            }
            last_match = Some(ci);
            pi += 1;
        }
        ci += 1;
    }
    if pi != p.len() {
        return None;
    }
    if let Some(fm) = first_match {
        score += (24 - fm as i32).max(0);
    }
    Some(score)
}

/// Returns byte ranges in `text` that match the subsequence characters of `query`.
/// Used to apply Pango markup highlight to the machine name in the card banner.
pub fn highlight_ranges(query: &str, text: &str) -> Vec<std::ops::Range<usize>> {
    if query.trim().is_empty() {
        return Vec::new();
    }
    // Walk the query as space-separated terms and collect matched char positions.
    let needle: Vec<char> = query
        .to_lowercase()
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    if needle.is_empty() {
        return Vec::new();
    }
    let text_chars: Vec<(usize, char)> = text.char_indices().collect();
    let mut ranges = Vec::new();
    let mut ni = 0usize;
    for (byte_off, ch) in &text_chars {
        if ni >= needle.len() {
            break;
        }
        if ch.to_lowercase().next() == Some(needle[ni]) {
            let len = ch.len_utf8();
            ranges.push(*byte_off..*byte_off + len);
            ni += 1;
        }
    }
    ranges
}

/// Searchable corpus for a machine (name + host + user + command + type).
fn profile_searchable(profile: &MachineProfile) -> String {
    [
        profile.name.as_str(),
        profile.ssh_host.as_str(),
        profile.ssh_user.as_str(),
        profile.remote_command.as_str(),
        profile.machine_type.user_facing_name(),
    ]
    .join(" ")
}

/// Filter + order machines for display using fzf-style scoring.
/// Pinned (favorite) machines that match lead; within pinned/unpinned, sort by
/// descending score then by name (matches SwiftUI `visibleProfiles`).
pub fn visible_machines<'a>(
    machines: &'a [MachineProfile],
    query: &str,
) -> Vec<&'a MachineProfile> {
    let q = query.trim();
    if q.is_empty() {
        // No query: favorites first, then alphabetical (original behavior).
        let mut out: Vec<&MachineProfile> = machines.iter().collect();
        out.sort_by(|a, b| {
            b.favorite
                .cmp(&a.favorite)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
        return out;
    }
    // Fuzzy filter + score.
    let terms: Vec<&str> = q.split_whitespace().collect();
    let mut scored: Vec<(&MachineProfile, i32)> = machines
        .iter()
        .filter_map(|m| {
            let haystack = profile_searchable(m);
            let mut total = 0i32;
            for term in &terms {
                match fzf_score(term, &haystack) {
                    Some(s) => total += s,
                    None => return None,
                }
            }
            Some((m, total))
        })
        .collect();
    scored.sort_by(|(a, sa), (b, sb)| {
        b.favorite
            .cmp(&a.favorite)
            .then_with(|| sb.cmp(sa))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    scored.into_iter().map(|(m, _)| m).collect()
}

/// Placeholder text shown when the filtered list is empty (mirrors the macOS
/// `ContentUnavailableView` in `WWNMachinesGridView`).
pub fn empty_state_text(_has_any: bool, _has_query: bool) -> (&'static str, &'static str) {
    (
        "No Matching Machines",
        "Adjust search or add a new machine profile.",
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
    fn split_collapses_below_main_sidebar_breakpoint() {
        assert!(split_should_collapse(320));
        assert!(split_should_collapse(760));
        assert!(!split_should_collapse(761));
        assert!(!split_should_collapse(0));
    }

    #[test]
    fn sidebar_drag_uses_split_coordinates() {
        let w = sidebar_width_from_pointer(300.0, 0.0, 1000.0, false, 160.0, 420.0);
        assert!((w - 300.0).abs() < 0.01);
        let end = sidebar_width_from_pointer(700.0, 0.0, 1000.0, true, 160.0, 420.0);
        assert!((end - 300.0).abs() < 0.01);
        // A pointer left of the minimum must not invert the clamp on a phone width.
        let narrow = sidebar_width_from_pointer(20.0, 0.0, 280.0, false, 160.0, 420.0);
        assert!((narrow - 160.0).abs() < 0.01);
    }

    #[test]
    fn visible_machines_orders_favorites_then_name() {
        let machines = vec![
            machine("zeta", false, MachineType::Native),
            machine("alpha", true, MachineType::Native),
            machine("remote", false, MachineType::SshWaypipe),
        ];
        let all = visible_machines(&machines, "");
        // Favorite first, then alphabetical.
        assert_eq!(all[0].name, "alpha");
        assert_eq!(all[1].name, "remote");
        assert_eq!(all[2].name, "zeta");
        assert_eq!(all.len(), 3);
    }

    #[test]
    fn search_matches_name_and_host() {
        let mut m = machine("Workstation", false, MachineType::SshWaypipe);
        m.ssh_host = "build.example.com".into();
        let machines = vec![m];
        assert_eq!(visible_machines(&machines, "work").len(), 1);
        assert_eq!(visible_machines(&machines, "example").len(), 1);
        assert_eq!(visible_machines(&machines, "nomatch").len(), 0);
    }

    #[test]
    fn empty_state_matches_macos_content_unavailable_view() {
        assert_eq!(empty_state_text(false, false).0, "No Matching Machines");
        assert_eq!(empty_state_text(true, true).0, "No Matching Machines");
    }

    #[test]
    fn card_labels_match_macos_view_model() {
        let mut native = machine("Local", false, MachineType::Native);
        native.remote_command.clear();
        native.runtime_overrides.bundled_app_id = Some("wawona-shell".into());
        assert_eq!(machine_subtitle(&native), "Native Shell");
        assert_eq!(machine_configuration_summary(&native), "Runs: Native Shell");
        assert!(launch_supported(&native));
        assert_eq!(machine_scope_label(native.machine_type), "Local");

        // Optional-software id still resolves via client_catalog (not keep-set).
        let mut optional = machine("Foot", false, MachineType::Native);
        optional.remote_command.clear();
        optional.runtime_overrides.bundled_app_id = Some("foot".into());
        assert_eq!(machine_subtitle(&optional), "Foot Terminal");

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
}
