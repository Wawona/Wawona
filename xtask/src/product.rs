//! `cargo xtask build|test|archive <target>`: the apps, through the same
//! Wawona.xcodeproj schemes and Gradle project the IDEs open.

use crate::deps;
use crate::util::{cmd, env_or, root, run, write};
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};

pub struct Target {
    pub name: &'static str,
    pub scheme: &'static str,
    /// xcodebuild's generic destination platform; the simulator is
    /// "<platform> Simulator".
    pub platform: &'static str,
    pub sdk: &'static str,
    pub sim_sdk: Option<&'static str>,
}

const TARGETS: &[Target] = &[
    Target { name: "macos", scheme: "Wawona-macOS", platform: "macOS", sdk: "macosx", sim_sdk: None },
    Target { name: "ios", scheme: "Wawona-iOS", platform: "iOS", sdk: "iphoneos", sim_sdk: Some("iphonesimulator") },
    Target {
        name: "ipados",
        scheme: "Wawona-iPadOS",
        platform: "iOS",
        sdk: "iphoneos",
        sim_sdk: Some("iphonesimulator"),
    },
    Target { name: "ios-modeb", scheme: "Wawona-iOS-ModeB", platform: "iOS", sdk: "iphoneos", sim_sdk: None },
    Target {
        name: "tvos",
        scheme: "Wawona-tvOS",
        platform: "tvOS",
        sdk: "appletvos",
        sim_sdk: Some("appletvsimulator"),
    },
    Target {
        name: "visionos",
        scheme: "Wawona-visionOS",
        platform: "visionOS",
        sdk: "xros",
        sim_sdk: Some("xrsimulator"),
    },
    Target {
        name: "watchos",
        scheme: "Wawona-watchOS",
        platform: "watchOS",
        sdk: "watchos",
        sim_sdk: Some("watchsimulator"),
    },
];

#[derive(clap::Args)]
pub struct Args {
    /// macos, ios, ipados, ios-modeb, tvos, visionos, watchos or android.
    pub target: String,
    /// Build for a device instead of the simulator (macOS is always native).
    #[arg(long)]
    pub device: bool,
    #[arg(long)]
    pub release: bool,
    /// Sign device builds with the team in TEAM_ID (otherwise unsigned).
    #[arg(long)]
    pub sign: bool,
    /// Extra xcodebuild build settings, KEY=VALUE.
    #[arg(long = "set")]
    pub settings: Vec<String>,
}

#[derive(clap::Args)]
pub struct ArchiveArgs {
    pub target: String,
    /// Export the archive: app-store-connect, developer-id, ad-hoc or debugging.
    #[arg(long)]
    pub export: Option<String>,
}

pub fn target(name: &str) -> Result<&'static Target> {
    TARGETS.iter().find(|t| t.name == name).ok_or_else(|| {
        let names: Vec<_> = TARGETS.iter().map(|t| t.name).chain(["android"]).collect();
        anyhow::anyhow!("unknown target {name}; one of {}", names.join(", "))
    })
}

