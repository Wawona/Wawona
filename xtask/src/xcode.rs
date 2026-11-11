//! `cargo xtask xcode <phase>`: the Wawona.xcodeproj run-script build phases.
//!
//! stamp     writes CURRENT_PROJECT_VERSION to .build/wwn-build-number.xcconfig
//! prebuild  builds the slice's backend and stages what the link step reads
//!           from DERIVED_FILE_DIR
//! embed     copies the slice's bundle tree into the built app and makes it
//!           self-contained

use crate::util::*;
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};

#[derive(clap::Subcommand)]
pub enum Cmd {
    Stamp,
    Prebuild,
    Embed,
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Stamp => stamp(),
        Cmd::Prebuild => prebuild(),
        Cmd::Embed => embed(),
    }
}

fn var(k: &str) -> Result<String> {
    std::env::var(k).with_context(|| format!("{k} is unset; run this as an Xcode build phase"))
}

/// The backend slice: the Mode B target builds its own iphoneos backend.
fn slice() -> Result<String> {
    let p = var("PLATFORM_NAME")?;
    Ok(if p == "iphoneos" && var("TARGET_NAME")? == "Wawona-iOS-ModeB" { "iphoneos-modeb".into() } else { p })
}

/// Written under .build/ so wwn-version.xcconfig can include it before Xcode
/// resolves build settings; a DERIVED_FILE_DIR include is read too late.
fn stamp() -> Result<()> {
    let bn = ["WAWONA_BUILD_NUMBER", "GITHUB_RUN_NUMBER"]
        .iter()
        .find_map(|k| std::env::var(k).ok().filter(|v| !v.is_empty()))
        .unwrap_or_else(|| {
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs().to_string()
        });
    write(
        root().join(".build/wwn-build-number.xcconfig"),
        format!("// Written by cargo xtask xcode stamp.\nCURRENT_PROJECT_VERSION = {bn}\n"),
    )
}

fn prebuild() -> Result<()> {
    crate::verify::calver()?;
    let root = root();
    let derived = PathBuf::from(var("DERIVED_FILE_DIR")?);
    let platform = var("PLATFORM_NAME")?;
    let slice = slice()?;
    let deps = root.join(".deps").join(crate::slices::deps_name(&slice));
    std::fs::create_dir_all(&derived)?;

    crate::backend::main(crate::backend::Args { slice: slice.clone(), profile: None, out: None })?;
    // Copy, never link: Xcode's dependency scan stats the input.
    std::fs::copy(root.join(".build/backend").join(&slice).join("lib/libwawona.a"), derived.join("libwawona.a"))?;

    if platform == "macosx" {
        return libghostty(&root, &derived);
    }

    // App Store Connect rejects libSystem's private ___progname, which weston
    // and fontconfig reach; device builds force-load this replacement first.
    if matches!(platform.as_str(), "iphoneos" | "appletvos" | "xros") {
        let o = derived.join("wawona-getprogname.o");
        // No -m*-version-min: visionOS clang rejects it, and the stub uses no SDK API.
        run(cmd("xcrun")
            .args(["--sdk", &platform, "clang", "-c"])
            .arg(root.join("src/platform/ios/WWNGetprognameStub.c"))
            .args(["-isysroot", &var("SDKROOT")?, "-arch", "arm64", "-fPIC", "-O2", "-o"])
            .arg(&o))?;
        run(cmd("xcrun")
            .args(["--sdk", &platform, "libtool", "-static", "-o"])
            .arg(derived.join("libwawona-getprogname.a"))
            .arg(&o))?;
    }

    // zsh and fastfetch collide with each other and with OpenSSH; ld-prime
    // has no -multiply_defined suppress and a dylib is not App Store
    // compliant. Keep only their entry points global.
    privatize(&platform, &deps.join("zsh/lib/libwawona-zsh.a"), &derived.join("libwawona-zsh.a"), "_wawona_zsh_main")?;
    privatize(&platform, &deps.join("fastfetch/lib/libfastfetch.a"), &derived.join("libfastfetch.a"), "_fastfetch_main")
}

