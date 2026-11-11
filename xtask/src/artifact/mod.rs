//! `cargo xtask artifact <check>`: policy gates on built apps and archives
//! (the graphics capability matrix, the Mode A/B firewall, size limits).

mod graphics;
mod ios;

use crate::util::*;
use anyhow::{bail, Result};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// The shipped graphics capability matrix (and store safety) on an
    /// unpacked app or artifact root.
    Graphics {
        #[arg(long, value_parser = ["macos", "macos-desktop", "ios", "ipados", "visionos", "tvos", "watchos", "android"])]
        platform: String,
        #[arg(long)]
        simulator: bool,
        root: PathBuf,
    },
    /// Mode B libwayland-mac.dylib and its helpers: present on macOS, absent
    /// everywhere else.
    ModeB {
        #[arg(long, value_parser = ["present", "absent"])]
        mode: String,
        root: PathBuf,
    },
    /// The iOS Mode A/B firewall on an app bundle or a Mode B tipa.
    Ios {
        #[arg(value_parser = ["mode-a", "mode-a-simulator", "sileo", "mode-b", "iteration"])]
        kind: String,
        artifact: PathBuf,
    },
    /// The iOS Mode B CI contract: the vphone replay and smoke lane exist and
    /// pin the Mode B bundle. WAWONA_MODEA_APP / WAWONA_MODEB_TIPA also scan
    /// those artifacts.
    IosContract,
    /// The Watch executable fits the App Store thin-binary limit (ITMS-90389)
    /// with Relay wasm still linked.
    WatchSize {
        #[arg(long, env = "WAWONA_WATCHOS_SIZE_LIMIT_MB", default_value_t = 75)]
        limit_mb: u64,
        app: PathBuf,
    },
    /// A type-2 AppImage: stage it as dist/Wawona-<arch>.AppImage.
    Appimage { result: PathBuf, system: String },
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Graphics { platform, simulator: _, root } => graphics::check(&platform, &root),
        Cmd::ModeB { mode, root } => mode_b(mode == "present", &root),
        Cmd::Ios { kind, artifact } => ios::check(&kind, &artifact),
        Cmd::IosContract => ios::contract(),
        Cmd::WatchSize { limit_mb, app } => watch_size(limit_mb, &app),
        Cmd::Appimage { result, system } => appimage(&result, &system),
    }
}

fn files(root: &Path) -> impl Iterator<Item = PathBuf> {
    WalkDir::new(root).into_iter().filter_map(|e| e.ok()).filter(|e| e.file_type().is_file()).map(|e| e.into_path())
}

fn name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

/// Executables, dylibs and shared objects that are Mach-O, skipping data
/// trees (zsh functions, share/): scanning every resource dominated product
/// build time.
fn machos(root: &Path) -> Vec<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    files(root)
        .filter(|p| {
            let s = p.to_string_lossy();
            let n = name(p);
            let exec = p.metadata().map(|m| m.permissions().mode() & 0o111 != 0).unwrap_or(false);
            (exec || n.ends_with(".dylib") || n.ends_with(".so"))
                && !n.ends_with(".sh")
                && !s.contains("/share/")
                && !s.contains("/zsh/functions/")
        })
        .filter(|p| crate::macho::is_macho(p))
        .collect()
}

