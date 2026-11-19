//! `cargo xtask build|test|archive|run <target>`: Exact bun hosts (no Wawona.xcodeproj).

use crate::exact_host;
use crate::util::{cmd, output, root, run};
use anyhow::{bail, Context, Result};
use std::path::PathBuf;

const BUNDLE_ID: &str = "com.aspauldingcode.Wawona";

#[derive(clap::Args)]
pub struct Args {
    /// macos, ios, ipados, ios-modeb, tvos, visionos, watchos, android,
    /// wearos, web, windows, linux, asteroidos, or `all` (test only).
    pub target: String,
    /// Build for a device instead of the simulator (macOS is always native).
    #[arg(long)]
    pub device: bool,
    #[arg(long)]
    pub release: bool,
    /// Sign device builds (Exact: EXACT_IDENTITY + EXACT_PROFILE).
    #[arg(long)]
    pub sign: bool,
    /// Extra settings (ignored for Exact; kept for CLI compat).
    #[arg(long = "set")]
    pub settings: Vec<String>,
}

#[derive(clap::Args)]
pub struct ArchiveArgs {
    pub target: String,
    /// Export method hint for Fastlane (Exact always writes an IPA/AAB).
    #[arg(long)]
    pub export: Option<String>,
}

#[derive(clap::Args)]
pub struct RunArgs {
    /// macos | ios | ipados | tvos | visionos | watchos.
    pub target: String,
    /// Skip Exact rebuild and launch the tip already under `.build/exact/`.
    /// Default is rebuild then launch (same shape as `cargo run`).
    #[arg(long)]
    pub no_rebuild: bool,
}

/// Open Exact tip UI. Always rebuilds unless `--no-rebuild`.
/// macOS: `open` the .app. Apple sims: install + launch.
pub fn run_app(a: RunArgs) -> Result<()> {
    match a.target.as_str() {
        "macos" => run_macos(!a.no_rebuild),
        "ios" | "ipados" | "tvos" | "visionos" | "watchos" => {
            run_apple_sim(&a.target, !a.no_rebuild)
        }
        other => bail!(
            "cargo xtask run: macos|ios|ipados|tvos|visionos|watchos (got {other}). \
             Android / web / linux: cargo xtask build {other}"
        ),
    }
}

fn run_macos(do_build: bool) -> Result<()> {
    let app = root().join(".build/exact/macos/Wawona.app");
    if do_build || !app.is_dir() {
        build(Args {
            target: "macos".into(),
            device: false,
            release: false,
            sign: false,
            settings: vec![],
        })?;
    }
    if !app.is_dir() {
        bail!("no {}", app.display());
    }
    println!("{}", app.display());
    run(cmd("open").arg(&app))
}

fn run_apple_sim(target: &str, do_build: bool) -> Result<()> {
    let app = root().join(".build/exact").join(target).join("Wawona.app");
    if do_build || !app.is_dir() {
        build(Args {
            target: target.into(),
            device: false,
            release: false,
            sign: false,
            settings: vec![],
        })?;
    }
    if !app.is_dir() {
        bail!("no {}", app.display());
    }
    let (runtime, device) = match target {
        "ios" | "ipados" => ("iOS", "iPhone"),
        "tvos" => ("tvOS", "Apple TV"),
        "visionos" => ("xrOS", "Apple Vision"),
        "watchos" => ("watchOS", "Apple Watch"),
        _ => unreachable!(),
    };
    // iPadOS product still uses the iPhone sim tip today (`--ios` Exact host).
    let device = if target == "ipados" { "iPad" } else { device };
    let udid = pick_simulator(runtime, device)?;
    let _ = cmd("xcrun").args(["simctl", "boot", &udid]).status();
    let _ = cmd("open").args(["-a", "Simulator"]).status();
    // Exact / store trees can be read-only; simctl wants a writable bundle.
    let staging = PathBuf::from(format!("/tmp/wawona-{target}-run.app"));
    let _ = std::fs::remove_dir_all(&staging);
    run(cmd("ditto").arg(&app).arg(&staging))?;
    run(cmd("chmod").args(["-R", "u+rwX"]).arg(&staging))?;
    let _ = cmd("xattr").args(["-cr"]).arg(&staging).status();
    run(cmd("xcrun").args(["simctl", "install", &udid, &staging.display().to_string()]))?;
    run(cmd("xcrun").args(["simctl", "launch", &udid, BUNDLE_ID]))?;
    println!("{}", app.display());
    eprintln!("sim {udid} launched {BUNDLE_ID}");
    Ok(())
}