/// TerminalMetalPresent paints unless WAWONA_LINK_LIBGHOSTTY=1 and
/// `cargo xtask deps get libghostty-macos` staged Zig GhosttyLib. Bridge.c reads
/// the define from a header; the link flags go under .build/, which
/// wwn-version.xcconfig includes.
fn libghostty(root: &Path, derived: &Path) -> Result<()> {
    let lg = root.join(".deps/libghostty-macos");
    let on =
        std::env::var("WAWONA_LINK_LIBGHOSTTY").as_deref() == Ok("1") && lg.join("lib/libghostty-internal.a").exists();
    let (header, xcconfig) = if on {
        std::fs::copy(lg.join("include/ghostty.h"), derived.join("ghostty.h"))?;
        let fw = "Metal MetalKit QuartzCore CoreText CoreGraphics CoreVideo CoreImage IOKit Security \
                  UniformTypeIdentifiers Carbon GameController IOSurface SystemConfiguration Network";
        let fw: String = fw.split_whitespace().map(|f| format!(" -framework {f}")).collect();
        (
            "#define WAWONA_HAS_LIBGHOSTTY 1\n#define GHOSTTY_STATIC 1\n".to_string(),
            format!(
                "HEADER_SEARCH_PATHS = $(inherited) {0}/include\nOTHER_LDFLAGS = $(inherited) -force_load {0}/lib/libghostty-internal.a -lc++ -lz -lbz2{fw}\n",
                lg.display()
            ),
        )
    } else {
        (String::new(), String::new())
    };
    write(derived.join("wwn_ghostty_host_config.h"), header)?;
    write(derived.join("wwn-libghostty-link.xcconfig"), &xcconfig)?;
    write(root.join(".build/wwn-libghostty-link.xcconfig"), &xcconfig)
}

/// `ld -r` the archive into one object with only `export` global. The merged
/// object carries the app's floor: an SDK-default one makes clang emit
/// _objc_release_xN, which dyld before iOS 16 cannot bind.
fn privatize(platform: &str, src: &Path, dst: &Path, export: &str) -> Result<()> {
    let (os, var_name) = match platform.trim_end_matches("simulator").trim_end_matches("os") {
        "iphone" => ("ios", "IPHONEOS_DEPLOYMENT_TARGET"),
        "appletv" => ("tvos", "TVOS_DEPLOYMENT_TARGET"),
        "watch" => ("watchos", "WATCHOS_DEPLOYMENT_TARGET"),
        "xr" => ("xros", "XROS_DEPLOYMENT_TARGET"),
        _ => bail!("no ld platform for {platform}"),
    };
    let os = if platform.ends_with("simulator") { format!("{os}-simulator") } else { os.to_string() };
    let min = var(var_name)?;
    // Xcode builds the iOS and watchOS targets in parallel.
    let tmp = root().join("target/wawona-privatize").join(platform).join(export);
    std::fs::create_dir_all(&tmp)?;
    let merged = tmp.join("merged.o");
    run(cmd("ld")
        .args(["-r", "-arch", "arm64", "-platform_version", &os, &min, &min, "-all_load"])
        .arg(src)
        .arg("-o")
        .arg(&merged))?;
    write(tmp.join("exports"), format!("{export}\n"))?;
    run(cmd("nmedit").arg("-s").arg(tmp.join("exports")).arg(&merged))?;
    run(cmd("libtool").arg("-static").arg(&merged).arg("-o").arg(dst))
}

