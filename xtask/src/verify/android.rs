use super::{files_under, line_count, Check, Opts};
use crate::util::*;
use anyhow::{Context, Result};
use regex::Regex;

const GRADLE_APP: &str = "android/app/build.gradle.kts";
const JNI: &str = "src/platform/android/android_jni.c";

/// wwn-toolchain builds the Android slices with the SDK and NDK in its
/// sdk-config.nix; Gradle must compile against the same ones.
pub fn config(c: &mut Check, _: &Opts) -> Result<String> {
    let path = output(cmd("nix").current_dir(&c.root).args(["eval", ".#wwnSdkConfigPath", "--raw"]))?;
    let sdk = read(&path)?;
    let Some(gradle) = c.text(GRADLE_APP) else { return Ok(String::new()) };
    let value = |src: &str, key: &str, quoted: bool, sep: &str| -> Result<String> {
        let pat = if quoted { format!(r#"{key}\s*{sep}\s*"([^"]+)""#) } else { format!(r"{key}\s*{sep}\s*([0-9]+)") };
        Regex::new(&pat)?.captures(src).map(|m| m[1].to_string()).with_context(|| format!("missing {key}"))
    };
    for (key, quoted) in
        [("compileSdk", false), ("targetSdk", false), ("buildToolsVersion", true), ("ndkVersion", true)]
    {
        let want = value(&sdk, key, quoted, "=").with_context(|| path.clone())?;
        let have = value(&gradle, key, quoted, "=").context(GRADLE_APP)?;
        if want != have {
            c.fail(format!("{key} mismatch: sdk-config={want:?}, gradle={have:?}"));
        }
    }
    Ok(path)
}

pub fn nochroot(c: &mut Check, _: &Opts) -> Result<String> {
    let files = files_under(&c.root, "dependencies", "android.nix");
    for p in &files {
        if read(p)?.contains("__noChroot") {
            c.fail(format!("{} sets __noChroot", c.rel(p)));
        }
    }
    Ok(format!("{} recipes", files.len()))
}

/// Recipes stay under 400 lines, and a failing step fails the build.
pub fn maintainability(c: &mut Check, _: &Opts) -> Result<String> {
    let files = files_under(&c.root, "dependencies", "android.nix");
    let swallow = Regex::new(r"\|\|\s*true")?;
    for p in &files {
        let (rel, n) = (c.rel(p), line_count(p));
        if n > 400 {
            c.fail(format!("{rel}: {n} lines exceeds budget 400"));
        }
        if swallow.is_match(&read(p)?) {
            c.fail(format!("{rel}: contains forbidden '|| true' silent fallback"));
        }
    }
    Ok(format!("{} recipes", files.len()))
}

/// The meson recipes live in the sibling wwn-toolchain and repo.wawona.io
/// checkouts (or WWN_TOOLCHAIN_ROOT / REPO_WAWONA_IO_ROOT).
pub fn meson_sandbox(c: &mut Check, _: &Opts) -> Result<String> {
    let root = c.root.clone();
    let sibling = |env: &str, name: &str| {
        std::env::var(env)
            .ok()
            .filter(|v| !v.is_empty())
            .map(std::path::PathBuf::from)
            .into_iter()
            .chain([root.parent().unwrap().join(name), root.join(name)])
            .find(|p| p.is_dir())
    };
    let inline = Regex::new(r"(?s)postPatch\s*=\s*''[^']*patchShebangs\s+\.")?;
    let recipe = |c: &mut Check, base: &std::path::Path, rel: &str| match std::fs::read_to_string(base.join(rel)) {
        Err(_) => c.fail(format!("missing meson android recipe: {rel}")),
        Ok(t) => {
            if !t.contains("androidMesonSandbox.apply") {
                c.fail(format!("{rel}: must wrap mkDerivation with androidMesonSandbox.apply"));
            }
            if inline.is_match(&t) {
                c.fail(format!("{rel}: inline postPatch patchShebangs; use androidMesonSandbox.apply"));
            }
        }
    };
    match sibling("WWN_TOOLCHAIN_ROOT", "wwn-toolchain") {
        None => c.fail("wwn-toolchain not found (set WWN_TOOLCHAIN_ROOT or check it out beside this one)"),
        Some(t) => {
            if !t.join("dependencies/toolchains/android-meson-sandbox.nix").is_file() {
                c.fail("wwn-toolchain: missing dependencies/toolchains/android-meson-sandbox.nix");
            }
            let default = std::fs::read_to_string(t.join("dependencies/toolchains/default.nix")).unwrap_or_default();
            if !default.contains("androidMesonSandbox") {
                c.fail("wwn-toolchain dependencies/toolchains/default.nix: androidMesonSandbox not threaded in androidArgs");
            }
            for lib in [
                "fontconfig",
                "freetype",
                "pixman",
                "cairo",
                "glib",
                "harfbuzz",
                "fribidi",
                "pango",
                "xkbcommon",
                "libwayland",
            ] {
                recipe(c, &t, &format!("dependencies/libs/{lib}/android.nix"));
            }
        }
    }
    match sibling("REPO_WAWONA_IO_ROOT", "repo.wawona.io") {
        None => c.fail("repo.wawona.io not found (set REPO_WAWONA_IO_ROOT or check it out beside this one)"),
        Some(r) => recipe(c, &r, "catalog/deb/gui/weston/in-app/dependencies/clients/weston/compositor-android.nix"),
    }
    Ok("11 recipes".into())
}

pub fn shell_tools(c: &mut Check, _: &Opts) -> Result<String> {
    flake_outputs(c, &["zsh-android", "fastfetch-android", "phoon-android", "waypipe-android"]);
    let nix: String = ["dependencies/wawona/android-deps.nix", "dependencies/wawona/android-shell-tools.nix"]
        .iter()
        .filter_map(|r| c.text(r))
        .collect();
    for n in [
        "zshAndroid",
        "fastfetchAndroid",
        "phoonAndroid",
        "waypipeAndroid",
        "libzsh_bin.so",
        "libfastfetch_bin.so",
        "libphoon_bin.so",
        "libwaypipe_bin.so",
        "ssh:ssh",
        "ssh-keygen:ssh_keygen",
        "assets/zsh",
    ] {
        if !nix.contains(n) {
            c.fail(format!("Android recipes missing shell-tool wiring: {n}"));
        }
    }
    for n in ["dropbearconvert", "libdropbearconvert_bin.so"] {
        if nix.contains(n) {
            c.fail(format!("Android recipes must not ship Dropbear leftover: {n}"));
        }
    }
    c.need(
        JNI,
        &["libzsh_bin.so", "libwaypipe_bin.so", "libphoon_bin.so", "StrictHostKeyChecking=accept-new"],
        "the JNI shell resolves and installs the bundled tools and uses OpenSSH argv",
    );
    Ok("OpenSSH portable; no Dropbear".into())
}

/// The checklist and the signatures `cargo xtask ci baseline` classifies.
pub fn upgrade_guardrails(c: &mut Check, _: &Opts) -> Result<String> {
    c.need(
        "docs/android-upgrade-guardrails.md",
        &[
            "## Scope Triggers",
            "## Pre-upgrade Checklist",
            "## Platform Smoke Validation",
            "## Blocker Signatures",
            "## Acceptance Criteria",
            "`linux-x86_64`",
            "`linux-arm64`",
            "`darwin-arm64`",
            "`darwin-x86_64`",
        ],
        "upgrade checklist section",
    );
    let have: Vec<&str> = crate::ci::SIGNATURES.iter().map(|s| s.0).collect();
    for key in ["toolchain_path_missing", "neon_builtin_mismatch", "gradle_daemon", "gradle_oom"] {
        if !have.contains(&key) {
            c.fail(format!("ci baseline is missing blocker signature {key}"));
        }
    }
    Ok("checklist and signatures".into())
}

/// Each output is defined in flake.nix (as `name =` or `"name" =`).
pub fn flake_outputs(c: &mut Check, names: &[&str]) {
    if let Some(f) = c.text("flake.nix") {
        for n in names {
            if !f.contains(&format!("\"{n}\" =")) && !f.contains(&format!("{n} =")) {
                c.fail(format!("flake.nix missing package output: {n}"));
            }
        }
    }
}