fn pick_simulator(runtime: &str, device: &str) -> Result<String> {
    if let Ok(udid) = std::env::var("WAWONA_SIM_UDID") {
        if !udid.is_empty() {
            return Ok(udid);
        }
    }
    if let Ok(udid) = std::env::var("EXACT_SIM") {
        if !udid.is_empty() {
            return Ok(udid);
        }
    }
    let raw = output(cmd("xcrun").args(["simctl", "list", "devices", "available", "-j"]))?;
    let v: serde_json::Value = serde_json::from_str(&raw)?;
    let devices = v
        .get("devices")
        .and_then(|d| d.as_object())
        .context("simctl devices json")?;
    let mut booted: Option<String> = None;
    let mut any: Option<String> = None;
    for (rt, list) in devices {
        if !rt.contains(runtime) {
            continue;
        }
        let Some(arr) = list.as_array() else { continue };
        for d in arr {
            let name = d.get("name").and_then(|n| n.as_str()).unwrap_or("");
            let udid = d.get("udid").and_then(|n| n.as_str()).unwrap_or("");
            let state = d.get("state").and_then(|n| n.as_str()).unwrap_or("");
            if udid.is_empty() || !name.contains(device) {
                continue;
            }
            if state == "Booted" {
                booted = Some(udid.into());
                break;
            }
            if any.is_none() {
                any = Some(udid.into());
            }
        }
        if booted.is_some() {
            break;
        }
    }
    booted
        .or(any)
        .with_context(|| format!("no {runtime} simulator matching {device}"))
}

pub fn build(a: Args) -> Result<()> {
    if a.target == "android" || a.target == "wearos" {
        let apk = exact_host::build_android(false, a.target == "wearos")?;
        println!("{}", apk.display());
        return Ok(());
    }
    if matches!(a.target.as_str(), "web" | "windows" | "linux" | "asteroidos") {
        let out = exact_host::build_host(&a.target)?;
        println!("{}", out.display());
        return Ok(());
    }
    let key = if a.device && a.target == "ios" {
        "ios-device"
    } else {
        a.target.as_str()
    };
    let t = exact_host::target(key)?;
    if a.sign {
        // Ensure identity is visible to Exact when archiving later.
        std::env::var("EXACT_IDENTITY").ok();
    }
    let app = exact_host::build_apple(&t)?;
    println!("{}", app.display());
    Ok(())
}

pub fn test(a: Args) -> Result<()> {
    if a.target == "all" {
        return test_all();
    }
    match a.target.as_str() {
        "rust" => {
            crate::prove::bend_gate()?;
            run(cmd("cargo").current_dir(root()).args(["test", "-p", "wawona-laws", "--offline"]))?;
            let exact = crate::exact_host::exact_root()?;
            run(cmd("cargo").current_dir(exact).args(["test", "-p", "wawona-data", "--offline"]))?;
            run(cmd("cargo").current_dir(root()).args(["test", "--manifest-path", "verification/helpers-check/Cargo.toml", "--offline"]))?;
            run(cmd("cargo").current_dir(root()).args(["test", "--tests", "--no-fail-fast"]))
        }
        "android" | "wearos" | "web" | "windows" | "linux" | "asteroidos" => {
            build(Args {
                target: a.target,
                device: false,
                release: false,
                sign: false,
                settings: vec![],
            })?;
            Ok(())
        }
        "ios" => {
            let t = exact_host::target("ios")?;
            let app = exact_host::build_apple(&t)?;
            println!("Exact iOS app ready for XCTest/Appium: {}", app.display());
            Ok(())
        }
        other => bail!(
            "cargo xtask test: rust, ios, android, wearos, web, windows, linux, asteroidos, or all (got {other})"
        ),
    }
}

