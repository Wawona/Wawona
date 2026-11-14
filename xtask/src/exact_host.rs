//! Exact bun host for product Apple/Android builds (no Wawona.xcodeproj).

use crate::backend;
use crate::deps;
use crate::util::{cmd, env_or, root, run};
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};

/// Sibling Exact checkout (…/Wawona/exact) or EXACT_ROOT.
pub fn exact_root() -> Result<PathBuf> {
    if let Ok(p) = std::env::var("EXACT_ROOT") {
        let p = PathBuf::from(p);
        if p.is_dir() {
            return Ok(p);
        }
        bail!("EXACT_ROOT={} is not a directory", p.display());
    }
    let sibling = root().parent().unwrap().join("exact");
    if sibling.is_dir() {
        return Ok(sibling);
    }
    bail!("Exact checkout not found at {} (set EXACT_ROOT)", sibling.display());
}

pub fn app_dir(exact: &Path) -> PathBuf {
    exact.join("apps/wawona")
}

/// Map cargo xtask target → Exact bun flags + deps sdk + backend slice.
pub struct ExactTarget {
    pub name: &'static str,
    pub bun_args: &'static [&'static str],
    pub sdk: &'static str,
    #[allow(dead_code)]
    pub device: bool,
}

pub fn target(name: &str) -> Result<ExactTarget> {
    let t = |name, bun_args, sdk, device| ExactTarget { name, bun_args, sdk, device };
    Ok(match name {
        "macos" => t("macos", &[], "macosx", false),
        "ios" => t("ios", &["--ios"], "iphonesimulator", false),
        "ios-device" => t("ios-device", &["--device"], "iphoneos", true),
        "ipados" => t("ipados", &["--ios"], "iphonesimulator", false),
        "tvos" => t("tvos", &["--tvos"], "appletvsimulator", false),
        "visionos" => t("visionos", &["--visionos"], "xrsimulator", false),
        "watchos" => t("watchos", &["--watchos"], "watchsimulator", false),
        "ios-modeb" => t("ios-modeb", &["--device"], "iphoneos", true),
        other => bail!("unknown Exact target {other}"),
    })
}

/// Stage deps + backend and return WAWONA_LINK_ARGS for Exact swiftc.
pub fn prepare_link(sdk: &str) -> Result<String> {
    deps::get(deps::GetArgs {
        sdks: vec![sdk.into()],
        nix: false,
        nix_args: vec![],
    })?;
    backend::main(backend::Args {
        slice: sdk.into(),
        profile: None,
        out: None,
    })?;
    let lib = root().join(".build/backend").join(sdk).join("lib");
    let deps_lib = root().join(".deps").join(sdk).join("lib");
    let mut args = vec![
        format!("-L{}", lib.display()),
        "-lwawona".into(),
        "-framework".into(),
        "Metal".into(),
        "-framework".into(),
        "QuartzCore".into(),
    ];
    if deps_lib.is_dir() {
        args.insert(0, format!("-L{}", deps_lib.display()));
    }
    Ok(args.join(" "))
}

pub fn bun() -> &'static str {
    "bun"
}

/// Build Exact apps/wawona for one target. Returns the .app path when known.
pub fn build_apple(t: &ExactTarget) -> Result<PathBuf> {
    let exact = exact_root()?;
    let link = prepare_link(t.sdk)?;
    let build_mjs = exact.join("host/apple/build.mjs");
    let mut c = cmd(bun());
    c.current_dir(&exact)
        .arg(&build_mjs)
        .args(t.bun_args)
        .arg("wawona-apple")
        .arg("--no-install")
        .env("WAWONA_LINK_ARGS", &link)
        .env("EXACT_APP_DIR", app_dir(&exact));
    run(&mut c)?;
    let app = find_wawona_app(&exact, t.name)?;
    // Mirror into Wawona .build so Target::app / package / tip stay stable.
    let tip = root().join(".build/exact").join(t.name).join("Wawona.app");
    if tip != app {
        let _ = std::fs::remove_dir_all(&tip);
        std::fs::create_dir_all(tip.parent().unwrap())?;
        run(cmd("ditto").arg(&app).arg(&tip))?;
    }
    Ok(tip)
}

