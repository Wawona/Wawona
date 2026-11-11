//! `cargo xtask tip <platform>`: the tip build every UI proof runs against
//! (rule wawona-test-tip-app). Rebuilds when the product fingerprint of the
//! working tree differs from the stamped one, refuses installed or stale
//! copies, and on macOS clean-launches the binary it built.
//!
//! stdout is `export` lines for `eval "$(cargo xtask tip macos)"`; progress
//! goes to stderr.

use std::path::{Path, PathBuf};
use std::process::Stdio;

use anyhow::{bail, Context, Result};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::util::*;

/// Inputs of the app binary. A commit that touches none of them reuses the
/// stamped build.
const PRODUCT_PATHS: [&str; 13] = [
    "Sources",
    "src",
    "Darwin",
    "Cargo.toml",
    "Cargo.lock",
    "Package.swift",
    "dependencies",
    "Wawona.xcodeproj",
    "xtask",
    "deps.lock",
    "flake.nix",
    "flake.lock",
    "VERSION",
];

#[derive(clap::Args)]
pub struct Args {
    /// macos, ios, tvos, visionos or watchos.
    platform: String,
    /// Build even when the stamp matches.
    #[arg(long, env = "WAWONA_TEST_REBUILD")]
    rebuild: bool,
    /// Build or resolve only; do not relaunch (macOS).
    #[arg(long, env = "WAWONA_TIP_SKIP_LAUNCH")]
    no_launch: bool,
    /// Build nothing: fail unless the stamped tip matches the working tree.
    #[arg(long)]
    check: bool,
    /// Use this app, built from this commit (CI's Gate product), as the tip.
    /// The working tree must be clean.
    #[arg(long, conflicts_with = "check")]
    adopt: Option<PathBuf>,
}

struct Platform {
    scheme: &'static str,
    sdk: &'static str,
    products: &'static str,
    /// simctl runtime identifier fragment and device-name fragment.
    sim: Option<(&'static str, &'static str)>,
}

fn platform(name: &str) -> Result<Platform> {
    let p = |scheme, sdk, products, sim| Platform { scheme, sdk, products, sim };
    Ok(match name.to_lowercase().as_str() {
        "macos" => p("Wawona-macOS", "macosx", "Debug", None),
        "ios" => p("Wawona-iOS", "iphonesimulator", "Debug-iphonesimulator", Some(("iOS", "iPhone"))),
        "tvos" => p("Wawona-tvOS", "appletvsimulator", "Debug-appletvsimulator", Some(("tvOS", "Apple TV"))),
        "visionos" => p("Wawona-visionOS", "xrsimulator", "Debug-xrsimulator", Some(("xrOS", "Apple Vision"))),
        "watchos" => p("Wawona-watchOS", "watchsimulator", "Debug-watchsimulator", Some(("watchOS", "Apple Watch"))),
        other => bail!("unknown platform {other:?} (macos, ios, tvos, visionos, watchos)"),
    })
}

