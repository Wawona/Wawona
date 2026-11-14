//! `cargo xtask build|test|archive <target>`: Exact bun hosts (no Wawona.xcodeproj).

use crate::exact_host;
use crate::util::{cmd, root, run};
use anyhow::{bail, Result};
use std::path::PathBuf;

#[derive(clap::Args)]
pub struct Args {
    /// macos, ios, ipados, ios-modeb, tvos, visionos, watchos or android.
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

pub fn build(a: Args) -> Result<()> {
    if a.target == "android" {
        let apk = exact_host::build_android(false)?;
        println!("{}", apk.display());
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
    match a.target.as_str() {
        "rust" => run(cmd("cargo").current_dir(root()).args(["test", "--tests", "--no-fail-fast"])),
        "android" => {
            // Exact Android host unit smoke: cargo check the crate.
            let exact = exact_host::exact_root()?;
            run(cmd("cargo")
                .current_dir(exact)
                .args(["check", "-p", "wawona-android"]))
        }
        "ios" => {
            let t = exact_host::target("ios")?;
            let app = exact_host::build_apple(&t)?;
            println!("Exact iOS app ready for XCTest/Appium: {}", app.display());
            Ok(())
        }
        other => bail!("cargo xtask test: rust, ios or android (got {other})"),
    }
}

pub fn archive(a: ArchiveArgs) -> Result<()> {
    if a.target == "android" {
        let aab = exact_host::build_android(true)?;
        println!("{}", aab.display());
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
