//! `cargo xtask package`: the Mode B wrappers (TrollStore .tipa, Sileo
//! .deb) and the macOS DMG. Mode B artifacts never go to App Store Connect
//! (docs/agent-rules/wawona-release-assets.md).

mod dmg;

use crate::product::{self, target};
use crate::util::{cmd, output, read, root, run, write};
use anyhow::{Context, Result};
use std::io::Write as _;
use std::path::{Path, PathBuf};

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Wawona Mode B as a TrollStore .tipa and rootless and rootful Sileo debs.
    IosModeB,
    /// The one-app Mode B proof (IOMFB, text, JIT) as a .tipa and two debs.
    Demo,
    /// The drag-install macOS DMG, Developer ID signed; notarized with --notarize.
    Dmg(dmg::Args),
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::IosModeB => ios_mode_b(),
        Cmd::Demo => demo(),
        Cmd::Dmg(a) => dmg::main(a),
    }
}

fn version() -> Result<String> {
    Ok(read(root().join("VERSION"))?.trim().to_string())
}

fn dist() -> Result<PathBuf> {
    let d = root().join("dist");
    std::fs::create_dir_all(&d)?;
    Ok(d)
}

fn ldid() -> Result<PathBuf> {
    if let Ok(p) = std::env::var("LDID") {
        return Ok(p.into());
    }
    let vphone = PathBuf::from(std::env::var("HOME")?).join(".vphone/src/vphone-cli/.tools/bin/ldid");
    let found =
        std::env::var_os("PATH").and_then(|p| std::env::split_paths(&p).map(|d| d.join("ldid")).find(|p| p.is_file()));
    found.or_else(|| vphone.is_file().then_some(vphone)).context("ldid not found (install ldid-procursus or set LDID)")
}

/// Sign the main executable with ldid only. A signed .app directory carries
/// _CodeSignature/CodeResources, which TrollStore Lite rejects.
fn ldid_sign(app: &Path, exe: &str, entitlements: &Path) -> Result<()> {
    let mut s = std::ffi::OsString::from("-S");
    s.push(entitlements);
    run(cmd(ldid()?).arg(s).arg(app.join(exe)))?;
    let _ = std::fs::remove_dir_all(app.join("_CodeSignature"));
    Ok(())
}

fn tipa(app: &Path, out: &Path) -> Result<()> {
    let name = app.file_name().unwrap().to_string_lossy().to_string();
    let mut z = zip::ZipWriter::new(std::fs::File::create(out)?);
    for e in walkdir::WalkDir::new(app).sort_by_file_name() {
        let e = e?;
        let rel = Path::new("Payload").join(&name).join(e.path().strip_prefix(app)?);
        let rel = rel.to_string_lossy();
        let meta = e.path().symlink_metadata()?;
        use std::os::unix::fs::PermissionsExt;
        let opts = zip::write::SimpleFileOptions::default().unix_permissions(meta.permissions().mode() & 0o777);
        if meta.file_type().is_symlink() {
            z.add_symlink(rel, std::fs::read_link(e.path())?.to_string_lossy(), opts)?;
        } else if meta.is_dir() {
            z.add_directory(rel, opts)?;
        } else {
            z.start_file(rel, opts)?;
            std::io::copy(&mut std::fs::File::open(e.path())?, &mut z)?;
        }
    }
    z.finish()?;
    eprintln!("wrote {}", out.display());
    Ok(())
}

/// A Debian binary package: an ar archive of debian-binary, control.tar.gz
/// and data.tar.gz (deb(5)). Files are owned by root; there are no
/// maintainer scripts (the vphone guest's /bin has no sh).
fn deb(control: &str, prefix: &str, app: &Path, out: &Path) -> Result<()> {
    let control_tar = targz(|t| {
        let mut h = tar::Header::new_gnu();
        h.set_size(control.len() as u64);
        h.set_mode(0o644);
        h.set_cksum();
        t.append_data(&mut h, "./control", control.as_bytes())
    })?;
    let data_tar = targz(|t| {
        let dest = Path::new(".").join(prefix).join(app.file_name().unwrap());
        t.append_dir_all(dest, app)
    })?;
    let mut f = std::fs::File::create(out)?;
    f.write_all(b"!<arch>\n")?;
    for (name, body) in [("debian-binary", &b"2.0\n"[..]), ("control.tar.gz", &control_tar), ("data.tar.gz", &data_tar)]
    {
        write!(f, "{name:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n", 0, 0, 0, "100644", body.len())?;
        f.write_all(body)?;
        if body.len() % 2 == 1 {
            f.write_all(b"\n")?;
        }
    }
    eprintln!("wrote {}", out.display());
    Ok(())
}