pub fn main(a: Args) -> Result<()> {
    let name = a.platform.to_lowercase();
    let p = platform(&name)?;
    if name != "visionos" {
        refuse_visionos()?;
    }
    let tip = std::env::var("WAWONA_TIP_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("/tmp/wawona-{name}-tip")));
    let dd = tip.join("DerivedData");
    let mut app = dd.join("Build/Products").join(p.products).join("Wawona.app");
    let fp = fingerprint()?;
    if let Some(src) = &a.adopt {
        adopt(src, &app, &tip, &fp)?;
    }
    let fresh = read(tip.join("product-FP")).is_ok_and(|s| s.trim() == fp) && app.is_dir();

    if a.check {
        if !fresh {
            bail!("tip {} is stale or missing; rebuild with `cargo xtask tip {name}`", tip.display());
        }
    } else if a.rebuild || !fresh {
        let udid = p.sim.map(|s| simulator(s.0, s.1)).transpose()?;
        eprintln!("tip: building {} at {}", p.scheme, &fp[..12]);
        let me = std::env::current_exe()?;
        run(cmd(&me).args(["deps", "get", p.sdk]).stdout(Stdio::from(std::io::stderr())))?;
        let dest = match &udid {
            Some(id) => format!("platform={} Simulator,id={id}", sim_platform(&name)),
            None => "platform=macOS,arch=arm64".into(),
        };
        let signing: &[&str] = if p.sim.is_some() {
            &["CODE_SIGNING_ALLOWED=NO", "CODE_SIGN_IDENTITY="]
        } else {
            &["CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
        };
        run(cmd("xcodebuild")
            .arg("-project")
            .arg(root().join("Wawona.xcodeproj"))
            .args(["-scheme", p.scheme, "-configuration", "Debug", "-derivedDataPath"])
            .arg(&dd)
            .args(["-destination", &dest])
            .args(signing)
            .arg("build")
            .stdout(Stdio::from(std::io::stderr())))?;
        if !app.is_dir() {
            app = walkdir::WalkDir::new(dd.join("Build/Products"))
                .into_iter()
                .flatten()
                .find(|e| e.file_name() == "Wawona.app" && e.file_type().is_dir())
                .map(|e| e.into_path())
                .with_context(|| format!("no Wawona.app under {}", dd.display()))?;
        }
        write(tip.join("git-HEAD"), output(cmd("git").current_dir(root()).args(["rev-parse", "HEAD"]))?)?;
        write(tip.join("product-FP"), &fp)?;
        if name == "macos" {
            symlink(&app, tip.join("Wawona.app"))?;
        }
    } else {
        eprintln!("tip: stamp matches the working tree; reusing {}", app.display());
    }
    refuse_stale(&app)?;

    let mut exports = vec![("WAWONA_APP_PATH", app.display().to_string())];
    exports.push(("WAWONA_TIP_ROOT", tip.display().to_string()));
    exports.push(("WAWONA_TIP_PLATFORM", name.clone()));
    if let Some((runtime, device)) = p.sim {
        exports.push(("WAWONA_SIM_UDID", simulator(runtime, device)?));
    } else {
        let rt = wawona_runtime();
        std::fs::create_dir_all(&rt)?;
        if !a.no_launch && !a.check {
            launch(&app, &tip, &rt)?;
        }
        exports.push(("WAWONA_RUNTIME", rt.display().to_string()));
        exports.push(("XDG_RUNTIME_DIR", rt.display().to_string()));
    }
    for (k, v) in &exports {
        println!("{}", export_line(k, v));
    }
    eprintln!("tip: ok {name} app={}", app.display());
    Ok(())
}

fn adopt(src: &Path, app: &Path, tip: &Path, fp: &str) -> Result<()> {
    let dirty = output(cmd("git").current_dir(root()).args(["status", "--porcelain", "--"]).args(PRODUCT_PATHS))?;
    if !dirty.is_empty() {
        bail!("--adopt needs a clean product tree; the app cannot match uncommitted edits");
    }
    refuse_stale(src)?;
    if app.exists() {
        std::fs::remove_dir_all(app)?;
    }
    std::fs::create_dir_all(app.parent().unwrap())?;
    run(cmd("ditto").arg(src).arg(app))?;
    // Workflow artifacts drop the executable bits.
    use std::os::unix::fs::PermissionsExt;
    for dir in ["Contents/MacOS", "Contents/Resources/bin"] {
        for e in walkdir::WalkDir::new(app.join(dir)).into_iter().flatten().filter(|e| e.file_type().is_file()) {
            std::fs::set_permissions(e.path(), std::fs::Permissions::from_mode(0o755))?;
        }
    }
    write(tip.join("git-HEAD"), output(cmd("git").current_dir(root()).args(["rev-parse", "HEAD"]))?)?;
    write(tip.join("product-FP"), fp)?;
    symlink(app, tip.join("Wawona.app"))?;
    eprintln!("tip: adopted {}", src.display());
    Ok(())
}

fn sim_platform(name: &str) -> &'static str {
    match name {
        "ios" => "iOS",
        "tvos" => "tvOS",
        "visionos" => "visionOS",
        _ => "watchOS",
    }
}

/// Hash of the product paths at HEAD plus every staged, unstaged and
/// untracked change under them.
fn fingerprint() -> Result<String> {
    let git = |args: &[&str]| -> Result<Vec<u8>> {
        let out = cmd("git").current_dir(root()).args(args).arg("--").args(PRODUCT_PATHS).output()?;
        if !out.status.success() {
            bail!("git {} failed", args.join(" "));
        }
        Ok(out.stdout)
    };
    let mut h = Sha256::new();
    h.update(git(&["ls-tree", "HEAD"])?);
    h.update(git(&["diff", "HEAD", "--binary"])?);
    for f in String::from_utf8(git(&["ls-files", "--others", "--exclude-standard"])?)?.lines() {
        h.update(f.as_bytes());
        h.update(std::fs::read(root().join(f)).unwrap_or_default());
    }
    Ok(format!("{:x}", h.finalize()))
}

/// The booted simulator of this runtime, else the first available one.
/// `WAWONA_SIM_UDID` wins.
fn simulator(runtime: &str, device: &str) -> Result<String> {
    if let Ok(id) = std::env::var("WAWONA_SIM_UDID") {
        if !id.is_empty() {
            return Ok(id);
        }
    }
    let list: Value = serde_json::from_str(&output(cmd("xcrun").args(["simctl", "list", "devices", "-j"]))?)?;
    let mut candidates = Vec::new();
    for (rt, devices) in list["devices"].as_object().into_iter().flatten() {
        if !rt.contains(&format!(".{runtime}-")) {
            continue;
        }
        for d in devices.as_array().into_iter().flatten() {
            let named = d["name"].as_str().unwrap_or("").contains(device);
            if named && d["isAvailable"].as_bool().unwrap_or(false) {
                let booted = d["state"] == "Booted";
                candidates.push((!booted, d["udid"].as_str().unwrap_or("").to_string()));
            }
        }
    }
    candidates.sort();
    candidates.into_iter().next().map(|c| c.1).with_context(|| format!("no {device} simulator; set WAWONA_SIM_UDID"))
}

/// Fails on an installed copy or an old DerivedData tree (string check
/// first: an absent install path is still forbidden).
pub fn refuse_stale(app: &Path) -> Result<()> {
    let installed = |p: &str| p.starts_with("/Applications/") || p.contains("/Applications/Wawona.app");
    let s = app.display().to_string();
    if installed(&s) {
        bail!("refusing installed app {s}; build the tip (`cargo xtask tip <platform>`)");
    }
    let resolved = app.canonicalize().with_context(|| format!("{s} is not a directory"))?;
    let r = resolved.display().to_string();
    if installed(&r) {
        bail!("refusing installed app {r}");
    }
    let old = ["/build/DerivedData-macos/", "/build/DerivedData-macos-new/", "/Library/Developer/Xcode/DerivedData/"];
    if old.iter().any(|o| r.contains(o)) && !r.contains("/wawona-") {
        bail!("refusing stale DerivedData {r}");
    }
    Ok(())
}

/// Agent-device lists Apple Vision Pro as the first iOS simulator, so an
/// unpinned destination picks it. `WAWONA_TARGET_VISIONOS=1` allows it.
fn refuse_visionos() -> Result<()> {
    if env_flag("WAWONA_TARGET_VISIONOS") {
        return Ok(());
    }
    let vision = regex::Regex::new(r"(?i)vision ?pro|visionos|xros|xrsimulator")?;
    let vars = [
        "AGENT_DEVICE_PLATFORM",
        "AGENT_DEVICE_DEVICE",
        "WAWONA_IOS_SIM",
        "WAWONA_IOS_DEVICE",
        "WAWONA_XCODE_DESTINATION",
        "DESTINATION",
    ];
    let mut seen: Vec<String> = vars.iter().filter_map(|v| std::env::var(v).ok()).collect();
    seen.extend(["agent-device.json", ".xcodebuildmcp/config.yaml"].iter().filter_map(|f| read(root().join(f)).ok()));
    if let Some(c) = seen.iter().find(|c| vision.is_match(c)) {
        bail!("a visionOS target is selected ({c}); set WAWONA_TARGET_VISIONOS=1 only for visionOS work");
    }
    Ok(())
}

/// Clean launch: stop the instance this tool started last, refuse any other
/// running Wawona, then start the tip binary and wait for its socket.
fn launch(app: &Path, tip: &Path, rt: &Path) -> Result<()> {
    let pid_file = tip.join("launch.pid");
    stop_recorded(&pid_file);
    if let Some(others) = try_output(cmd("pgrep").args(["-f", "Wawona.app/Contents/MacOS/Wawona"])) {
        bail!("another Wawona is running (pids {}); quit it, then rerun", others.replace('\n', " "));
    }
    let sock = rt.join("wayland-0");
    let _ = std::fs::remove_file(&sock);
    let mut c = cmd(app.join("Contents/MacOS/Wawona"));
    c.env("WAWONA_RUNTIME", rt).env("XDG_RUNTIME_DIR", rt);
    let log = tip.join("launch.log");
    let pid = detached(c, &log)?;
    write(&pid_file, pid.to_string())?;
    if !wait_for(30, 300, || socket_accepts(&sock)) || !alive(pid) {
        let tail = read(&log).unwrap_or_default();
        let tail: Vec<_> = tail.lines().rev().take(40).collect();
        bail!(
            "tip Wawona (pid {pid}) did not bind {}:\n{}",
            sock.display(),
            tail.into_iter().rev().collect::<Vec<_>>().join("\n")
        );
    }
    eprintln!("tip: launched pid {pid} on {}", sock.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_installed_copies() {
        assert!(refuse_stale(Path::new("/Applications/Wawona.app")).is_err());
        assert!(refuse_stale(Path::new("/Users/x/Applications/Wawona.app")).is_err());
    }

    #[test]
    fn fingerprint_is_stable() {
        assert_eq!(fingerprint().unwrap(), fingerprint().unwrap());
    }
}
