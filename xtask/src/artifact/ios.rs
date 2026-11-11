//! The iOS Mode A/B firewall (wawona-ios-mode-b-channels) and the minimum-OS
//! contract (wawona-ios-min-os): store builds target iOS 15.0.

use super::*;
use std::io::Read;

const MODE_A_ID: &str = "com.aspauldingcode.Wawona";
const MODE_B_ID: &str = "com.aspauldingcode.Wawona.ModeB";
const MINIMUM: &str = "15.0";

pub fn plist_string(p: &Path, key: &str) -> Option<String> {
    plist::Value::from_file(p).ok()?.as_dictionary()?.get(key)?.as_string().map(str::to_string)
}

fn version_le(a: &str, b: &str) -> bool {
    let v = |s: &str| {
        s.split('.').map(|n| n.parse::<u32>().unwrap_or(0)).chain(std::iter::repeat(0)).take(2).collect::<Vec<_>>()
    };
    v(a) <= v(b)
}

fn require_minimum(exe: &Path, expected: &str) -> Result<()> {
    match build_versions(exe).first() {
        Some((_, m)) if m == expected => Ok(()),
        other => bail!("expected iOS minimum {expected}, got {:?}", other.map(|(_, m)| m)),
    }
}

/// Info.plist can advertise a lower floor than an embedded Mach-O requires:
/// check every iOS slice (watchOS companion slices keep their own floor).
fn dependency_minima(app: &Path, platform: u32, maximum: &str) -> Result<()> {
    for p in files(app).filter(|p| name(p).ends_with(".dylib")) {
        // A failed Swift runtime copy can leave an empty dylib that has no
        // load commands to check.
        if p.metadata()?.len() == 0 || !crate::macho::is_macho(&p) {
            bail!("embedded dylib is empty or not Mach-O: {}", p.display());
        }
    }
    let frameworks = files(app).filter(|p| p.to_string_lossy().contains("/Frameworks/") && crate::macho::is_macho(p));
    for p in machos(app).into_iter().chain(frameworks) {
        for (plat, min) in build_versions(&p).into_iter().filter(|(pl, _)| matches!(pl, 2 | 7)) {
            if plat != platform {
                bail!("wrong embedded iOS platform {plat} (expected {platform}): {}", p.display());
            }
            if !version_le(&min, maximum) {
                bail!("dependency requires iOS {min} (maximum {maximum}): {}", p.display());
            }
        }
    }
    Ok(())
}

fn qemu(path: &str) -> bool {
    let l = path.to_lowercase();
    let n = l.rsplit('/').next().unwrap_or(&l);
    n == "wwn-qemu-run"
        || n.starts_with("qemu-system-")
        || n.starts_with("libqemu")
        || (n.starts_with("qemu-") && n.ends_with(".framework"))
        || l.contains("/share/qemu/")
        || l.contains("/frameworks/qemu")
}

pub fn check(kind: &str, artifact: &Path) -> Result<()> {
    if !artifact.exists() {
        bail!("artifact not found: {}", artifact.display());
    }
    match kind {
        "mode-a" | "mode-a-simulator" => mode_a(artifact, kind == "mode-a-simulator"),
        "sileo" => {
            let exe = artifact.join("Wawona");
            if plist_string(&artifact.join("Info.plist"), "CFBundleIdentifier").as_deref() != Some(MODE_B_ID) {
                bail!("Sileo bundle identifier is not {MODE_B_ID}");
            }
            require_minimum(&exe, MINIMUM)?;
            println!("Sileo iOS {MINIMUM}+ artifact gate OK: {}", artifact.display());
            Ok(())
        }
        _ => mode_b(artifact, kind == "iteration"),
    }
}

fn mode_a(app: &Path, simulator: bool) -> Result<()> {
    let exe = app.join("Wawona");
    if !exe.is_file() {
        bail!("Mode A executable is missing");
    }
    if plist_string(&app.join("Info.plist"), "CFBundleIdentifier").as_deref() != Some(MODE_A_ID) {
        bail!("Mode A bundle identifier changed");
    }
    let syms = nm(&["-gU"], &exe);
    if syms.contains("_wwn_iomfb_") {
        bail!("Mode A links the private IOMFB sink");
    }
    if syms.contains("_wwn_igetty_ios_") {
        bail!("Mode A links the TrollStore session switcher");
    }
    if strings(&exe).iter().any(|s| s.contains("IOMobileFramebuffer") || s.contains("WWN_MODE_B")) {
        bail!("Mode A contains Mode B private symbols or strings");
    }
    if let Some(q) = files(app).map(|p| p.to_string_lossy().into_owned()).find(|p| qemu(p)) {
        bail!("QEMU artifacts are forbidden in Mode A: {q}");
    }
    if let Some(ent) = try_output(cmd("codesign").args(["-d", "--entitlements", ":-"]).arg(app)) {
        for k in ["IOMobileFramebuffer", "platform-application", "no-sandbox", "get-task-allow"] {
            if ent.contains(k) {
                bail!("Mode A carries the Mode B entitlement {k}");
            }
        }
    }
    let platform = if simulator { 7 } else { 2 };
    if simulator && output(cmd("xcrun").args(["lipo", "-archs"]).arg(&exe))? != "arm64" {
        bail!("the simulator floor check needs the native arm64 artifact");
    }
    match build_versions(&exe).first() {
        Some((p, _)) if *p == platform => {}
        other => bail!("wrong main platform {:?} (expected {platform})", other.map(|v| v.0)),
    }
    require_minimum(&exe, MINIMUM)?;
    dependency_minima(app, platform, MINIMUM)?;
    println!("Mode A firewall and platform {platform} dependency floors {MINIMUM} OK: {}", app.display());
    Ok(())
}