fn embed() -> Result<()> {
    let root = root();
    let platform = var("PLATFORM_NAME")?;
    let target = var("TARGET_NAME")?;
    let deps = root.join(".deps").join(crate::slices::deps_name(&slice()?));
    let build = PathBuf::from(var("TARGET_BUILD_DIR")?);
    let contents = build.join(var("CONTENTS_FOLDER_PATH")?);
    let app = build.join(var("WRAPPER_NAME")?);

    copy_bundle(&deps, &deps.join("bundle"), &contents)?;

    // App Store Connect treats an executable file as an unsigned code object.
    let rootfs = contents.join("wawona-rootfs");
    for e in walkdir::WalkDir::new(&rootfs).into_iter().flatten().filter(|e| e.file_type().is_file()) {
        set_mode(e.path(), 0o644)?;
    }

    // Relay owns the CPU; no QEMU or UTM engine ships (docs/wwn-repo-dag.md).
    let qemu: Vec<_> = walkdir::WalkDir::new(&app)
        .into_iter()
        .flatten()
        .map(|e| e.path().to_path_buf())
        .filter(|p| {
            let n = p.file_name().unwrap_or_default().to_string_lossy().to_lowercase();
            n == "wwn-qemu-run"
                || n.starts_with("qemu-system-")
                || n.starts_with("libqemu")
                || (n.starts_with("qemu-") && n.ends_with(".framework"))
                || p.to_string_lossy().contains("/share/qemu/")
        })
        .collect();
    if !qemu.is_empty() {
        bail!("QEMU/UTM artifacts are forbidden in Wawona bundles: {qemu:?}");
    }

    // The source Info.plist is shared. exportArchive and ASC reject iOS-only
    // keys on the other platforms (wawona#138), and a watch build listing
    // them is accepted and then silently discarded.
    if !matches!(target.as_str(), "Wawona-iOS" | "Wawona-iPadOS" | "Wawona-iOS-ModeB") {
        let plist = build.join(var("INFOPLIST_PATH")?);
        for key in ["LSRequiresIPhoneOS", "UISupportedInterfaceOrientations~ipad", "MinimumOSVersion~ipad"] {
            let _ = try_output(cmd("/usr/libexec/PlistBuddy").arg("-c").arg(format!("Delete :{key}")).arg(&plist));
        }
    }

    if platform.ends_with("simulator") {
        // Store modes and com.apple.provenance make simctl install fail with EACCES.
        return run(cmd("xattr").arg("-cr").arg(&app));
    }
    if platform == "macosx" {
        return crate::macho::bundle_dylibs(&deps, &contents);
    }
    Ok(())
}

/// Copies the slice's bundle tree. Links into the store become copies (a
/// packed slice keeps store paths as `<slice>/store/<hash-name>`); relative
/// links (the macOS modeb-* aliases) stay links.
fn copy_bundle(deps: &Path, src: &Path, contents: &Path) -> Result<()> {
    for e in walkdir::WalkDir::new(src).min_depth(1) {
        let e = e?;
        let rel = e.path().strip_prefix(src)?;
        let dst = contents.join(rel);
        let ft = e.file_type();
        if ft.is_dir() {
            continue;
        }
        if let Some(d) = dst.parent() {
            std::fs::create_dir_all(d)?;
        }
        if dst.symlink_metadata().is_ok() {
            if dst.is_dir() && !dst.symlink_metadata()?.file_type().is_symlink() {
                std::fs::remove_dir_all(&dst)?;
            } else {
                std::fs::remove_file(&dst)?;
            }
        }
        if ft.is_symlink() {
            let t = std::fs::read_link(e.path())?;
            if t.is_absolute() {
                copy_resolved(&crate::macho::resolve(deps, &t), &dst)?;
            } else {
                std::os::unix::fs::symlink(&t, &dst)?;
            }
        } else {
            std::fs::copy(e.path(), &dst)?;
            make_writable(&dst)?;
        }
    }
    Ok(())
}

fn copy_resolved(from: &Path, to: &Path) -> Result<()> {
    if from.is_dir() {
        for e in walkdir::WalkDir::new(from).follow_links(true) {
            let e = e?;
            let d = to.join(e.path().strip_prefix(from)?);
            if e.file_type().is_dir() {
                std::fs::create_dir_all(&d)?;
            } else {
                std::fs::copy(e.path(), &d)?;
                make_writable(&d)?;
            }
        }
        Ok(())
    } else {
        std::fs::copy(from, to).with_context(|| format!("copy {}", from.display()))?;
        make_writable(to)
    }
}

fn set_mode(p: &Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode))?;
    Ok(())
}

pub fn make_writable(p: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let m = std::fs::metadata(p)?.permissions().mode();
    set_mode(p, m | 0o200)
}