fn targz(
    fill: impl FnOnce(&mut tar::Builder<flate2::write::GzEncoder<Vec<u8>>>) -> std::io::Result<()>,
) -> Result<Vec<u8>> {
    let mut t = tar::Builder::new(flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::best()));
    t.mode(tar::HeaderMode::Deterministic);
    t.follow_symlinks(false);
    fill(&mut t)?;
    Ok(t.into_inner()?.finish()?)
}

/// Rootless installs under /var/jb (iphoneos-arm64); rootful at /
/// (iphoneos-arm). They are different trees, not a renamed archive.
const SCHEMES: [(&str, &str, &str); 2] =
    [("rootless", "iphoneos-arm64", "var/jb/Applications"), ("rootful", "iphoneos-arm", "Applications")];

/// Leftovers no Mode B wrapper ships: Relay owns VMs, containers and wasm,
/// and the guest disks wait until Relay boots NixOS.
const MODE_B_STRIP: &[&str] = &[
    "_CodeSignature",
    "wwn-qemu-run",
    "share/qemu",
    "wawona-mobile-guest",
    "wawona-container-guest",
    "wawona-rootfs/usr/share/zsh/Completion/Unix/Command/_qemu",
];

/// Build Wawona-iOS-ModeB at one deployment floor and stage it ldid-signed.
fn mode_b_app(floor: &str, stage: &Path) -> Result<()> {
    product::build(product::Args {
        target: "ios-modeb".into(),
        device: true,
        release: true,
        sign: false,
        settings: vec![format!("IPHONEOS_DEPLOYMENT_TARGET={floor}")],
    })?;
    let _ = std::fs::remove_dir_all(stage);
    std::fs::create_dir_all(stage.parent().unwrap())?;
    run(cmd("ditto").arg(target("ios-modeb")?.app(true, true)).arg(stage))?;
    crate::xcode::make_writable(stage)?;
    for p in MODE_B_STRIP {
        let p = stage.join(p);
        let _ = if p.is_dir() { std::fs::remove_dir_all(&p) } else { std::fs::remove_file(&p) };
    }
    if let Ok(rd) = std::fs::read_dir(stage.join("Frameworks")) {
        for e in rd.flatten().filter(|e| e.file_name().to_string_lossy().starts_with("qemu")) {
            std::fs::remove_dir_all(e.path()).or_else(|_| std::fs::remove_file(e.path()))?;
        }
    }
    let ents = root().join("src/resources/app-bundle/Wawona-ModeB.entitlements");
    ldid_sign(stage, "Wawona", &ents)?;
    if stage.join("wwn-vsock-peer").is_file() {
        ldid_sign(stage, "wwn-vsock-peer", &ents)?;
    }
    Ok(())
}

/// TrollStore installs from iOS 14, Sileo from iOS 13
/// (docs/agent-rules/wawona-ios-min-os.md), so each wrapper gets its own build.
fn ios_mode_b() -> Result<()> {
    let (v, out) = (version()?, dist()?);
    let stage = root().join(".build/package/ios-mode-b/Wawona.app");
    mode_b_app("13.0", &stage)?;
    for (scheme, arch, prefix) in SCHEMES {
        let control = format!(
            "Package: com.aspauldingcode.wawona.modeb\nName: Wawona\nVersion: {v}\nArchitecture: {arch}\n\
             Maintainer: Wawona <hello@wawona.io>\nDescription: Wawona Mode B ({scheme}). JIT + IOMFB Desktop. Not App Store.\n\
             Section: Applications\nPriority: optional\nDepends: firmware (>= 13.0)\nHomepage: https://wawona.io\n"
        );
        deb(&control, prefix, &stage, &out.join(format!("Wawona-{v}-iOS-arm64-{scheme}.deb")))?;
    }
    mode_b_app("14.0", &stage)?;
    tipa(&stage, &out.join(format!("Wawona-{v}-iOS-arm64.tipa")))
}

const DEMO: &str = "WawonaModeBDemo";
const DEMO_ID: &str = "com.aspauldingcode.wawona.modeb.demo";

/// Each reinstall needs a new CFBundleVersion: the last build recorded next
/// to the artifacts, plus one (BUILD overrides).
fn demo_build(out: &Path) -> Result<u64> {
    if let Ok(b) = std::env::var("BUILD") {
        return Ok(b.parse()?);
    }
    let prev = read(out.join(".modeb-demo-build")).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    Ok(prev + 1)
}

