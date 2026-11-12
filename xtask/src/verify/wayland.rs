//! Checks over docs/compliance/wayland-protocol-manifest.toml: its shape, its
//! agreement with the Smithay runtime, and who owns each interface.

use super::{Check, Opts};
use crate::util::*;
use anyhow::{Context, Result};
use regex::Regex;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

const MANIFEST: &str = "docs/compliance/wayland-protocol-manifest.toml";
const COMPOSITOR: &str = "src/core/compositor.rs";
const WAYLAND_MOD: &str = "src/core/wayland/mod.rs";
const PROFILES: [&str; 4] = ["store-safe", "store-safe-remote", "desktop-host", "full-dev"];
const COMPILE: [&str; 3] = ["all-targets", "desktop-feature-gated", "linux-desktop-only"];

#[derive(Deserialize)]
struct Manifest {
    #[serde(default)]
    profile: Vec<toml::Table>,
    #[serde(default)]
    protocol: Vec<toml::Table>,
}

struct Proto {
    t: toml::Table,
}

impl Proto {
    fn s(&self, k: &str) -> &str {
        self.t.get(k).and_then(|v| v.as_str()).unwrap_or("")
    }
    fn iface(&self) -> &str {
        self.s("interface")
    }
    fn profiles(&self) -> BTreeSet<&str> {
        self.t.get("profiles").and_then(|v| v.as_array()).into_iter().flatten().filter_map(|v| v.as_str()).collect()
    }
}

fn manifest(c: &Check) -> Result<(Vec<String>, Vec<Proto>)> {
    let m: Manifest = toml::from_str(&read(c.path(MANIFEST))?).context(MANIFEST)?;
    let profiles = m.profile.iter().filter_map(|p| p.get("name")?.as_str().map(String::from)).collect();
    Ok((profiles, m.protocol.into_iter().map(|t| Proto { t }).collect()))
}

fn write_json(o: &Opts, name: &str, v: &impl serde::Serialize) -> Result<()> {
    if let Some(d) = &o.json_out {
        write(d.join(name), serde_json::to_string_pretty(v)?)?;
    }
    Ok(())
}

const REQUIRED_INTERFACES: &[&str] = &[
    "wl_compositor",
    "wl_subcompositor",
    "wl_shm",
    "wl_output",
    "wl_seat",
    "wl_data_device_manager",
    "wl_fixes",
    "xdg_wm_base",
    "zxdg_toplevel_decoration_v1",
    "xdg_activation_v1",
    "zxdg_exporter_v2",
    "zxdg_importer_v2",
    "xdg_system_bell_v1",
    "xdg_toplevel_icon_v1",
    "xdg_toplevel_tag_manager_v1",
    "zwlr_screencopy_manager_v1",
    "zwlr_export_dmabuf_manager_v1",
    "zwlr_virtual_pointer_manager_v1",
    "zwp_virtual_keyboard_manager_v1",
    "zwlr_layer_shell_v1",
    "ext_foreign_toplevel_list_v1",
    "zwp_pointer_constraints_v1",
    "zwp_pointer_gestures_v1",
    "zwp_relative_pointer_manager_v1",
    "wp_cursor_shape_manager_v1",
    "zwp_text_input_manager_v3",
    "zwp_input_method_manager_v2",
    "zwp_primary_selection_device_manager_v1",
    "ext_data_control_manager_v1",
    "zwlr_data_control_manager_v1",
    "zwp_linux_dmabuf_v1",
    "wp_presentation",
    "wp_commit_timing_manager_v1",
    "wp_fifo_manager_v1",
    "wp_fractional_scale_manager_v1",
    "wp_viewporter",
    "wp_single_pixel_buffer_manager_v1",
    "wp_alpha_modifier_v1",
    "wp_content_type_manager_v1",
    "ext_background_effect_manager_v1",
    "zwp_idle_inhibit_manager_v1",
    "zwp_keyboard_shortcuts_inhibit_manager_v1",
    "ext_idle_notifier_v1",
    "wp_security_context_manager_v1",
    "ext_session_lock_manager_v1",
    "ext_output_image_capture_source_manager_v1",
    "ext_image_copy_capture_manager_v1",
    "wp_drm_lease_device_v1",
    "wp_linux_drm_syncobj_manager_v1",
    "xwayland_shell_v1",
    "zwp_xwayland_keyboard_grab_manager_v1",
];

