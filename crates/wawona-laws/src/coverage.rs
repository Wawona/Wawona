//! Coverage of Exact actions and Wayland Explorer protocols.
//!
//! Every `app.contract` action names one law. Every `PROTOCOL_CATALOG`
//! interface has a proof-obligation row. Every erroneous-check helper names
//! a Bend law, or `kani` when the check needs negative integers.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

/// `(action, bend law or "host")`. `host` is a side effect with no state law.
const UI_ACTIONS: &[(&str, &str)] = &[
    ("aimMachine", "store_is"),
    ("applyPhase", "start_is_running"),
    ("askCloseAllTabs", "store_is"),
    ("askDelete", "store_is"),
    ("assignTag", "flip_back"),
    ("back", "back_idempotent"),
    ("cancelCreateTag", "back_idempotent"),
    ("clearMachineQuery", "store_is"),
    ("clearMachinesNotice", "store_is"),
    ("clearPendingDelete", "store_is"),
    ("clearTabQuery", "store_is"),
    ("confirmCloseAllTabs", "ends_running"),
    ("confirmDelete", "close_drops_one"),
    ("follow", "host"),
    ("openAboutLink", "host"),
    ("openAdd", "open_machine_back"),
    ("openCreateTag", "open_machine_back"),
    ("openDep", "host"),
    ("openMachine", "open_machine_back"),
    ("openSection", "section_hidden"),
    ("openSessionTab", "open_machine_back"),
    ("openSessionWindow", "open_machine_back"),
    ("openSettings", "select_settings_then_back"),
    ("openTabOverview", "open_machine_back"),
    ("saveAdd", "save_rejects_blank"),
    ("setSessionDecoration", "store_is"),
    ("saveCreateTag", "save_rejects_blank"),
    ("saveDetail", "save_rejects_blank"),
    ("searchMachines", "store_is"),
    ("searchTabs", "store_is"),
    ("setColorOperations", "store_is"),
    ("setCompositorBackend", "store_is"),
    ("setDesktopReplacement", "store_is"),
    ("setDraftCommand", "store_is"),
    ("setDraftKind", "store_is"),
    ("setDraftName", "store_is"),
    ("setDraftSession", "remote_needs_waypipe"),
    ("setDraftTagColor", "store_is"),
    ("setDraftTagName", "store_is"),
    ("setDraftUseRemote", "store_is"),
    ("setEnvCategory", "store_is"),
    ("setFilter", "store_is"),
    ("setForceSsd", "store_is"),
    ("setHostPlatform", "store_is"),
    ("setICloudDriveHome", "store_is"),
    ("setICloudSync", "store_is"),
    ("setLogLevel", "store_is"),
    ("setMultipleClients", "store_is"),
    ("setNestedCompositors", "store_is"),
    ("setOpenglDriver", "store_is"),
    ("setPersistentToolbar", "store_is"),
    ("setProductMode", "store_is"),
    ("setResizeDisplayForVirtualKeyboard", "store_is"),
    ("setRespectSafeArea", "store_is"),
    ("setSessionThumbnails", "store_is"),
    ("setShowToolbarWithHardwareKeyboard", "store_is"),
    ("setShowVirtualCursor", "store_is"),
    ("setSortKey", "flip_back"),
    ("setSshAuthMethod", "store_is"),
    ("setSshEnabled", "store_is"),
    ("setSshHost", "store_is"),
    ("setSshKeyPassphrase", "store_is"),
    ("setSshKeyPath", "store_is"),
    ("setSshKeyType", "store_is"),
    ("setSshPassword", "store_is"),
    ("setSshPort", "port_keeps_22"),
    ("setSshStrictHostKey", "store_is"),
    ("setSshUser", "store_is"),
    ("setSwapCmdWithAlt", "store_is"),
    ("setSwipeBackToClose", "store_is"),
    ("setShakeToClose", "store_is"),
    ("setToolbarArrowJoystickMode", "store_is"),
    ("setToolbarChromeStyle", "store_is"),
    ("setToolbarThemeAware", "store_is"),
    ("setTouchInputType", "store_is"),
    ("setTouchPointerEmulation", "store_is"),
    ("setUniversalClipboard", "store_is"),
    ("setVulkanDriver", "store_is"),
    ("setWaypipeCompress", "store_is"),
    ("setWaypipeCompressLevel", "store_is"),
    ("setWaypipeDebug", "store_is"),
    ("setWaypipeDisplay", "store_is"),
    ("setWaypipeLoginShell", "store_is"),
    ("setWaypipeNoGpu", "store_is"),
    ("setWaypipeOneshot", "store_is"),
    ("setWaypipeRemoteCommand", "store_is"),
    ("setWaypipeThreads", "store_is"),
    ("setWaypipeTitlePrefix", "store_is"),
    ("setWaypipeUnlinkSocket", "store_is"),
    ("setWaypipeUseSsh", "store_is"),
    ("setWaypipeVideo", "store_is"),
    ("setWaypipeVideoBpf", "store_is"),
    ("setWaypipeVideoDecoding", "store_is"),
    ("setWaypipeVideoEncoding", "store_is"),
    ("startMachine", "start_is_running"),
    ("stopMachine", "ends_running"),
    ("syncICloudNow", "host"),
    ("togglePin", "flip_back"),
    ("toggleSortAscending", "flip_back"),
];

