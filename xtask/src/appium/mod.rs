//! `cargo xtask appium <task>`: the Appium UI suite (rule wawona-appium-ui-gh).
//! Tests/appium/matrix.toml gates each case by PlatformCapabilities;
//! Tests/appium/selectors.json holds the wwn.* ids every host must carry.

mod cases;
mod evidence;
mod host;
mod pages;
mod session;
mod webdriver;

use std::collections::BTreeSet;
use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use regex::Regex;
use serde_json::Value;

use crate::util::*;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Offline checks: selectors.json ids in Swift, Kotlin and Linux; the
    /// matrix shape; every catalog client mapped by cargo xtask appium launch.
    Verify,
    /// Fail unless every catalog client has a non-blank gallery screenshot.
    Gallery {
        /// Check only these clients (comma-separated).
        #[arg(long, env = "WAWONA_CATALOG_VERIFY_ONLY", value_delimiter = ',')]
        only: Vec<String>,
    },
    /// Run the suite against an Appium server. Writes junit.xml to the
    /// artifacts directory.
    Run(cases::Args),
    /// Capture every catalog client (or these) into the gallery, then check
    /// it: Colima, the Appium server, the tip app and WebDriverAgentMac first.
    Catalog { clients: Vec<String> },
    /// Launch one catalog client into the running compositor (Colima guest
    /// over waypipe on macOS, nested on Linux).
    Launch { client: String },
    /// Colima guests over waypipe SSH, by hand.
    Waypipe(host::LabArgs),
    /// Fail closed unless Colima runs and its guest answers SSH.
    Colima,
    /// Start the Appium server on :4723 unless it answers.
    Server,
    /// Start WebDriverAgentMac on :10100 unless it answers.
    Wda,
    /// Print the artifact root export (non-hidden on GitHub Actions).
    Prepare,
}

pub fn main(cmd: Cmd) -> Result<()> {
    match cmd {
        Cmd::Verify => verify(),
        Cmd::Gallery { only } => evidence::verify_gallery(&artifacts(), &only),
        Cmd::Run(a) => cases::run(a),
        Cmd::Catalog { clients } => host::catalog(&clients),
        Cmd::Launch { client } => host::launch(&client),
        Cmd::Waypipe(a) => host::lab(a),
        Cmd::Colima => host::ensure_colima().map(drop),
        Cmd::Server => host::ensure_server(),
        Cmd::Wda => host::ensure_wda(),
        Cmd::Prepare => host::prepare_artifacts(),
    }
}

/// `WAWONA_APPIUM_ARTIFACTS`, default `.agent-device/test-artifacts/appium`.
pub fn artifacts() -> PathBuf {
    std::env::var("WAWONA_APPIUM_ARTIFACTS")
        .map(PathBuf::from)
        .unwrap_or_else(|_| root().join(".agent-device/test-artifacts/appium"))
}

pub fn platform() -> String {
    env_or("WAWONA_APPIUM_PLATFORM", "ios").trim().to_lowercase()
}

pub const PLATFORMS: [&str; 8] = ["ios", "ipados", "tvos", "watchos", "visionos", "macos", "android", "linux"];
const FEATURES: [&str; 10] = [
    "vm",
    "container",
    "multi_window",
    "toolbar_keys",
    "device_rotation",
    "gpu_driver_picker",
    "ssh",
    "waypipe",
    "wasm",
    "native_shell",
];
pub const KINDS: [&str; 2] = ["compositors", "applications"];

pub struct Matrix(toml::Table);

impl Matrix {
    pub fn load() -> Result<Self> {
        Ok(Self(toml::from_str(&read(root().join("Tests/appium/matrix.toml"))?)?))
    }

    pub fn row(&self, platform: &str) -> Result<&toml::Table> {
        self.0
            .get("platforms")
            .and_then(|p| p.get(platform))
            .and_then(|r| r.as_table())
            .with_context(|| format!("unknown platform {platform:?} in matrix.toml"))
    }

    /// A feature's gate state: available, planned, blocked, forbidden, or a
    /// window policy (fill_primary, multi_scene, native_appkit, stub, ...).
    pub fn state(&self, platform: &str, feature: &str) -> Result<String> {
        let row = self.row(platform)?;
        let v = row.get(feature).and_then(|v| v.as_str());
        Ok(v.with_context(|| format!("platforms.{platform}.{feature} unset"))?.to_string())
    }

    pub fn allows_new_window(&self, platform: &str) -> Result<bool> {
        Ok(matches!(self.state(platform, "multi_window")?.as_str(), "multi_scene" | "native_appkit"))
    }

    pub fn catalog(&self, kind: &str) -> Vec<(String, toml::Table)> {
        let group = self.0.get("catalog").and_then(|c| c.get(kind)).and_then(|g| g.as_table());
        group.into_iter().flatten().map(|(k, v)| (k.clone(), v.as_table().cloned().unwrap_or_default())).collect()
    }

    pub fn entry(&self, kind: &str, name: &str) -> Result<toml::Table> {
        let found = self.catalog(kind).into_iter().find(|(k, _)| k == name);
        Ok(found.with_context(|| format!("catalog.{kind}.{name} missing"))?.1)
    }

    pub fn clients(&self) -> Vec<String> {
        KINDS.iter().flat_map(|k| self.catalog(k).into_iter().map(|(n, _)| n)).collect()
    }
}

fn field<'a>(t: &'a toml::Table, k: &str) -> &'a str {
    t.get(k).and_then(|v| v.as_str()).unwrap_or("")
}

