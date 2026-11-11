//! The shipped graphics capability matrix (wawona-platform-targets) on an
//! unpacked app or artifact root.

use super::*;

/// Scans the bundle's Mach-O files once: their strings, defined driver entry
/// points and linked libraries.
struct Bundle {
    root: PathBuf,
    machos: Vec<(PathBuf, Vec<String>)>,
}

impl Bundle {
    fn new(root: &Path) -> Bundle {
        let machos = machos(root).into_iter().map(|p| (p.clone(), strings(&p))).collect();
        Bundle { root: root.to_path_buf(), machos }
    }

    /// The first binary carrying a string that contains `marker`.
    fn marker(&self, marker: &str) -> Option<&Path> {
        self.machos.iter().find(|(_, s)| s.iter().any(|l| l.contains(marker))).map(|(p, _)| p.as_path())
    }

    /// Whole-string form, for markers that are also substrings of prose:
    /// ANGLE's renderer string is the literal "ANGLE (", while kmscube's UI
    /// copy mentions "iland + ANGLE (userland KMS)" on every target.
    fn exact(&self, marker: &str) -> Option<&Path> {
        self.machos.iter().find(|(_, s)| s.iter().any(|l| l == marker)).map(|(p, _)| p.as_path())
    }

    /// Driver-owned identifiers that survive stripping. Shared environment
    /// help also names SwiftShader, so prose is not evidence of a linked ICD.
    fn swiftshader(&self) -> Option<&Path> {
        ["SwiftShader Device", "SwiftShader driver", "SwiftShaderUUID"].iter().find_map(|m| self.exact(m))
    }

    /// Defined Vulkan/EGL entry points. Strings alone are ambiguous: driver
    /// selection code embeds ICD manifest paths, and the ash crate embeds MVK
    /// enum names, on targets that link no driver.
    fn driver_symbols(&self) -> usize {
        let re = regex::Regex::new(r" [TtSs] _(vk[A-Z]|egl[A-Z]|angle_egl)").unwrap();
        self.machos.iter().map(|(p, _)| nm(&[], p).lines().filter(|l| re.is_match(l)).count()).sum()
    }

    fn find(&self, pred: impl Fn(&str) -> bool) -> Vec<PathBuf> {
        files(&self.root).filter(|p| pred(&name(p))).collect()
    }

    fn has(&self, n: &str) -> bool {
        files(&self.root).any(|p| name(&p) == n)
    }
}

fn gpu_driver_file(n: &str) -> bool {
    let l = n.to_lowercase();
    ["angle", "moltenvk", "swiftshader"].iter().any(|k| l.contains(k))
        || (l.contains("vulkan") && l.contains("icd"))
        || n.starts_with("libvulkan")
        || n.starts_with("libEGL")
        || n.starts_with("libGLES")
}

/// No ANGLE, MoltenVK or SwiftShader, linked or as files.
fn no_drivers(b: &Bundle, platform: &str) -> Result<()> {
    if let Some(p) = b.marker("MoltenVK version") {
        bail!("{platform} bundle statically embeds MoltenVK: {}", p.display());
    }
    if let Some(p) = b.swiftshader() {
        bail!("{platform} bundle statically embeds SwiftShader: {}", p.display());
    }
    if let Some(p) = b.exact("ANGLE (") {
        bail!("{platform} bundle statically embeds ANGLE: {}", p.display());
    }
    let n = b.driver_symbols();
    if n > 0 {
        bail!("{platform} bundle defines {n} Vulkan/EGL entry points; its keep-set is Metal present only");
    }
    let f = b.find(gpu_driver_file);
    if !f.is_empty() {
        bail!("{platform} bundle contains GPU driver artifacts: {f:?}");
    }
    Ok(())
}

/// Every Apple target that ships through App Review. macOS is excluded: it is
/// never store-constrained (wawona-macos-no-appstore). Linkage and Mode B
/// daemons fail; a bare string only warns, since failing on it would reward
/// deleting diagnostics rather than removing capability.
fn store_safety(b: &Bundle, platform: &str) -> Result<()> {
    let dobby = regex::Regex::new(r" [TtU] _?Dobby").unwrap();
    let mut bad = Vec::new();
    for (p, _) in &b.machos {
        if linked(p).contains("/System/Library/PrivateFrameworks/") {
            bad.push(format!("links a private framework: {}", p.display()));
        }
        if nm(&[], p).lines().any(|l| dobby.is_match(l)) {
            bad.push(format!("references Dobby (Mode B code injection): {}", p.display()));
        }
    }
    for d in b.find(|n| matches!(n, "framebufferd" | "inputd" | "amfiexceptiond")) {
        bad.push(format!("contains Mode B daemon {}", d.display()));
    }
    for m in ["SkyLight", "CoreBedtime", "DYLD_INSERT_LIBRARIES"] {
        if let Some(p) = b.marker(m) {
            println!("WARN: {platform} carries the string '{m}' (no linkage) in {}", p.display());
        }
    }
    if !bad.is_empty() {
        bail!("{platform} store safety:\n  {}", bad.join("\n  "));
    }
    println!("OK: {platform} store-safety (no private frameworks, no Dobby, no Mode B daemons)");
    Ok(())
}

fn flag(k: &str) -> bool {
    std::env::var(k).as_deref() == Ok("1")
}

