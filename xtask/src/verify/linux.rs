use super::{files_under, Check, Opts};
use crate::util::*;
use anyhow::Result;
use regex::Regex;
use serde_json::Value;

/// `src/linux/bundled_clients.rs` stays 1:1 with Android's catalog: same
/// ids, names and order.
pub fn bundled_clients(c: &mut Check, _: &Opts) -> Result<String> {
    let android = "android/app/src/main/java/com/aspauldingcode/wawona/BundledClients.kt";
    let linux = "src/linux/bundled_clients.rs";
    let (Some(a), Some(l)) = (c.text(android), c.text(linux)) else { return Ok(String::new()) };
    let pairs = |re: &str, src: &str| -> Vec<(String, String)> {
        Regex::new(re).unwrap().captures_iter(src).map(|m| (m[1].to_string(), m[2].to_string())).collect()
    };
    let a = pairs(r#"BundledClientOption\(\s*"([^"]+)"\s*,\s*"([^"]+)""#, &a);
    let l = pairs(r#"BundledClient\s*\{\s*id:\s*"([^"]+)"\s*,\s*name:\s*"([^"]+)""#, &l);
    for (name, v) in [("Android", &a), ("Linux", &l)] {
        if v.len() != 2 {
            c.fail(format!("expected 2 {name} product clients, found {}", v.len()));
        }
    }
    let ids = |v: &[(String, String)]| v.iter().map(|p| p.0.clone()).collect::<Vec<_>>();
    if ids(&a) != ids(&l) {
        c.fail(format!("Linux client ids or order differ from Android: android={:?} linux={:?}", ids(&a), ids(&l)));
    }
    for (id, name) in &l {
        if let Some((_, an)) = a.iter().find(|p| &p.0 == id) {
            if an != name {
                c.fail(format!("display name mismatch for {id}: android={an:?} linux={name:?}"));
            }
        }
    }
    Ok(format!("{} clients", l.len()))
}

/// The machine profile model serializes the `wawona.machineProfiles.v1` keys
/// the Swift Codable types use, irregular acronym casing included.
pub fn machines_parity(c: &mut Check, _: &Opts) -> Result<String> {
    c.need(
        "src/linux/machine_profile.rs",
        &["crate::domain::machine_profile"],
        "the Linux model re-exports the shared one",
    );
    let model = "src/domain/machine_profile.rs";
    c.need(model, &["Native", "SshWaypipe", "SshTerminal", "VirtualMachine", "Container"], "MachineType variant");
    c.need(model, &["rename_all = \"snake_case\""], "MachineType serializes as the Swift rawValues");
    c.need(
        model,
        &[
            "\"type\"",
            "\"sshHost\"",
            "\"sshUser\"",
            "\"sshPort\"",
            "\"sshPassword\"",
            "\"remoteCommand\"",
            "\"runtimeOverrides\"",
            "\"executablePath\"",
            "\"autoLaunch\"",
            "\"displayName\"",
        ],
        "profile JSON key",
    );
    c.need(
        model,
        &[
            "\"vulkanDriver\"",
            "\"openGLDriver\"",
            "\"dmabufEnabled\"",
            "\"inputProfile\"",
            "\"bundledAppID\"",
            "\"waypipeEnabled\"",
            "\"forceSSD\"",
            "\"renderMacOSPointer\"",
            "\"autoScale\"",
            "\"waylandDisplay\"",
            "\"colorOperations\"",
            "\"waypipeSSHPassword\"",
            "\"logLevel\"",
            "\"shakeToCloseEnabled\"",
            "\"swipeBackToCloseEnabled\"",
        ],
        "runtime override JSON key",
    );
    c.need(
        "src/linux/profile_store.rs",
        &["wawona.machineProfiles.v1", "machine-profiles-v1.json", "migrate_from_legacy"],
        "the store persists the canonical key and migrates the legacy config",
    );
    Ok("wawona.machineProfiles.v1".into())
}

/// The Linux wrappers take the UI binary (or they exit 1 at run time), stay
/// LF and strip CR (issue #164), and autostart the compositor host.
pub fn package_wiring(c: &mut Check, _: &Opts) -> Result<String> {
    let flake = c.text("flake.nix").unwrap_or_default();
    for attr in ["wawona-linux", "wawona-linux-compositor-host", "wawona-linux-tray", "default", "wawona"] {
        let re = format!(
            r"(?s){}\s*=\s*pkgs\.callPackage\s+\./dependencies/wawona/linux(?:-host|-tray)?\.nix\s*\{{(.*?)\n\s*\}};",
            regex::escape(attr)
        );
        match Regex::new(&re)?.find(&flake) {
            None => c.fail(format!("flake.nix missing the pkgs.callPackage linux site for {attr}")),
            Some(m) if !m.as_str().contains("wawonaLinuxUiBin") => {
                c.fail(format!("flake.nix {attr} must pass wawonaLinuxUiBin (the wrapper exits 1 without it)"))
            }
            _ => {}
        }
    }
    for f in ["src/linux/service.rs", "src/bin/wawona-linux-tray.rs"] {
        c.forbid(f, &["/home/alex/Wawona"], "a hardcoded flake path");
    }
    let service = c.text("src/linux/service.rs").unwrap_or_default();
    if service.lines().any(|l| l.contains("WantedBy=default.target") && !l.contains("assert")) {
        c.fail("src/linux/service.rs must use WantedBy=graphical-session.target, not default.target");
    }
    c.need(
        "src/linux/service.rs",
        &["render_autostart_desktop", "wawona-linux-compositor-host", "fn resolve_flake_ref"],
        "autostart targets the compositor host",
    );
    for f in
        ["dependencies/wawona/linux.nix", "dependencies/wawona/linux-host.nix", "dependencies/wawona/linux-tray.nix"]
    {
        let Ok(raw) = std::fs::read(c.path(f)) else {
            c.fail(format!("missing {f}"));
            continue;
        };
        if raw.contains(&b'\r') {
            c.fail(format!("{f} contains CR (issue #164); keep LF"));
        }
        let t = String::from_utf8_lossy(&raw);
        if !t.contains("builtins.replaceStrings") || !t.contains(r#"["\r"]"#) {
            c.fail(format!(r#"{f} must strip \r with builtins.replaceStrings ["\r"] [""] (issue #164)"#));
        }
        if !t.contains("wawonaLinuxUiBin") {
            c.fail(format!("{f} must take wawonaLinuxUiBin"));
        }
    }
    c.need(".gitattributes", &["*.nix text eol=lf"], "issue #164 LF policy");
    Ok("UI binary wired; LF".into())
}

pub fn shell_tools(c: &mut Check, _: &Opts) -> Result<String> {
    c.need(
        "dependencies/wawona/linux.nix",
        &["pkgs.zsh", "pkgs.fastfetch", "pkgs.weston", "pkgs.foot", "pkgs.kmscube", "pkgs.waypipe", "pkgs.openssh"],
        "runtimeInputs the launcher spawns",
    );
    Ok("shell and client runtimes".into())
}

/// Every patched dependency builds against one nixpkgs so source hashes
/// agree. Only pure build tooling outside the artifact closure may differ.
pub fn nixpkgs_lineage(c: &mut Check, _: &Opts) -> Result<String> {
    const TOOLING: &[&str] = &["cachix"];
    let Some(lock) = c.text("flake.lock") else { return Ok(String::new()) };
    let lock: Value = serde_json::from_str(&lock)?;
    let nodes = lock["nodes"].as_object().cloned().unwrap_or_default();
    let root = lock["root"].as_str().unwrap_or("root").to_string();
    fn resolve(nodes: &serde_json::Map<String, Value>, root: &str, edge: &Value) -> Option<String> {
        match edge {
            Value::String(s) => Some(s.clone()),
            Value::Array(path) => path
                .iter()
                .try_fold(root.to_string(), |n, seg| resolve(nodes, root, &nodes.get(&n)?["inputs"][seg.as_str()?])),
            _ => None,
        }
    }
    let root_inputs = nodes[&root]["inputs"].as_object().cloned().unwrap_or_default();
    let Some(root_nixpkgs) = root_inputs.get("nixpkgs").and_then(|e| resolve(&nodes, &root, e)) else {
        c.fail("the root has no nixpkgs input");
        return Ok(String::new());
    };
    for (name, dst) in &root_inputs {
        if !(name.starts_with("wwn-") || ["rust-overlay", "microvm", "crate2nix"].contains(&name.as_str())) {
            continue;
        }
        let node = resolve(&nodes, &root, dst).unwrap_or_default();
        let Some(edge) = nodes.get(&node).map(|n| &n["inputs"]["nixpkgs"]).filter(|e| !e.is_null()) else { continue };
        let got = resolve(&nodes, &root, edge).unwrap_or_default();
        if got != root_nixpkgs {
            c.fail(format!(
                "input '{name}' resolves nixpkgs to '{got}', not the root '{root_nixpkgs}'. Add `{name}.inputs.nixpkgs.follows = \"nixpkgs\"`"
            ));
        }
    }
    let mut others: Vec<&String> =
        nodes.keys().filter(|k| (*k == "nixpkgs" || k.starts_with("nixpkgs_")) && **k != root_nixpkgs).collect();
    others.sort();
    for n in others {
        let mut stray: Vec<&String> = nodes
            .iter()
            .filter(|(p, node)| {
                !TOOLING.contains(&p.as_str())
                    && node["inputs"].as_object().is_some_and(|i| i.values().any(|d| d.as_str() == Some(n.as_str())))
            })
            .map(|(p, _)| p)
            .collect();
        stray.sort();
        if !stray.is_empty() {
            let rev: String = nodes[n]["locked"]["rev"].as_str().unwrap_or("").chars().take(12).collect();
            c.fail(format!(
                "non-root nixpkgs '{n}' (@{rev}) consumed by {stray:?}; make them follow the root nixpkgs or add them to the tooling allowlist"
            ));
        }
    }
    let rev: String = nodes[&root_nixpkgs]["locked"]["rev"].as_str().unwrap_or("").chars().take(12).collect();
    Ok(format!("single build lineage @{rev}"))
}

/// macOS bsdtar ignores GNU tar's --wildcards, so a glob extract silently
/// matches nothing. Extract a directory member and filter instead.
pub fn no_tar_wildcards(c: &mut Check, _: &Opts) -> Result<String> {
    let call = Regex::new(r"(^|[\s;&|(])tar\b[^\n]*--wildcards\b")?;
    let mut files: Vec<_> = std::fs::read_dir(&c.root)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "nix"))
        .collect();
    for d in ["dependencies", ".github"] {
        files.extend(files_under(&c.root, d, ".nix"));
    }
    let skip = ["result/", "target/", ".direnv/", "inspirational_projects/", "/nixpkgs/"];
    let mut n = 0;
    for p in files {
        let rel = c.rel(&p);
        if skip.iter().any(|s| rel.contains(s)) {
            continue;
        }
        n += 1;
        for (i, l) in read(&p)?.lines().enumerate() {
            if !l.trim_start().starts_with('#') && call.is_match(l) {
                c.fail(format!("{rel}:{}: {}", i + 1, l.trim()));
            }
        }
    }
    Ok(format!("{n} recipes"))
}