impl Target {
    fn sdk_for(&self, device: bool) -> &'static str {
        if device {
            self.sdk
        } else {
            self.sim_sdk.unwrap_or(self.sdk)
        }
    }

    fn destination(&self, device: bool) -> String {
        if device || self.sim_sdk.is_none() {
            format!("generic/platform={}", self.platform)
        } else {
            format!("generic/platform={} Simulator", self.platform)
        }
    }

    fn derived(&self) -> PathBuf {
        root().join(".build/xcode").join(self.name)
    }

    /// The built .app for one configuration.
    pub fn app(&self, device: bool, release: bool) -> PathBuf {
        let config = if release { "Release" } else { "Debug" };
        let sdk = self.sdk_for(device);
        let dir = if sdk == "macosx" { config.to_string() } else { format!("{config}-{sdk}") };
        self.derived().join("Build/Products").join(dir).join("Wawona.app")
    }

    fn xcodebuild(&self, destination: &str, device: bool, release: bool, sign: bool) -> std::process::Command {
        let mut c = cmd("xcodebuild");
        c.current_dir(root())
            .args(["-project", "Wawona.xcodeproj", "-scheme", self.scheme])
            .args(["-configuration", if release { "Release" } else { "Debug" }])
            .args(["-destination", destination])
            .arg("-derivedDataPath")
            .arg(self.derived());
        if !sign && (device || self.sim_sdk.is_none()) {
            c.args(["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]);
        }
        c
    }
}

fn fetch(t: &Target, device: bool) -> Result<()> {
    let mut sdks = vec![t.sdk_for(device).to_string()];
    // The iOS app embeds the watch companion.
    if t.name == "ios" {
        sdks.push(if device { "watchos" } else { "watchsimulator" }.into());
    }
    deps::get(deps::GetArgs { sdks, nix: false, nix_args: vec![] })
}

/// Gradle runs on JetBrains Runtime 21 (rule wawona-android-jbr): an exported
/// `JAVA_HOME` wins (CI sets JBR), else `ANDROID_STUDIO_JBR`, else Android
/// Studio's embedded runtime.
fn gradle(task: &str) -> Result<()> {
    let mut c = cmd(root().join("gradlew"));
    c.current_dir(root()).arg(task);
    if std::env::var_os("JAVA_HOME").is_none() {
        let home = env_or("HOME", "");
        let studio = [
            std::env::var("ANDROID_STUDIO_JBR").unwrap_or_default(),
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home".into(),
            format!("{home}/Applications/Android Studio.app/Contents/jbr/Contents/Home"),
            "/opt/android-studio/jbr".into(),
        ];
        let jbr = studio.into_iter().filter(|p| !p.is_empty()).find(|p| Path::new(p).join("bin/java").is_file());
        let jbr = jbr.context("no JetBrains Runtime 21: install Android Studio or set ANDROID_STUDIO_JBR")?;
        c.env("JAVA_HOME", jbr);
    }
    run(&mut c)
}

/// The one file with extension `ext` Gradle wrote under android/app/build/outputs/`dir`.
fn gradle_output(dir: &str, ext: &str) -> Result<std::path::PathBuf> {
    let d = root().join("android/app/build/outputs").join(dir);
    let mut found: Vec<_> = std::fs::read_dir(&d)
        .with_context(|| format!("read {}", d.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == ext))
        .collect();
    match found.len() {
        1 => Ok(found.remove(0)),
        n => bail!("{} holds {n} .{ext} files, expected one", d.display()),
    }
}

pub fn build(a: Args) -> Result<()> {
    if a.target == "android" {
        deps::get(deps::GetArgs { sdks: vec!["android".into()], nix: false, nix_args: vec![] })?;
        gradle(if a.release { "assembleRelease" } else { "assembleDebug" })?;
        let v = if a.release { "release" } else { "debug" };
        println!("{}", gradle_output(&format!("apk/{v}"), "apk")?.display());
        return Ok(());
    }
    let t = target(&a.target)?;
    fetch(t, a.device)?;
    run(t.xcodebuild(&t.destination(a.device), a.device, a.release, a.sign).args(&a.settings).arg("build"))?;
    println!("{}", t.app(a.device, a.release).display());
    Ok(())
}

pub fn test(a: Args) -> Result<()> {
    match a.target.as_str() {
        "rust" => run(cmd("cargo").current_dir(root()).args(["test", "--tests", "--no-fail-fast"])),
        "android" => {
            deps::get(deps::GetArgs { sdks: vec!["android".into()], nix: false, nix_args: vec![] })?;
            gradle("testDebugUnitTest")
        }
        "ios" => {
            let t = target("ios")?;
            fetch(t, false)?;
            let sim = std::env::var("EXACT_SIM").unwrap_or_else(|_| "iPhone 17 Pro".into());
            run(t.xcodebuild(&format!("platform=iOS Simulator,name={sim}"), false, false, false).arg("test"))
        }
        other => bail!("cargo xtask test: rust, ios or android (got {other})"),
    }
}

pub fn archive(a: ArchiveArgs) -> Result<()> {
    if a.target == "android" {
        deps::get(deps::GetArgs { sdks: vec!["android".into()], nix: false, nix_args: vec![] })?;
        gradle("bundleRelease")?;
        println!("{}", gradle_output("bundle/release", "aab")?.display());
        return Ok(());
    }
    let t = target(&a.target)?;
    fetch(t, true)?;
    let xcarchive = root().join(".build/archive").join(format!("{}.xcarchive", t.name));
    run(t
        .xcodebuild(&t.destination(true), true, true, a.export.is_some())
        .arg("-archivePath")
        .arg(&xcarchive)
        .arg("archive"))?;
    let Some(method) = a.export else {
        println!("{}", xcarchive.display());
        return Ok(());
    };
    let team = std::env::var("TEAM_ID").unwrap_or_default();
    let plist = root().join(".build/archive").join(format!("{}-{method}.plist", t.name));
    write(
        &plist,
        format!(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \
         \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>\
         <key>method</key><string>{method}</string><key>teamID</key><string>{team}</string>\
         <key>signingStyle</key><string>automatic</string></dict></plist>\n"
        ),
    )?;
    let out = root().join("dist");
    run(cmd("xcodebuild")
        .args(["-exportArchive", "-archivePath"])
        .arg(&xcarchive)
        .arg("-exportOptionsPlist")
        .arg(&plist)
        .arg("-exportPath")
        .arg(&out)
        .arg("-allowProvisioningUpdates"))?;
    println!("{}", out.display());
    Ok(())
}