fn mode_b(tipa: &Path, iteration: bool) -> Result<()> {
    let file = name(tipa);
    if !regex::Regex::new(r"^Wawona-\d{2}\.\d{1,2}\.\d{1,2}-iOS-arm64\.tipa$")?.is_match(&file) {
        bail!("Mode B filename {file} does not follow release naming");
    }
    let mut z = zip::ZipArchive::new(std::fs::File::open(tipa)?)?;
    let tmp = std::env::temp_dir().join(format!("tipa-{}", std::process::id()));
    let mut entries = Vec::new();
    for i in 0..z.len() {
        let mut e = z.by_index(i)?;
        if e.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
            bail!("tipa must not contain symbolic links ({})", e.name());
        }
        let n = e.name().to_string();
        if n == "Payload/Wawona.app/Wawona" || n == "Payload/Wawona.app/Info.plist" {
            let mut b = Vec::new();
            e.read_to_end(&mut b)?;
            write(tmp.join(&n), b)?;
        }
        entries.push(n);
    }
    let app = tmp.join("Payload/Wawona.app");
    let exe = app.join("Wawona");
    let r = (|| {
        if !exe.is_file() {
            bail!("Mode B executable is missing");
        }
        if entries.iter().any(|e| e.starts_with("Payload/Wawona.app/_CodeSignature/")) {
            bail!("tipa must not contain _CodeSignature");
        }
        for f in ["libEGL", "libGLESv2"] {
            if !entries.contains(&format!("Payload/Wawona.app/Frameworks/{f}.framework/{f}")) {
                bail!("Mode B runtime dependency is missing: {f}.framework");
            }
        }
        // Relay owns the CPU; zsh's _qemu completion is not an engine.
        if let Some(q) = entries.iter().find(|e| qemu(e)) {
            bail!("QEMU artifacts are forbidden in Mode B (Relay fails closed): {q}");
        }
        let info = app.join("Info.plist");
        if plist_string(&info, "CFBundleIdentifier").as_deref() != Some(MODE_B_ID) {
            bail!("Mode B bundle identifier is wrong");
        }
        if plist_string(&info, "CFBundleVersion").is_none_or(|v| v.is_empty()) {
            bail!("Mode B build number is missing");
        }
        require_minimum(&exe, MINIMUM)?;
        let syms = nm(&["-gU"], &exe);
        for (s, what) in [("_wwn_iomfb_open", "IOMFB sink"), ("_wwn_igetty_ios_initialize", "logical session switcher")]
        {
            if !syms.contains(s) {
                bail!("Mode B {what} is not linked");
            }
        }
        if !strings(&exe).iter().any(|s| s.contains("IOMobileFramebuffer")) {
            bail!("Mode B IOMFB SPI is absent");
        }
        let ent = output(cmd("ldid").arg("-e").arg(&exe))?;
        for k in [
            "get-task-allow",
            "platform-application",
            "com.apple.private.security.no-sandbox",
            "com.apple.private.IOMobileFramebuffer",
            "com.apple.security.iokit-user-client-class",
        ] {
            if !ent.contains(k) {
                bail!("missing entitlement: {k}");
            }
        }
        // wawona-mode-b-watchdog-safety: never an IOWatchdog entitlement.
        if ["iowatchdog", "ElleKit", "ellekit"].iter().any(|k| ent.contains(k)) {
            bail!("forbidden jailbreak or watchdog entitlement found");
        }
        Ok(())
    })();
    let _ = std::fs::remove_dir_all(&tmp);
    r?;
    let what = if iteration { "iteration tipa" } else { "tipa" };
    println!("Mode B {what} firewall OK: {}", tipa.display());
    Ok(())
}

pub fn contract() -> Result<()> {
    let replay = read(root().join(".agent-device/wawona-ios-vphone-smoke.ad"))?;
    for (k, why) in [
        ("context device=vphone wawona-jb", "pin device vphone wawona-jb"),
        ("open com.aspauldingcode.Wawona.ModeB", "open the Mode B bundle"),
        ("test-artifacts/modeb-ios/", "store screenshots under modeb-ios/"),
    ] {
        if !replay.contains(k) {
            bail!("the vphone replay must {why}");
        }
    }
    let smoke = read(root().join("xtask/src/lab/smoke.rs"))?;
    // A replay cannot enable JIT; the smoke's vphone lane opens it first.
    if !smoke.contains("open-jit") || !smoke.contains(MODE_B_ID) {
        bail!("the agent-device smoke's vphone lane must open-jit the Mode B bundle first");
    }
    if let Ok(a) = std::env::var("WAWONA_MODEA_APP") {
        mode_a(Path::new(&a), false)?;
    }
    if let Ok(t) = std::env::var("WAWONA_MODEB_TIPA") {
        mode_b(Path::new(&t), false)?;
    }
    println!("iOS Mode B CI contract OK");
    Ok(())
}