/// Helper in `protocol_proofs.rs` to the Bend law that states it.
/// `kani` means the check uses negative integers, which Bend's Nat does not model.
const PROTOCOL_HELPERS: &[(&str, &str)] = &[
    ("alpha_modifier_factor_is_unit_interval", "factor_zero"),
    ("color_representation_alpha_mode_supported", "alpha_zero"),
    ("color_representation_rejects_duplicate_surface", "rejects_second_is_flag"),
    ("commit_timing_hold_required", "hold_now"),
    ("content_type_hint_is_known_or_none", "content_known"),
    ("cursor_shape_value_is_non_zero", "cursor_pos"),
    ("drm_lease_request_rejects_empty", "lease_zero"),
    ("drm_lease_request_rejects_without_connectors", "lease_zero"),
    ("export_dmabuf_should_cancel_without_capability", "absent_yes"),
    ("fifo_barrier_blocks_next_commit", "fifo_is_armed_unpresented"),
    ("fractional_scale_units_at_least_120", "scale_at_least_120"),
    ("gamma_control_rejects_second_active", "rejects_second_is_flag"),
    ("gamma_ramp_byte_len_matches", "gamma_zero"),
    ("hyprland_shortcut_rejects_duplicate", "rejects_second_is_flag"),
    ("idle_inhibit_map_remove_clears", "idle_drops"),
    ("image_copy_capture_rejects_duplicate_frame", "rejects_second_is_flag"),
    ("output_power_mode_is_on_or_off", "bit_zero"),
    ("pointer_constraint_oneshot_stays_dead", "oneshot_is_not_both"),
    ("shortcuts_inhibit_surface_toggle", "absent_no"),
    ("single_pixel_buffer_is_one_by_one", "pixel_one"),
    ("tearing_hint_is_vsync_or_async", "bit_zero"),
    ("viewport_commit_rejects_fractional_without_dest", "frac_misaligned"),
    ("viewport_commit_rejects_out_of_buffer_i32", "kani"),
    ("viewport_destination_request_is_valid", "dest_unset"),
    ("viewport_source_request_is_valid", "size_pos"),
    ("wl_shell_role_conflict", "rejects_second_is_flag"),
    ("wlr_input_inhibit_rejects_second_inhibitor", "rejects_second_is_flag"),
    ("xdg_v6_positioner_anchor_rect_non_negative", "kani"),
    ("xdg_v6_positioner_size_must_be_positive", "size_pos"),
];

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn read(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

fn contract_actions(text: &str) -> BTreeSet<String> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            let rest = line.strip_prefix("action ")?;
            let name = rest.split(['(', ' ', '\t']).next()?.trim();
            if name.is_empty() { None } else { Some(name.to_string()) }
        })
        .collect()
}

fn first_quote(line: &str) -> Option<&str> {
    let rest = line.split('"').nth(1)?;
    if rest.is_empty() { None } else { Some(rest) }
}

fn catalog_interfaces(text: &str) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    let mut expect = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with("cat!(") {
            if let Some(name) = first_quote(line) {
                names.insert(name.to_string());
            } else {
                expect = true;
            }
            continue;
        }
        if expect {
            if let Some(name) = first_quote(line) {
                names.insert(name.to_string());
            }
            expect = false;
        }
    }
    names
}

fn proof_interfaces(text: &str) -> BTreeSet<String> {
    text.lines()
        .filter_map(|line| {
            let rest = line.trim().strip_prefix("interface:")?;
            let rest = rest.trim().trim_start_matches('"');
            let name = rest.split('"').next()?.trim();
            if name.is_empty() { None } else { Some(name.to_string()) }
        })
        .collect()
}

fn proof_helpers(text: &str) -> BTreeSet<String> {
    let mut names = BTreeSet::new();
    let mut inside = false;
    for line in text.lines() {
        if line.contains("Helpers(&[") {
            inside = true;
        }
        if inside {
            for part in line.split('"').skip(1).step_by(2) {
                if !part.is_empty()
                    && part.chars().all(|c| c == '_' || c.is_ascii_lowercase() || c.is_ascii_digit())
                {
                    names.insert(part.to_string());
                }
            }
        }
        if inside && line.contains("])") {
            inside = false;
        }
    }
    names
}