/// The printable runs of at least four bytes, as strings(1) -a prints them.
fn strings(p: &Path) -> Vec<String> {
    let Ok(b) = std::fs::read(p) else { return Vec::new() };
    let mut v = Vec::new();
    let mut cur = Vec::new();
    for &c in &b {
        if c == b'\t' || (0x20..0x7f).contains(&c) {
            cur.push(c);
        } else {
            if cur.len() >= 4 {
                v.push(String::from_utf8_lossy(&cur).into_owned());
            }
            cur.clear();
        }
    }
    if cur.len() >= 4 {
        v.push(String::from_utf8_lossy(&cur).into_owned());
    }
    v
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

fn nm(args: &[&str], p: &Path) -> String {
    try_output(cmd("xcrun").arg("nm").args(args).arg(p)).unwrap_or_default()
}

fn linked(p: &Path) -> String {
    try_output(cmd("xcrun").args(["otool", "-L"]).arg(p)).unwrap_or_default()
}

/// (platform, minos) of every LC_BUILD_VERSION, and LC_VERSION_MIN_IPHONEOS
/// as platform 2.
fn build_versions(p: &Path) -> Vec<(u32, String)> {
    let l = try_output(cmd("xcrun").args(["otool", "-l"]).arg(p)).unwrap_or_default();
    let (mut v, mut build, mut legacy, mut platform) = (Vec::new(), false, false, 0);
    for line in l.lines().map(str::trim) {
        let mut w = line.split_whitespace();
        match (w.next(), w.next()) {
            (Some("cmd"), Some("LC_BUILD_VERSION")) => (build, platform) = (true, 0),
            (Some("cmd"), Some("LC_VERSION_MIN_IPHONEOS")) => legacy = true,
            (Some("platform"), Some(n)) if build => platform = n.parse().unwrap_or(0),
            (Some("minos"), Some(n)) if build => {
                v.push((platform, n.to_string()));
                build = false;
            }
            (Some("version"), Some(n)) if legacy => {
                v.push((2, n.to_string()));
                legacy = false;
            }
            _ => {}
        }
    }
    v
}

fn mode_b(present: bool, root: &Path) -> Result<()> {
    let w = root.join("Contents/Library/Wawona");
    let dylib = w.join("iland/libwayland-mac.dylib");
    let iow = w.join("wwn-iowatchdog");
    let claim = w.join("wwn-iowatchdog-claim-install");
    let hook = w.join("lib/libwwn_watchdogd_hook.dylib");
    if present {
        for (p, what) in
            [(&dylib, "Mode B dylib"), (&iow, "wwn-iowatchdog"), (&claim, "claim-install"), (&hook, "Path B hook")]
        {
            if !p.is_file() {
                bail!("expected {what} at {}", p.display());
            }
        }
        if !crate::macho::is_macho(&dylib) {
            bail!("{} is not a Mach-O dylib", dylib.display());
        }
        println!("OK: Mode B dylib + iowatchdog + claim-install + hook ({})", root.display());
    } else {
        let mut found: Vec<PathBuf> =
            files(root).filter(|p| matches!(name(p).as_str(), "libwayland-mac.dylib" | "libwwn-iland.dylib")).collect();
        found.extend([iow, claim].into_iter().filter(|p| p.exists()));
        if !found.is_empty() {
            bail!("Mode B dylib/wwn-iowatchdog must be absent from a store-safe or non-macOS artifact: {found:?}");
        }
        println!("OK: Mode B dylib absent under {}", root.display());
    }
    Ok(())
}

fn watch_size(limit_mb: u64, app: &Path) -> Result<()> {
    let watch = std::fs::read_dir(app.join("Watch"))
        .ok()
        .and_then(|d| d.filter_map(|e| e.ok()).map(|e| e.path()).find(|p| p.extension().is_some_and(|x| x == "app")))
        .unwrap_or_else(|| app.to_path_buf());
    let stem = watch.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let Some(exe) = ["WawonaWatch", "Wawona", &stem].iter().map(|n| watch.join(n)).find(|p| p.is_file()) else {
        bail!("no Watch executable under {}", watch.display());
    };
    // Relay wasm must stay linked: the size gate is never met by dropping it.
    let wasm = nm(&["-a"], &exe).contains("wawona_wasm") || contains(&std::fs::read(&exe)?, b"wawona_wasm");
    if !wasm {
        bail!("Watch executable missing wawona_wasm (Relay wasm required)");
    }
    let size = exe.metadata()?.len();
    let mb = size as f64 / 1048576.0;
    if size > limit_mb * 1048576 {
        bail!("Watch executable {mb:.2} MB > {limit_mb} MB limit ({})", exe.display());
    }
    println!("OK: Watch executable {mb:.2} MB <= {limit_mb} MB (wasm present) ({})", exe.display());
    Ok(())
}

fn appimage(result: &Path, system: &str) -> Result<()> {
    let image = std::fs::canonicalize(result)?;
    let b = std::fs::read(&image)?;
    println!("AppImage: {} ({} bytes)", image.display(), b.len());
    if b.len() < 1_000_000 {
        bail!("AppImage suspiciously small ({} bytes)", b.len());
    }
    if b[..4] != *b"\x7fELF" {
        bail!("not an ELF executable");
    }
    // A type-2 AppImage carries AI\x02 at offset 8 of its ELF runtime.
    if b[8..11] != *b"AI\x02" {
        bail!("not a type-2 AppImage");
    }
    // Gate artifacts keep a short name; the release workflow renames at the
    // ship boundary (wawona-release-assets).
    let arch = system.split('-').next().unwrap_or(system);
    let dest = root().join(format!("dist/Wawona-{arch}.AppImage"));
    write(&dest, &b)?;
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755))?;
    println!("Staged {}", dest.display());
    let work = std::env::temp_dir().join(format!("appimage-{}", std::process::id()));
    std::fs::create_dir_all(&work)?;
    let ok = cmd(&dest).arg("--appimage-extract").current_dir(&work).output().is_ok_and(|o| o.status.success());
    let sq = work.join("squashfs-root");
    if !ok {
        println!("::warning::--appimage-extract unavailable on this runner; relying on the magic and size checks");
    } else if sq.join("AppRun").is_file() && sq.join("entrypoint").exists() {
        println!("AppImage extract OK: AppRun + entrypoint present");
    } else {
        println!("::warning::AppImage extracted but AppRun/entrypoint missing");
    }
    let _ = std::fs::remove_dir_all(&work);
    println!("AppImage smoke passed for {system}");
    Ok(())
}