pub fn protocol_manifest(c: &mut Check, _: &Opts) -> Result<String> {
    let (profiles, protos) = manifest(c)?;
    for p in PROFILES {
        if !profiles.iter().any(|q| q == p) {
            c.fail(format!("missing required profile {p}"));
        }
    }
    for i in REQUIRED_INTERFACES {
        if !protos.iter().any(|p| p.iface() == *i) {
            c.fail(format!("missing required interface {i}"));
        }
    }
    let exposure = ["store-safe-core", "store-safe-conditional", "desktop-only", "internal-only"];
    for p in &protos {
        let name = p.iface();
        let missing: Vec<&str> =
            ["smithay_module", "exposure", "profiles", "source_module", "compile_expectation", "equivalent", "notes"]
                .into_iter()
                .filter(|k| !p.t.contains_key(*k))
                .collect();
        if !missing.is_empty() {
            c.fail(format!("{name}: missing keys {missing:?}"));
            continue;
        }
        if !exposure.contains(&p.s("exposure")) {
            c.fail(format!("{name}: invalid exposure {:?}", p.s("exposure")));
        }
        if !COMPILE.contains(&p.s("compile_expectation")) {
            c.fail(format!("{name}: invalid compile_expectation {:?}", p.s("compile_expectation")));
        }
        if !["smithay", "no-equivalent"].contains(&p.s("equivalent")) {
            c.fail(format!("{name}: invalid equivalent {:?}", p.s("equivalent")));
        }
        if p.s("equivalent") == "no-equivalent" && p.s("smithay_module") != "none" {
            c.fail(format!("{name}: no-equivalent protocols must use smithay_module = \"none\""));
        }
    }
    Ok(format!("{} protocols", protos.len()))
}