fn law_names(text: &str) -> BTreeSet<String> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            let rest = line.strip_prefix("law ")?;
            Some(rest.trim_end_matches(':').to_string())
        })
        .collect()
}

fn json_string_list(text: &str, key: &str) -> Vec<String> {
    let aliases = text.find("\"aliases\"").unwrap_or_else(|| panic!("aliases"));
    let key_at = text[aliases..]
        .find(&format!("\"{key}\""))
        .unwrap_or_else(|| panic!("missing {key}"))
        + aliases;
    let rest = &text[key_at..];
    let start = rest.find('[').unwrap_or_else(|| panic!("{key} list"));
    let end = rest[start..].find(']').unwrap_or_else(|| panic!("{key} end"));
    rest[start + 1..start + end]
        .split('"')
        .skip(1)
        .step_by(2)
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_contract_action_names_a_law() {
        let contract = read(&repo_root().join("../exact/apps/wawona/app.contract"));
        let laws = law_names(&read(&repo_root().join("verification/bend/LAWS.bend")));
        let found = contract_actions(&contract);
        let listed: BTreeSet<_> = UI_ACTIONS.iter().map(|(name, _)| (*name).to_string()).collect();
        let missing: Vec<_> = found.difference(&listed).cloned().collect();
        let extra: Vec<_> = listed.difference(&found).cloned().collect();
        assert!(missing.is_empty(), "contract actions with no law row: {missing:?}");
        assert!(extra.is_empty(), "law rows with no contract action: {extra:?}");
        for (action, law) in UI_ACTIONS {
            if *law != "host" {
                assert!(laws.contains(*law), "{action} names missing law {law}");
            }
        }
    }

    #[test]
    fn every_explorer_protocol_has_an_obligation_and_a_law() {
        let catalog = read(&repo_root().join("src/core/wayland/catalog.rs"));
        let proofs = read(&repo_root().join("src/core/wayland/protocol_proofs.rs"));
        let laws = law_names(&read(&repo_root().join("verification/bend/LAWS.bend")));
        let catalog_ifaces = catalog_interfaces(&catalog);
        let proof_ifaces = proof_interfaces(&proofs);
        let missing: Vec<_> = catalog_ifaces.difference(&proof_ifaces).cloned().collect();
        let extra: Vec<_> = proof_ifaces.difference(&catalog_ifaces).cloned().collect();
        assert!(missing.is_empty(), "catalog protocols with no obligation: {missing:?}");
        assert!(extra.is_empty(), "obligations missing from the catalog: {extra:?}");
        assert!(catalog_ifaces.len() > 100, "explorer catalog collapsed");
        let none_rows = proofs.lines().filter(|line| line.contains("checks: ErroneousChecks::None")).count();
        let helper_rows = proofs.lines().filter(|line| line.contains("checks: ErroneousChecks::Helpers")).count();
        assert_eq!(
            none_rows + helper_rows,
            proof_ifaces.len(),
            "every protocol is a helper law or no-client-error"
        );

        let helpers = proof_helpers(&proofs);
        let listed: BTreeSet<_> = PROTOCOL_HELPERS.iter().map(|(name, _)| (*name).to_string()).collect();
        let missing_h: Vec<_> = helpers.difference(&listed).cloned().collect();
        let extra_h: Vec<_> = listed.difference(&helpers).cloned().collect();
        assert!(missing_h.is_empty(), "helpers with no law: {missing_h:?}");
        assert!(extra_h.is_empty(), "law map names a helper that is gone: {extra_h:?}");
        for (helper, law) in PROTOCOL_HELPERS {
            if *law != "kani" {
                assert!(laws.contains(*law), "{helper} names missing law {law}");
            }
        }
    }

    #[test]
    fn all_targets_share_the_contract_laws() {
        let platforms = read(&repo_root().join("platforms.json"));
        let targets = json_string_list(&platforms, "ALL_TARGETS");
        assert!(
            targets.len() >= 12,
            "ALL_TARGETS lost a host: {targets:?}"
        );
        let exact = json_string_list(&platforms, "EXACT_HOSTS");
        for id in &exact {
            assert!(
                targets.contains(id),
                "Exact host {id} is outside ALL_TARGETS"
            );
        }
        for id in &targets {
            let marker = format!("\"id\": \"{id}\"");
            let at = platforms.find(&marker).unwrap_or_else(|| panic!("no target {id}"));
            let window = &platforms[at..platforms.len().min(at + 500)];
            assert!(
                window.contains("\"exact_ui\": \"available\"") || window.contains("\"exact_ui\": \"planned\""),
                "{id} has no exact_ui row"
            );
        }
    }
}