pub fn archive(a: ArchiveArgs) -> Result<()> {
    if a.target == "android" || a.target == "wearos" {
        let aab = exact_host::build_android(true, a.target == "wearos")?;
        println!("{}", aab.display());
        return Ok(());
    }
    if matches!(a.target.as_str(), "web" | "windows" | "linux" | "asteroidos") {
        let out = exact_host::build_host(&a.target)?;
        println!("{}", out.display());
        return Ok(());
    }
    let out_dir = root().join("dist");
    std::fs::create_dir_all(&out_dir)?;
    let ipa = out_dir.join(format!("Wawona-{}.ipa", a.target));
    if a.target == "ios" || a.target == "ipados" || a.target == "ios-modeb" {
        let path = exact_host::archive_ios(&ipa)?;
        println!("{}", path.display());
        return Ok(());
    }
    // macOS / tv / vision / watch: Exact .app then zip as ship artifact when archive asked.
    let key = a.target.as_str();
    let t = exact_host::target(key)?;
    let app = exact_host::build_apple(&t)?;
    if a.export.is_some() && (key == "ios" || key.starts_with("ios")) {
        let path = exact_host::archive_ios(&ipa)?;
        println!("{}", path.display());
        return Ok(());
    }
    println!("{}", app.display());
    Ok(())
}

fn test_all() -> Result<()> {
    const TARGETS: &[&str] = &[
        "web",
        "windows",
        "linux",
        "asteroidos",
        "android",
        "wearos",
        "macos",
        "ios",
        "ipados",
        "tvos",
        "visionos",
        "watchos",
    ];
    let mut failed = Vec::new();
    for target in TARGETS {
        match build(Args {
            target: (*target).to_string(),
            device: false,
            release: false,
            sign: false,
            settings: vec![],
        }) {
            Ok(()) => eprintln!("PASS {target}"),
            Err(e) => {
                eprintln!("FAIL {target}: {e:#}");
                failed.push(*target);
            }
        }
    }
    if failed.is_empty() {
        Ok(())
    } else {
        bail!("failed: {}", failed.join(", "))
    }
}

/// Compat for lab/install/package that previously used Xcode DerivedData paths.
pub struct Target {
    pub name: &'static str,
    #[allow(dead_code)]
    pub scheme: &'static str,
}

pub fn target(name: &str) -> Result<&'static Target> {
    const ALL: &[Target] = &[
        Target { name: "macos", scheme: "Wawona-macOS" },
        Target { name: "ios", scheme: "Wawona-iOS" },
        Target { name: "ipados", scheme: "Wawona-iPadOS" },
        Target { name: "ios-modeb", scheme: "Wawona-iOS-ModeB" },
        Target { name: "tvos", scheme: "Wawona-tvOS" },
        Target { name: "visionos", scheme: "Wawona-visionOS" },
        Target { name: "watchos", scheme: "Wawona-watchOS" },
    ];
    ALL.iter().find(|t| t.name == name).ok_or_else(|| anyhow::anyhow!("unknown target {name}"))
}

impl Target {
    /// Preferred Exact tip / build product path after cutover.
    pub fn app(&self, _device: bool, _release: bool) -> PathBuf {
        if let Ok(p) = std::env::var("WAWONA_APP_PATH") {
            return PathBuf::from(p);
        }
        let tip = PathBuf::from(format!("/tmp/wawona-{}-tip/Wawona.app", self.name));
        if tip.is_dir() {
            return tip;
        }
        root().join(".build/exact").join(self.name).join("Wawona.app")
    }
}
