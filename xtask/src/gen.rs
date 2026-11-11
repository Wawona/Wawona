//! `cargo xtask gen <what>`: regenerate committed files from their sources.

use crate::util::*;
use anyhow::{bail, Result};
use std::path::{Path, PathBuf};

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// docs/protocol-status.md from PROTOCOL_CATALOG and the live registry,
    /// then the wawona.io copy when that checkout is beside this one.
    ProtocolStatus,
    /// docs/protocol-expect/*.json from the catalog's expect_on, then the
    /// protocol-probe package in a sibling repo.wawona.io.
    ProtocolExpect,
    /// Create or update the protocol roadmap milestones on GitHub (titles
    /// match docs/protocol-milestones.md). Never closes one.
    ProtocolMilestones,
    /// The SettingsDependencies.json snapshots from settings-deps.nix.
    SettingsDeps,
    /// Rust crate licenses for NOTICE (needs cargo-license).
    Licenses {
        /// Also write docs/cargo-licenses.json.
        #[arg(long)]
        json: bool,
    },
    /// shader_spv.h for renderer_android.c: the quad shaders under `src`
    /// compiled to SPIR-V (glslc or glslangValidator on PATH) as byte arrays.
    /// Runs in the Android deps derivation, so it reads no checkout.
    AndroidShaders { src: PathBuf, out: PathBuf },
}

pub fn main(c: Cmd) -> Result<()> {
    if let Cmd::AndroidShaders { src, out } = &c {
        return android_shaders(src, out);
    }
    std::env::set_current_dir(root())?;
    match c {
        Cmd::ProtocolStatus => {
            lib_test("WWN_WRITE_PROTOCOL_STATUS", "tests::protocol_matrix::test_generate_protocol_status_manifest")?;
            let site = root().join("../wawona.io/scripts/sync-protocol-status.sh");
            if site.is_file() {
                run(cmd(&site).env("WAWONA_REPO", root()))?;
            } else {
                eprintln!("wawona.io is not beside this checkout; run its scripts/sync-protocol-status.sh there");
            }
            eprintln!("Review docs/protocol-status.md; milestones: cargo xtask gen protocol-milestones");
            Ok(())
        }
        Cmd::ProtocolExpect => {
            lib_test(
                "WWN_WRITE_PROTOCOL_EXPECT",
                "core::wayland::catalog::tests::test_generate_protocol_expect_manifests",
            )?;
            let probe = root().join("../repo.wawona.io/catalog/wasm/src/p1/packages/protocol-probe");
            if probe.is_dir() {
                let dst = probe.join("expect");
                std::fs::create_dir_all(&dst)?;
                for f in crate::verify::files_under(&root(), "docs/protocol-expect", ".json") {
                    std::fs::copy(&f, dst.join(f.file_name().unwrap()))?;
                }
                eprintln!("synced the expect JSON into {}", dst.display());
            }
            Ok(())
        }
        Cmd::ProtocolMilestones => milestones(),
        Cmd::SettingsDeps => settings_deps(),
        Cmd::AndroidShaders { .. } => unreachable!(),
        Cmd::Licenses { json } => {
            if try_output(cmd("cargo").args(["license", "--version"])).is_none() {
                bail!("cargo-license is not installed: cargo install cargo-license");
            }
            run(cmd("cargo").args(["license", "--tsv"]))?;
            if json {
                write("docs/cargo-licenses.json", output(cmd("cargo").args(["license", "--json"]))?)?;
                eprintln!("wrote docs/cargo-licenses.json");
            }
            Ok(())
        }
    }
}

/// One library test that writes a generated file when `flag` is set.
fn lib_test(flag: &str, test: &str) -> Result<()> {
    run(cmd("cargo").args(["test", "--lib", test, "--", "--nocapture", "--exact"]).env(flag, "1"))
}

const MILESTONES: [(&str, &str); 8] = [
    ("Wayland protocols: Explorer catalog honesty", "Catalog tracks all Explorer families; Missing rows; portable advertise gates; protocol-status + wawona.io sync."),
    ("Wayland protocols: close Partials", "commit-timing, fifo, gestures, idle-notify, foreign-toplevel list, wlr foreign/virtual-pointer, toplevel icon/tag."),
    ("Wayland protocols: high-traffic Stubs", "session-lock, workspace, data-control, color, screencopy, wlr-output/gamma/power, security-context, tablet, xwayland."),
    ("Wayland protocols: KDE / Plasma remainder", "plasma shell, window management, virtual desktop, screencast, output management/device/order, appmenu, fake-input."),
    ("Wayland protocols: COSMIC + River", "Implement COSMIC and River protocol families to Functional."),
    ("Wayland protocols: Hyprland + Treeland + Weston", "Implement Hyprland, Treeland, and Weston/IVI families to Functional."),
    ("Wayland protocols: external vendor shells", "GTK shell, Aura, AGL, Mir, XApp, NVIDIA EGLStream as demand requires."),
    ("Wayland protocols: Kani erroneous-check proofs", "Every Functional protocol error path has a named helper + fail-closed Kani harness in Verification report."),
];

