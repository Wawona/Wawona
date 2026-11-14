//! `cargo xtask tip <platform>`: Exact tip build (rule wawona-test-tip-app).

use std::path::{Path, PathBuf};
use std::process::Stdio;

use anyhow::{bail, Context, Result};
use sha2::{Digest, Sha256};

use crate::exact_host;
use crate::util::*;

const PRODUCT_PATHS: [&str; 11] = [
    "Sources",
    "src",
    "Darwin",
    "Cargo.toml",
    "Cargo.lock",
    "dependencies",
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
    #[arg(long, env = "WAWONA_TEST_REBUILD")]
    rebuild: bool,
    #[arg(long, env = "WAWONA_TIP_SKIP_LAUNCH")]
    no_launch: bool,
    #[arg(long)]
    check: bool,
    #[arg(long, conflicts_with = "check")]
    adopt: Option<PathBuf>,
}

pub fn main(a: Args) -> Result<()> {
    let name = a.platform.to_lowercase();
    if name != "visionos" {
        refuse_visionos()?;
    }
    let tip = std::env::var("WAWONA_TIP_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(format!("/tmp/wawona-{name}-tip")));
    let app_link = tip.join("Wawona.app");
    let fp = fingerprint()?;
    if let Some(src) = &a.adopt {
        adopt(src, &app_link, &tip, &fp)?;
    }
    let fresh = read(tip.join("product-FP")).is_ok_and(|s| s.trim() == fp) && app_link.is_dir();

    if a.check {
        if !fresh {
            bail!("tip {} is stale or missing; rebuild with `cargo xtask tip {name}`", tip.display());
        }
    } else if a.rebuild || !fresh {
        eprintln!("tip: Exact building {name} at {}", &fp[..12.min(fp.len())]);
        let t = exact_host::target(match name.as_str() {
            "macos" => "macos",
            "ios" => "ios",
            "tvos" => "tvos",
            "visionos" => "visionos",
            "watchos" => "watchos",
            _ => unreachable!(),
        })?;
        let built = exact_host::build_apple(&t)?;
        std::fs::create_dir_all(&tip)?;
        // Replace tip app with Exact product.
        if app_link.exists() {
            let _ = std::fs::remove_dir_all(&app_link);
            let _ = std::fs::remove_file(&app_link);
        }
        // Copy tree (Exact build dir must stay; tip needs a stable path).
        run(cmd("cp").args(["-R", &built.display().to_string(), &app_link.display().to_string()]))?;
        write(tip.join("git-HEAD"), output(cmd("git").current_dir(root()).args(["rev-parse", "HEAD"]))?)?;
        write(tip.join("product-FP"), &fp)?;
        // Fingerprint Exact Present module too.
        if let Ok(exact) = exact_host::exact_root() {
            let _ = write(
                tip.join("exact-HEAD"),
                output(cmd("git").current_dir(&exact).args(["rev-parse", "HEAD"]))?,
            );
        }
    } else {
        eprintln!("tip: stamp matches; reusing {}", app_link.display());
    }
    refuse_stale(&app_link)?;

    let mut exports = vec![
        ("WAWONA_APP_PATH", app_link.display().to_string()),
        ("WAWONA_TIP_ROOT", tip.display().to_string()),
        ("WAWONA_TIP_PLATFORM", name.clone()),
    ];
    if name != "macos" {
        let (runtime, device) = match name.as_str() {
            "ios" => ("iOS", "iPhone"),
            "tvos" => ("tvOS", "Apple TV"),
            "visionos" => ("xrOS", "Apple Vision"),
            "watchos" => ("watchOS", "Apple Watch"),
            _ => ("iOS", "iPhone"),
        };
        exports.push(("WAWONA_SIM_UDID", simulator(runtime, device)?));
    } else {
        let rt = wawona_runtime();
        std::fs::create_dir_all(&rt)?;
        if !a.no_launch && !a.check {
            launch(&app_link, &tip, &rt)?;
        }
        exports.push(("WAWONA_RUNTIME", rt.display().to_string()));
        exports.push(("XDG_RUNTIME_DIR", rt.display().to_string()));
    }
    for (k, v) in exports {
        println!("export {k}={v}");
    }
    Ok(())
}

fn fingerprint() -> Result<String> {
    let mut h = Sha256::new();
    for rel in PRODUCT_PATHS {
        let p = root().join(rel);
        if p.is_dir() {
            for e in walkdir::WalkDir::new(&p).into_iter().flatten() {
                if e.file_type().is_file() {
                    h.update(e.path().to_string_lossy().as_bytes());
                    if let Ok(bytes) = std::fs::read(e.path()) {
                        h.update(&bytes);
                    }
                }
            }
        } else if p.is_file() {
            h.update(std::fs::read(&p)?);
        }
    }
    if let Ok(exact) = exact_host::exact_root() {
        for rel in ["apps/wawona/app.contract", "apps/wawona/app.json", "apps/wawona/modules"] {
            let p = exact.join(rel);
            if p.is_dir() {
                for e in walkdir::WalkDir::new(&p).into_iter().flatten() {
                    if e.file_type().is_file() {
                        h.update(e.path().to_string_lossy().as_bytes());
                        if let Ok(bytes) = std::fs::read(e.path()) {
                            h.update(&bytes);
                        }
                    }
                }
            } else if p.is_file() {
                h.update(rel.as_bytes());
                h.update(std::fs::read(&p)?);
            }
        }
    }
    Ok(format!("{:x}", h.finalize()))
}

fn refuse_stale(app: &Path) -> Result<()> {
    let s = app.display().to_string();
    if s.contains("/Applications/") {
        bail!("refuse installed app {}; tip Exact build only", s);
    }
    if !app.is_dir() {
        bail!("missing tip app {}", s);
    }
    Ok(())
}

fn adopt(src: &Path, app: &Path, tip: &Path, fp: &str) -> Result<()> {
    std::fs::create_dir_all(tip)?;
    if app.exists() {
        let _ = std::fs::remove_dir_all(app);
    }
    run(cmd("cp").args(["-R", &src.display().to_string(), &app.display().to_string()]))?;
    write(tip.join("product-FP"), fp)?;
    write(tip.join("git-HEAD"), output(cmd("git").current_dir(root()).args(["rev-parse", "HEAD"]))?)?;
    Ok(())
}

fn refuse_visionos() -> Result<()> {
    if std::env::var_os("SIMULATOR_DEVICE_NAME")
        .is_some_and(|n| n.to_string_lossy().contains("Vision"))
    {
        bail!("refuse Vision Pro simulator for non-visionos tip");
    }
    Ok(())
}

fn simulator(runtime: &str, device: &str) -> Result<String> {
    let raw = output(cmd("xcrun").args(["simctl", "list", "devices", "available", "-j"]))?;
    let v: serde_json::Value = serde_json::from_str(&raw)?;
    let devices = v
        .get("devices")
        .and_then(|d| d.as_object())
        .context("simctl devices json")?;
    for (rt, list) in devices {
        if !rt.contains(runtime) {
            continue;
        }
        if let Some(arr) = list.as_array() {
            for d in arr {
                let name = d.get("name").and_then(|n| n.as_str()).unwrap_or("");
                let udid = d.get("udid").and_then(|n| n.as_str()).unwrap_or("");
                if name.contains(device) && !udid.is_empty() {
                    return Ok(udid.into());
                }
            }
        }
    }
    bail!("no {runtime} simulator matching {device}")
}

fn wawona_runtime() -> PathBuf {
    PathBuf::from(format!("/tmp/wawona-{}", unsafe { libc::getuid() }))
}

fn launch(app: &Path, tip: &Path, rt: &Path) -> Result<()> {
    let _ = cmd("pkill").args(["-f", &format!("{}/", tip.display())]).status();
    std::fs::create_dir_all(rt)?;
    let exe = app.join("Contents/MacOS").read_dir()?.flatten().next().map(|e| e.path());
    let exe = exe.context("no MacOS executable in tip app")?;
    let mut c = cmd(&exe);
    c.env("XDG_RUNTIME_DIR", rt)
        .env("WAWONA_TIP", "1")
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // Detach.
    use std::os::unix::process::CommandExt;
    unsafe {
        c.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    c.spawn().context("launch tip")?;
    Ok(())
}