pub fn smithay_coverage(c: &mut Check, _: &Opts) -> Result<String> {
    let (_, protos) = manifest(c)?;
    for p in &protos {
        let (name, src) = (p.iface(), p.s("source_module"));
        let Ok(text) = std::fs::read_to_string(c.path(src)) else {
            c.fail(format!("{name}: source_module does not exist: {src}"));
            continue;
        };
        if !COMPILE.contains(&p.s("compile_expectation")) {
            c.fail(format!("{name}: invalid compile_expectation {:?}", p.s("compile_expectation")));
        }
        match p.s("equivalent") {
            "no-equivalent" if p.s("smithay_module") != "none" => {
                c.fail(format!("{name}: no-equivalent must use smithay_module = \"none\""))
            }
            "no-equivalent" if !text.contains("allow_") && !text.contains("protocol_profile") => {
                c.fail(format!("{name}: no-equivalent protocol must be runtime-gated in {src}"))
            }
            "smithay" if p.s("smithay_module") == "none" => {
                c.fail(format!("{name}: a smithay equivalent cannot use smithay_module = \"none\""))
            }
            _ => {}
        }
    }
    let survivors: BTreeSet<String> = Regex::new(r"`([^`]+)`")?
        .captures_iter(&c.text("docs/compliance/non-smithay-survivors.md").unwrap_or_default())
        .map(|m| m[1].to_string())
        .collect();
    let wmod = c.text(WAYLAND_MOD).unwrap_or_default();
    let runtime: BTreeSet<String> =
        Regex::new(r#"interface:\s*"([^"]+)""#)?.captures_iter(&wmod).map(|m| m[1].to_string()).collect();
    for p in &protos {
        match p.s("equivalent") {
            "no-equivalent" if !survivors.contains(p.iface()) => {
                c.fail(format!("{}: no-equivalent interface missing from non-smithay-survivors.md", p.iface()))
            }
            "smithay" if !runtime.contains(p.iface()) => c.fail(format!(
                "{}: smithay-equivalent interface missing from the smithay runtime binding set",
                p.iface()
            )),
            _ => {}
        }
    }
    let comp = c.text(COMPOSITOR).unwrap_or_default();
    for call in ["smithay_runtime::register_core_shell", "smithay_runtime::register_extensions_wlr"] {
        if !comp.contains(call) {
            c.fail(format!("{COMPOSITOR}: missing {call}"));
        }
    }
    if comp.contains("smithay_scaffold") || wmod.contains("smithay_scaffold") {
        c.fail("legacy smithay_scaffold references remain in runtime wiring");
    }
    c.forbid(
        "src/core/wayland/wayland/display.rs",
        &["create_global::<CompositorState"],
        "globals register centrally through smithay_runtime",
    );
    Ok(format!("{} protocols", protos.len()))
}

pub fn no_equivalent_closure(c: &mut Check, o: &Opts) -> Result<String> {
    const TRUE_NO_PATH: [&str; 6] = [
        "no direct smithay",
        "no active smithay",
        "no smithay",
        "wawona-specific extension",
        "kde survivor protocol",
        "legacy fullscreen shell",
    ];
    const BLOCKED: &str = "still registered through wawona custom create_global path";
    let (_, protos) = manifest(c)?;
    let mut rows: Vec<BTreeMap<&str, String>> = Vec::new();
    for p in protos.iter().filter(|p| p.s("equivalent") == "no-equivalent") {
        let note = p.s("notes").trim().to_string();
        let lower = note.to_lowercase();
        let disposition = if lower.contains(BLOCKED) {
            "architecture-blocked"
        } else if TRUE_NO_PATH.iter().any(|m| lower.contains(m)) {
            "true-no-path"
        } else {
            c.fail(format!("{}: no closed disposition marker in notes", p.iface()));
            "unclassified"
        };
        rows.push(BTreeMap::from([
            ("interface", p.iface().to_string()),
            ("source_module", p.s("source_module").to_string()),
            ("notes", note),
            ("disposition", disposition.to_string()),
        ]));
    }
    rows.sort_by(|a, b| a["interface"].cmp(&b["interface"]));
    if rows.len() != 57 {
        c.fail(format!("no-equivalent count mismatch: expected 57, found {}", rows.len()));
    }
    write_json(o, "wayland-no-equivalent-closure.json", &rows)?;
    let n = |d: &str| rows.iter().filter(|r| r["disposition"] == d).count();
    Ok(format!(
        "total={} true_no_path={} architecture_blocked={}",
        rows.len(),
        n("true-no-path"),
        n("architecture-blocked")
    ))
}

/// Profiles stay consistent, and the flake outputs the profiles build
/// evaluate (or build, with --build) on this host.
pub fn profile_smoke(c: &mut Check, o: &Opts) -> Result<String> {
    let (_, protos) = manifest(c)?;
    let mut counts: BTreeMap<&str, usize> = PROFILES.iter().map(|p| (*p, 0)).collect();
    for p in &protos {
        let profiles = p.profiles();
        for q in &profiles {
            match counts.get_mut(q) {
                Some(n) => *n += 1,
                None => c.fail(format!("{}: unknown profile {q}", p.iface())),
            }
        }
        if p.s("exposure") == "desktop-only" && profiles.iter().any(|q| !["desktop-host", "full-dev"].contains(q)) {
            c.fail(format!("{}: desktop-only exposure leaks into a non-desktop profile", p.iface()));
        }
        if p.s("equivalent") == "no-equivalent"
            && p.s("exposure") != "store-safe-core"
            && (profiles.contains("store-safe") || profiles.contains("store-safe-remote"))
        {
            c.fail(format!("{}: a no-equivalent protocol must not be in the store-safe profiles", p.iface()));
        }
    }
    for (p, n) in &counts {
        if *n == 0 {
            c.fail(format!("the manifest has no protocol rows for profile {p}"));
        }
    }
    let system = output(cmd("nix").args(["eval", "--raw", "--impure", "--expr", "builtins.currentSystem"]))?;
    let outputs: &[&str] = if system.ends_with("-darwin") {
        &[
            "weston-ios",
            "weston-compositor-ios",
            "weston-compositor-ios-drm",
            "weston-compositor-ios-drm-sim",
            "weston-ios-gl",
            "weston-ios-gl-sim",
            "angle-ios",
            "angle-ios-sim",
            "iland-ios",
            "iland-ios-sim",
            "iland-gl-clients-ios",
            "iland-gl-clients-ios-device",
            "iland-gl-clients",
        ]
    } else {
        &["weston-android", "weston-compositor-android", "angle-android"]
    };
    for name in outputs {
        let attr = format!("{}#packages.{system}.{name}", c.root.display());
        let ok = if o.build {
            cmd("nix").args(["build", &attr, "--no-link"]).status()?.success()
        } else {
            try_output(cmd("nix").args(["eval", &attr, "--apply", "x: x.name or true"])).is_some()
        };
        if !ok {
            c.fail(format!("flake output {name} does not {} on {system}", if o.build { "build" } else { "evaluate" }));
        }
    }
    let counts: Vec<String> = counts.iter().map(|(p, n)| format!("{p}={n}")).collect();
    Ok(format!("{}; {} flake outputs on {system}", counts.join(", "), outputs.len()))
}

/// Classifies each manifest interface by who registers and dispatches it.
/// With --strict, a Smithay-equivalent interface still owned (or also
/// registered) by custom code fails.
pub fn runtime_ownership(c: &mut Check, o: &Opts) -> Result<String> {
    let (_, protos) = manifest(c)?;
    let comp = c.text(COMPOSITOR).unwrap_or_default();
    if !comp.contains("smithay_runtime::register_core_shell")
        || !comp.contains("smithay_runtime::register_extensions_wlr")
    {
        c.fail(format!("missing smithay_runtime core wiring in {COMPOSITOR}"));
    }
    let wcode: String = c
        .text(WAYLAND_MOD)
        .unwrap_or_default()
        .lines()
        .map(|l| l.split("//").next().unwrap())
        .collect::<Vec<_>>()
        .join("\n");
    let mut rows = Vec::new();
    let (mut strict_fail, mut unknown_mods) = (Vec::new(), BTreeSet::new());
    for p in &protos {
        let files = scoped_files(c, p.s("source_module"));
        if files.is_empty() {
            unknown_mods.insert(p.s("source_module").to_string());
            continue;
        }
        let hints = type_hints(p.iface());
        let (mut creates, mut dispatches) = (BTreeSet::new(), BTreeSet::new());
        for f in &files {
            let text = read(f)?;
            for h in &hints {
                let h = regex::escape(h);
                if Regex::new(&format!(r"create_global::<\s*CompositorState\s*,[^>\n]*{h}"))?.is_match(&text) {
                    creates.insert(c.rel(f));
                }
                let forwards =
                    Regex::new(&format!(r"<\s*[\w:]*State\s+as\s+(GlobalDispatch|Dispatch)<\s*[\w:]*\b{h}\b"))?;
                if impl_blocks(&text, &h)?.iter().any(|b| !forwards.is_match(b)) {
                    dispatches.insert(c.rel(f));
                }
            }
        }
        let delegated = marker(p.iface()).is_some_and(|m| wcode.contains(m))
            || hints.iter().any(|h| {
                Regex::new(&format!(
                    r"(?s)delegate_(?:global_)?dispatch!\([^;]*?\b{}\b[^;]*?=>\s*[\w:]*smithay[\w:]*State\)",
                    regex::escape(h)
                ))
                .unwrap()
                .is_match(&wcode)
            });
        let dual = !creates.is_empty() || !dispatches.is_empty();
        let owner = if ["wl_compositor", "wl_subcompositor", "xdg_wm_base"].contains(&p.iface()) {
            "smithay_runtime_core"
        } else if delegated {
            "smithay_runtime"
        } else if p.s("equivalent") == "no-equivalent" {
            "custom_survivor"
        } else if dual {
            "custom_runtime"
        } else {
            "unknown"
        };
        if o.strict && p.s("equivalent") == "smithay" && (matches!(owner, "custom_runtime" | "unknown") || dual) {
            strict_fail.push(p.iface().to_string());
        }
        rows.push(serde_json::json!({
            "interface": p.iface(), "equivalent": p.s("equivalent"), "source_module": p.s("source_module"),
            "owner": owner, "dual_registration": dual,
            "custom_create_global_files": creates, "custom_dispatch_files": dispatches,
        }));
    }
    write_json(o, "wayland-runtime-ownership.json", &rows)?;
    if !unknown_mods.is_empty() {
        c.fail(format!("unknown source_module paths in the manifest: {unknown_mods:?}"));
    }
    let count = |owner: &str| rows.iter().filter(|r| r["equivalent"] == "smithay" && r["owner"] == owner).count();
    if !strict_fail.is_empty() {
        strict_fail.sort();
        c.fail(format!(
            "smithay-equivalent interfaces not owned by the smithay_runtime bindings: {}",
            strict_fail.join(", ")
        ));
    }
    Ok(format!(
        "total={} smithay_custom={} smithay_unknown={} strict={}",
        rows.len(),
        count("custom_runtime"),
        count("unknown"),
        o.strict
    ))
}

fn type_hints(iface: &str) -> Vec<String> {
    match iface {
        "zxdg_toplevel_decoration_v1" => vec!["ZxdgDecorationManagerV1".into(), "ZxdgToplevelDecorationV1".into()],
        "xdg_toplevel_icon_v1" => vec!["XdgToplevelIconManagerV1".into(), "XdgToplevelIconV1".into()],
        _ => vec![iface
            .split('_')
            .map(|p| {
                let mut ch = p.chars();
                ch.next()
                    .map(|f| f.to_uppercase().chain(ch.flat_map(|c| c.to_lowercase())).collect::<String>())
                    .unwrap_or_default()
            })
            .collect()],
    }
}

fn marker(iface: &str) -> Option<&'static str> {
    Some(match iface {
        "wl_shm" => "delegate_shm!",
        "wl_output" | "zxdg_output_manager_v1" => "delegate_output!",
        "wl_seat" => "delegate_seat!",
        "zwp_primary_selection_device_manager_v1" => "delegate_primary_selection!",
        "wl_data_device_manager" => "delegate_data_device!",
        "wl_compositor" | "wl_subcompositor" => "delegate_compositor!",
        "xdg_wm_base" => "delegate_xdg_shell!",
        "zxdg_toplevel_decoration_v1" => "delegate_xdg_decoration!",
        "xdg_activation_v1" => "delegate_xdg_activation!",
        "zxdg_exporter_v2" | "zxdg_importer_v2" => "delegate_xdg_foreign!",
        "xdg_wm_dialog_v1" => "delegate_xdg_dialog!",
        "xdg_system_bell_v1" => "delegate_xdg_system_bell!",
        "xdg_toplevel_icon_v1" => "delegate_xdg_toplevel_icon!",
        "xdg_toplevel_tag_manager_v1" => "delegate_xdg_toplevel_tag!",
        "zwp_text_input_manager_v3" => "delegate_text_input_manager!",
        "zwp_input_method_manager_v2" => "delegate_input_method_manager!",
        "zwp_virtual_keyboard_manager_v1" => "delegate_virtual_keyboard_manager!",
        _ => return None,
    })
}

/// A module's files: the file, its siblings when it is a mod.rs, or a
/// directory's .rs files.
fn scoped_files(c: &Check, rel: &str) -> Vec<std::path::PathBuf> {
    let p = c.path(rel);
    let dir = if p.is_file() && p.file_name().is_some_and(|n| n == "mod.rs") {
        p.parent().unwrap().to_path_buf()
    } else if p.is_file() {
        return vec![p];
    } else if p.is_dir() {
        p
    } else {
        return vec![];
    };
    let mut v: Vec<_> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "rs"))
        .collect();
    v.sort();
    v
}

/// Bodies of `impl (Global)Dispatch<..hint..>` blocks; `hint` is escaped.
fn impl_blocks(text: &str, hint: &str) -> Result<Vec<String>> {
    let re = Regex::new(&format!(r"impl\s+(GlobalDispatch|Dispatch)<[^>\n]*{hint}"))?;
    let mut out = Vec::new();
    for m in re.find_iter(text) {
        let Some(start) = text[m.end()..].find('{').map(|i| i + m.end()) else { continue };
        let mut depth = 0;
        for (i, ch) in text[start..].char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        out.push(text[start..=start + i].to_string());
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    Ok(out)
}