pub fn selector_ids() -> Result<BTreeSet<String>> {
    let v: Value = serde_json::from_str(&read(root().join("Tests/appium/selectors.json"))?)?;
    Ok(v["ids"].as_array().into_iter().flatten().filter_map(|i| i.as_str().map(String::from)).collect())
}

fn verify() -> Result<()> {
    let mut failed = false;
    let required = selector_ids()?;
    let quoted = Regex::new(r#""(wwn\.[^"]+)""#)?;
    for (name, path) in [
        ("swift", "Sources/WawonaUI/Machines/Catalog/WWNAccessibilityIdentifiers.swift"),
        ("kotlin", "android/app/src/main/java/com/aspauldingcode/wawona/WawonaTestTags.kt"),
        ("linux", "src/linux/ui/a11y.rs"),
    ] {
        let text = read(root().join(path))?;
        let found: BTreeSet<&str> = quoted.captures_iter(&text).map(|c| c.get(1).unwrap().as_str()).collect();
        let missing: Vec<_> = required.iter().filter(|id| !found.contains(id.as_str())).collect();
        if missing.is_empty() {
            println!("OK {name}: all {} cross-platform ids present", required.len());
        } else {
            failed = true;
            println!("FAIL {name}: missing {} required ids", missing.len());
            missing.iter().for_each(|id| println!("  - {id}"));
        }
    }

    let m = Matrix::load()?;
    let platforms: BTreeSet<&str> =
        m.0.get("platforms").and_then(|p| p.as_table()).into_iter().flatten().map(|(k, _)| k.as_str()).collect();
    if platforms != PLATFORMS.into_iter().collect() {
        failed = true;
        println!("FAIL matrix platforms: {platforms:?}");
    }
    for p in PLATFORMS {
        let Ok(row) = m.row(p) else { continue };
        let missing: Vec<_> = FEATURES.iter().filter(|f| !row.contains_key(**f)).collect();
        if !missing.is_empty() {
            failed = true;
            println!("FAIL matrix {p}: missing features {missing:?}");
        }
        if matches!(p, "macos" | "linux") && field(row, "catalog_clients") != "available" {
            failed = true;
            println!("FAIL platforms.{p}.catalog_clients must be available");
        }
    }

    // Matrix rows are Colima; nested is only a Linux CI override by env.
    let mapped: BTreeSet<String> = host::GUESTS.iter().map(|(c, _)| c.to_string()).collect();
    let mut clients = 0;
    for kind in KINDS {
        for (name, entry) in m.catalog(kind) {
            clients += 1;
            let problem = if field(&entry, "status") != "available" {
                "status must be available"
            } else if field(&entry, "guest") != "colima" {
                "guest must be colima"
            } else if !mapped.contains(&name) {
                "missing from host::GUESTS"
            } else {
                continue;
            };
            failed = true;
            println!("FAIL catalog.{kind}.{name}: {problem}");
        }
    }
    if clients == 0 {
        bail!("empty catalog in matrix.toml");
    }
    if failed {
        bail!("appium verify failed");
    }
    println!("OK matrix.toml platforms={} catalog clients={clients}, all mapped", platforms.len());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matrix_has_all_platforms_and_features() {
        let m = Matrix::load().unwrap();
        for p in PLATFORMS {
            for f in FEATURES {
                m.state(p, f).unwrap();
            }
        }
    }

    #[test]
    fn vm_and_container_gates() {
        let m = Matrix::load().unwrap();
        for (p, vm, container) in [
            ("tvos", "forbidden", "forbidden"),
            ("watchos", "forbidden", "forbidden"),
            ("macos", "planned", "available"),
            ("ios", "planned", "planned"),
        ] {
            assert_eq!(m.state(p, "vm").unwrap(), vm, "{p}");
            assert_eq!(m.state(p, "container").unwrap(), container, "{p}");
        }
    }

    #[test]
    fn new_window_policy() {
        let m = Matrix::load().unwrap();
        assert!(m.allows_new_window("macos").unwrap());
        assert!(!m.allows_new_window("ios").unwrap());
    }

    #[test]
    fn catalog_rows_are_colima_guests() {
        let m = Matrix::load().unwrap();
        for (kind, name, command) in [
            ("compositors", "weston", "weston"),
            ("compositors", "hyprland", "Hyprland"),
            ("applications", "foot", "foot"),
        ] {
            let e = m.entry(kind, name).unwrap();
            assert_eq!(field(&e, "status"), "available");
            assert_eq!(field(&e, "guest"), "colima");
            assert_eq!(field(&e, "command"), command);
        }
        let mut listed: Vec<_> =
            cases::COMPOSITORS.iter().chain(cases::APPLICATIONS.iter()).map(|s| s.to_string()).collect();
        let mut clients = m.clients();
        listed.sort();
        clients.sort();
        assert_eq!(listed, clients, "cases.rs client lists match matrix.toml");
        for p in ["macos", "linux"] {
            assert_eq!(m.state(p, "catalog_clients").unwrap(), "available");
        }
    }

    #[test]
    fn selectors_cover_the_cross_platform_ids() {
        let ids = selector_ids().unwrap();
        for id in ["wwn.machines.add", "wwn.machines.pin", "wwn.toolbar.customize", "wwn.keyboard.dismiss"] {
            assert!(ids.contains(id), "{id}");
        }
        assert!(ids.len() >= 40);
    }
}