fn find_wawona_app(exact: &Path, name: &str) -> Result<PathBuf> {
    if let Ok(p) = std::env::var("WAWONA_APP_PATH") {
        let p = PathBuf::from(p);
        if p.is_dir() {
            return Ok(p);
        }
    }
    for cand in [
        exact.join("apps/wawona/.exact/Wawona.app"),
        exact.join("target/host-dev/Wawona.app"),
        root().join(".build/exact").join(name).join("Wawona.app"),
    ] {
        if cand.is_dir() {
            return Ok(cand);
        }
    }
    // Exact host-dev: target/clients/<hash>/<bundleId>/<platform>/…/Wawona.app
    // Prefer store id com.aspauldingcode.Wawona over legacy .exact chrome id.
    let clients = exact.join("target/clients");
    if clients.is_dir() {
        let mut store: Option<(std::time::SystemTime, PathBuf)> = None;
        let mut any: Option<(std::time::SystemTime, PathBuf)> = None;
        for e in walkdir::WalkDir::new(&clients).max_depth(12).into_iter().flatten() {
            if e.file_name() != "Wawona.app" || !e.file_type().is_dir() {
                continue;
            }
            let path = e.path().to_path_buf();
            let m = e.metadata().ok().and_then(|m| m.modified().ok());
            let Some(m) = m else { continue };
            let is_store = path.components().any(|c| c.as_os_str() == "com.aspauldingcode.Wawona");
            if is_store && store.as_ref().map(|(t, _)| m > *t).unwrap_or(true) {
                store = Some((m, path.clone()));
            }
            if any.as_ref().map(|(t, _)| m > *t).unwrap_or(true) {
                any = Some((m, path));
            }
        }
        if let Some((_, p)) = store.or(any) {
            return Ok(p);
        }
    }
    walkdir::WalkDir::new(exact.join("apps/wawona"))
        .max_depth(6)
        .into_iter()
        .flatten()
        .find(|e| e.file_name() == "Wawona.app" && e.file_type().is_dir())
        .map(|e| e.into_path())
        .context("Exact build produced no Wawona.app; set WAWONA_APP_PATH")
}

/// Device IPA via Exact --archive.
pub fn archive_ios(out: &Path) -> Result<PathBuf> {
    let exact = exact_root()?;
    let link = prepare_link("iphoneos")?;
    let build_mjs = exact.join("host/apple/build.mjs");
    let mut c = cmd(bun());
    c.current_dir(&exact)
        .arg(&build_mjs)
        .args(["--device", "wawona-apple", "--archive"])
        .arg(out)
        .env("WAWONA_LINK_ARGS", &link)
        .env("EXACT_APP_DIR", app_dir(&exact));
    // Prefer signed when Fastlane/operator set identity+profile; else unsigned for re-sign.
    if std::env::var_os("EXACT_IDENTITY").is_none() || std::env::var_os("EXACT_PROFILE").is_none() {
        c.arg("--unsigned");
    }
    run(&mut c)?;
    if !out.is_file() {
        bail!("Exact archive did not write {}", out.display());
    }
    Ok(out.to_path_buf())
}

/// Exact Android APK or AAB.
pub fn build_android(aab: bool) -> Result<PathBuf> {
    deps::get(deps::GetArgs {
        sdks: vec!["android".into()],
        nix: false,
        nix_args: vec![],
    })?;
    backend::main(backend::Args {
        slice: "android".into(),
        profile: Some("release".into()),
        out: None,
    })?;
    let exact = exact_root()?;
    let flag = if aab { "--aab" } else { "--apk" };
    run(cmd(bun())
        .current_dir(app_dir(&exact))
        .args(["exact.mjs", "android", flag])
        .env("EXACT_APP_DIR", app_dir(&exact)))?;
    let base = exact.join("host/android/app/build/wawona/outputs");
    let (dir, ext) = if aab {
        (base.join("bundle/release"), "aab")
    } else {
        (base.join("apk/release"), "apk")
    };
    let mut found: Vec<_> = std::fs::read_dir(&dir)
        .with_context(|| format!("read {}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == ext))
        .collect();
    match found.len() {
        1 => Ok(found.remove(0)),
        n => bail!("{} holds {n} .{ext} files", dir.display()),
    }
}

pub fn _env_or_exact_sim() -> String {
    env_or("EXACT_SIM", "iPhone 17 Pro")
}