pub fn check(platform: &str, root: &Path) -> Result<()> {
    if !root.exists() {
        bail!("missing root {}", root.display());
    }
    mode_b(platform.starts_with("macos"), root)?;
    let b = Bundle::new(root);
    match platform {
        // Store Apple-mobile presents through Smithay and Metal; GLES clients
        // install later as optional software.
        "ios" | "ipados" | "visionos" => {
            store_safety(&b, platform)?;
            no_drivers(&b, platform)?;
            println!("OK: {platform} has no ANGLE/MoltenVK/SwiftShader (optional software stays unbundled)");
        }
        // WWN_TVOS_GPU=1 requires MoltenVK and ANGLE, as on iOS before the
        // keep-set change; without it nothing may drift into the bundle.
        "tvos" if flag("WWN_TVOS_GPU") => {
            store_safety(&b, platform)?;
            let m = b.marker("MoltenVK version").context("tvos WWN_TVOS_GPU=1 but no statically linked MoltenVK")?;
            println!("OK: tvos MoltenVK found in {}", m.display());
            let a = b.exact("ANGLE (").context("tvos WWN_TVOS_GPU=1 but no statically linked ANGLE")?;
            println!("OK: tvos ANGLE found in {}", a.display());
        }
        "tvos" => {
            store_safety(&b, platform)?;
            no_drivers(&b, platform)?;
            for (p, _) in &b.machos {
                let l = linked(p);
                if ["IOKit", "MoltenVK", "libEGL", "libGLES", "Vulkan"].iter().any(|k| l.contains(k)) {
                    bail!("tvos Mach-O links a forbidden graphics dependency: {}\n{l}", p.display());
                }
            }
            println!("OK: tvos defines no Vulkan/EGL entry points");
        }
        "watchos" => {
            store_safety(&b, platform)?;
            watchos(&b)?;
        }
        "android" => android(&b)?,
        "macos" => {
            // The two hardware Vulkan ICDs behind vkcube's fallback chain.
            // SwiftShader is the optional CPU last resort for GPU-less VMs.
            for n in ["libMoltenVK.dylib", "libvulkan_kosmickrisp.dylib"] {
                if !b.has(n) {
                    bail!("macOS graphics bundle missing {n}");
                }
            }
            let sw = if b.has("libvk_swiftshader.dylib") { "present" } else { "not bundled" };
            println!("INFO: macOS SwiftShader CPU fallback ICD {sw}");
        }
        _ => {}
    }
    println!("OK: {platform} graphics bundle policy passed under {}", root.display());
    Ok(())
}

/// watchOS has no public Metal: MoltenVK never, the CPU SwiftShader + ANGLE
/// ICD only under WWN_WATCH_SWIFTSHADER=1, and present through SpriteKit.
fn watchos(b: &Bundle) -> Result<()> {
    if let Some(p) = b.marker("MoltenVK version") {
        bail!("watchos must not embed MoltenVK (no public Metal WSI): {}", p.display());
    }
    if !flag("WWN_WATCH_SWIFTSHADER") {
        if let Some(p) = b.swiftshader().or_else(|| b.exact("ANGLE (")) {
            bail!("watchos bundle embeds a GLES/VK ICD without WWN_WATCH_SWIFTSHADER=1: {}", p.display());
        }
        println!("OK: watchos has no GLES/VK ICD (SpriteKit present only)");
    } else {
        let exe = b.root.join(
            crate::artifact::ios::plist_string(&b.root.join("Info.plist"), "CFBundleExecutable")
                .unwrap_or_else(|| "Wawona".into()),
        );
        if b.swiftshader().is_none() && !nm(&["-gU"], &exe).contains("vkGetInstanceProcAddr") {
            bail!("watchos WWN_WATCH_SWIFTSHADER=1 but the SwiftShader ICD was not found");
        }
        b.exact("ANGLE (").context("watchos WWN_WATCH_SWIFTSHADER=1 but ANGLE was not found")?;
        println!("OK: watchos CPU GLES/VK (SwiftShader + ANGLE; present remains SpriteKit)");
    }
    let mut spritekit = false;
    for (p, _) in &b.machos {
        let l = linked(p);
        spritekit |= l.contains("SpriteKit.framework");
        if l.contains("Metal.framework") {
            if !flag("WWN_WATCHOS_METAL") {
                bail!("watchos Mach-O links Metal.framework (store present is SpriteKit only): {}", p.display());
            }
            println!("INFO: watchos links Metal.framework under WWN_WATCHOS_METAL=1 (research; never a store IPA)");
        }
    }
    if !spritekit {
        bail!("watchos bundle does not link SpriteKit.framework (the present accelerator)");
    }
    println!("OK: watchos present accelerator (SpriteKit linked)");
    Ok(())
}

fn android(b: &Bundle) -> Result<()> {
    let apple = b.find(|n| {
        n.ends_with(".dylib") || n.to_lowercase().contains("moltenvk") || n.to_lowercase().contains("iosurface")
    });
    if !apple.is_empty() {
        bail!("Android bundle contains Apple-only graphics artifacts: {apple:?}");
    }
    // Mode B is macOS desktop-host only; a Play APK never carries it.
    let leak = b.find(|n| {
        matches!(n, "libwayland-mac.dylib" | "framebufferd" | "inputd" | "amfiexceptiond")
            || n.to_lowercase().contains("dobby")
    });
    if !leak.is_empty() {
        bail!("Android Play bundle contains Mode B or privileged artifacts: {leak:?}");
    }
    let kgsl = b.find(|n| {
        let l = n.to_lowercase();
        l.contains("turnip") || l.contains("freedreno")
    });
    if !kgsl.is_empty() {
        bail!("Android runtime-only bundle contains direct KGSL driver artifacts: {kgsl:?}");
    }
    for n in ["libEGL_angle.so", "libGLESv2_angle.so", "libvk_swiftshader.so", "vk_swiftshader_icd.json"] {
        if !b.has(n) {
            bail!("Android graphics bundle missing {n}");
        }
    }
    println!("OK: android Play store-safety (no Mode B, no KGSL, ANGLE + SwiftShader + ICD present)");
    Ok(())
}

use anyhow::Context;