fn milestones() -> Result<()> {
    let repo = env_or("GITHUB_REPOSITORY", "Wawona/Wawona");
    let list = output(cmd("gh").args(["api", &format!("repos/{repo}/milestones?state=all&per_page=100")]))?;
    let existing: Vec<serde_json::Value> = serde_json::from_str(&list)?;
    for (title, desc) in MILESTONES {
        let found = existing.iter().find(|m| m["title"] == title).and_then(|m| m["number"].as_u64());
        let mut gh = cmd("gh");
        match found {
            Some(n) => gh.args(["api", "--method", "PATCH", &format!("repos/{repo}/milestones/{n}")]),
            None => gh.args([
                "api",
                "--method",
                "POST",
                &format!("repos/{repo}/milestones"),
                "-f",
                &format!("title={title}"),
            ]),
        };
        output(gh.args(["-f", &format!("description={desc}"), "-f", "state=open"]))?;
        eprintln!("{} {title}", if found.is_some() { "updated" } else { "created" });
    }
    Ok(())
}

fn settings_deps() -> Result<()> {
    let nix = root().join("dependencies/wawona/settings-deps.nix");
    let iland = root().join("../iLand/VERSION");
    match std::fs::read_to_string(&iland) {
        Ok(v) => eprintln!("iland VERSION (sibling): {}", v.trim()),
        Err(_) => eprintln!("warning: sibling iLand/VERSION not found; using the settings-deps fallback"),
    }
    let targets = [
        ("ios", "src/resources/settings-deps/ios/SettingsDependencies.json"),
        ("ipados", "src/resources/settings-deps/ipados/SettingsDependencies.json"),
        ("macos", "src/resources/settings-deps/macos/SettingsDependencies.json"),
        ("tvos", "src/resources/settings-deps/tvos/SettingsDependencies.json"),
        ("watchos", "src/resources/settings-deps/watchos/SettingsDependencies.json"),
        ("visionos", "src/resources/settings-deps/visionos/SettingsDependencies.json"),
        ("android", "android/app/src/main/assets/SettingsDependencies.json"),
        ("linux", "src/linux/ui/settings_dependencies.json"),
    ];
    for (target, out) in targets {
        let expr = format!("let d = import {}; in d.inventories.{target} d.versions", nix.display());
        let packages: serde_json::Value =
            serde_json::from_str(&output(cmd("nix-instantiate").args(["--eval", "--strict", "--json", "-E", &expr]))?)?;
        write(Path::new(out), format!("{}\n\n", ascii_json(&serde_json::json!({ "packages": packages }))?))?;
        eprintln!("wrote {out}");
    }
    Ok(())
}

/// Two-space JSON with non-ASCII escaped, the snapshots' committed form.
fn ascii_json(v: &serde_json::Value) -> Result<String> {
    let s = serde_json::to_string_pretty(v)?;
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        if ch.is_ascii() {
            out.push(ch);
        } else {
            let mut buf = [0u16; 2];
            for u in ch.encode_utf16(&mut buf) {
                out.push_str(&format!("\\u{u:04x}"));
            }
        }
    }
    Ok(out)
}

fn android_shaders(src: &Path, out: &Path) -> Result<()> {
    let shaders = src.join("src/platform/android/rendering/shaders");
    let (compiler, flag) = if have("glslc") {
        ("glslc", None)
    } else if have("glslangValidator") {
        ("glslangValidator", Some("-V"))
    } else {
        bail!("glslc or glslangValidator is not on PATH (nix: pkgs.glslang)");
    };
    std::fs::create_dir_all(out)?;
    let mut header = String::from(
        "/* Auto-generated - do not edit */\n#pragma once\n\n#include <stddef.h>\n#include <stdint.h>\n\n",
    );
    for (stage, name) in [("vert", "g_quad_vert_spv"), ("frag", "g_quad_frag_spv")] {
        let spv = out.join(format!("quad.{stage}.spv"));
        run(cmd(compiler).args(flag).arg(shaders.join(format!("android_quad.{stage}"))).arg("-o").arg(&spv))?;
        let bytes = std::fs::read(&spv)?;
        header += &format!("static const unsigned char {name}[] = {{\n");
        for row in bytes.chunks(12) {
            let hex: Vec<String> = row.iter().map(|b| format!("0x{b:02x}")).collect();
            header += &format!("  {},\n", hex.join(", "));
        }
        header += &format!("}};\nstatic const size_t {name}_len = sizeof({name});\n\n");
        eprintln!("embedded {} ({} bytes)", spv.display(), bytes.len());
    }
    std::fs::write(out.join("shader_spv.h"), header)?;
    Ok(())
}