fn demo() -> Result<()> {
    let out = std::env::var("OUT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| root().join(".agent-device/test-artifacts/dmabuf/vphone-jb"));
    std::fs::create_dir_all(&out)?;
    let (v, build) = (version()?, demo_build(&out)?);
    let src = root().join("scripts/modeb-demo");
    let stage = root().join(".build/package/demo");
    let app = stage.join(format!("{DEMO}.app"));
    let _ = std::fs::remove_dir_all(&stage);
    std::fs::create_dir_all(&app)?;
    let sdk = output(cmd("xcrun").args(["--sdk", "iphoneos", "--show-sdk-path"]))?;
    let xcrun = |tool: &str| {
        let mut c = cmd("xcrun");
        c.args(["--sdk", "iphoneos", tool]);
        c
    };
    run(xcrun("clang")
        .args(["-arch", "arm64", "-isysroot", &sdk, "-miphoneos-version-min=15.0", "-O2"])
        .arg(format!("-I{}", src.display()))
        .arg("-c")
        .arg(src.join("modeb_demo_support.c"))
        .arg("-o")
        .arg(stage.join("support.o")))?;
    let swift = ["-sdk", &sdk, "-target", "arm64-apple-ios15.0"];
    run(xcrun("swiftc")
        .args(swift)
        .args(["-parse-as-library", "-O", "-emit-object", "-wmo", "-import-objc-header"])
        .arg(src.join("modeb-demo-Bridging-Header.h"))
        .arg(format!("-I{}", src.display()))
        .arg(src.join("ModeBDemoApp.swift"))
        .arg(src.join("ModeBDemoHost.swift"))
        .arg("-o")
        .arg(stage.join("demo.o")))?;
    run(xcrun("swiftc")
        .args(swift)
        .arg(stage.join("support.o"))
        .arg(stage.join("demo.o"))
        .args(
            ["UIKit", "Foundation", "CoreGraphics", "QuartzCore", "IOSurface", "IOKit"]
                .iter()
                .flat_map(|f| ["-framework", f]),
        )
        .arg("-o")
        .arg(app.join(DEMO)))?;
    write(app.join("Info.plist"), demo_plist(&v, build))?;
    ldid_sign(&app, DEMO, &src.join("demo.entitlements"))?;
    tipa(&app, &out.join(format!("{DEMO}-{v}-iOS-arm64.tipa")))?;
    write(out.join(".modeb-demo-build"), format!("{build}\n"))?;
    let maint = "Alex Spaulding <aspauldingcode@gmail.com>";
    for (scheme, arch, prefix) in SCHEMES {
        let control = format!(
            "Package: {DEMO_ID}\nName: Wawona Mode B Demo\nVersion: {v}-{build}\nArchitecture: {arch}\n\
             Maintainer: {maint}\nAuthor: {maint}\nDescription: Mode B framebuffer and JIT demo ({scheme}). \
             IOMFB plasma, Hello text, fib HUD. Not App Store.\nSection: Utilities\nPriority: optional\n\
             Depends: firmware (>= 15.0)\nHomepage: https://wawona.io\nTag: role::developer\n"
        );
        let deb_path = out.join(format!("wawona-modeb-demo_{v}-{build}_{arch}.deb"));
        deb(&control, prefix, &app, &deb_path)?;
        let repo = root().join("../repo.wawona.io/debs");
        if repo.is_dir() {
            std::fs::copy(&deb_path, repo.join(deb_path.file_name().unwrap()))?;
        }
    }
    eprintln!("CFBundleShortVersionString={v} CFBundleVersion={build}");
    Ok(())
}

fn demo_plist(v: &str, build: u64) -> String {
    let kv = |k: &str, s: &str| format!("<key>{k}</key><string>{s}</string>");
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \
         \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>{}{}{}{}{}{}{}{}\
         <key>LSRequiresIPhoneOS</key><true/><key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>\
         <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>\
         <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>\
         <key>LSApplicationQueriesSchemes</key><array><string>apple-magnifier</string></array>\
         <key>CFBundleURLTypes</key><array><dict>{}<key>CFBundleURLSchemes</key><array><string>wawona-modeb-demo</string></array></dict></array>\
         </dict></plist>\n",
        kv("CFBundleExecutable", DEMO), kv("CFBundleIdentifier", DEMO_ID), kv("CFBundleName", DEMO),
        kv("CFBundleDisplayName", "Wawona Mode B Demo"), kv("CFBundlePackageType", "APPL"),
        kv("CFBundleShortVersionString", v), kv("CFBundleVersion", &build.to_string()),
        kv("MinimumOSVersion", "15.0"), kv("CFBundleURLName", DEMO_ID),
    )
}
