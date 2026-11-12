//! The GitHub Release DMG: Wawona.app, an Applications symlink and
//! README.txt (drag-install; docs/agent-rules/wawona-release-assets.md).
//! Signed inside out with Developer ID and the hardened runtime, then
//! notarized and stapled (Apple: "Notarizing macOS software before
//! distribution").

use super::{dist, version};
use crate::macho::is_macho;
use crate::product::{self, target};
use crate::util::{cmd, output, root, run, write};
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};

#[derive(clap::Args)]
pub struct Args {
    /// A built Wawona-macOS .app (default: build Release).
    #[arg(long)]
    app: Option<PathBuf>,
    /// Submit to notarytool and staple. Needs APP_STORE_CONNECT_API_KEY
    /// (base64 .p8), APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID.
    #[arg(long)]
    notarize: bool,
}

const README: &str = "Thank you for installing Wawona\n===============================\n\n\
Drag Wawona.app onto Applications. Launch Agents and the login item are in\n\
Wawona Settings, Permissions.\n\nThis DMG is Developer ID signed and notarized.\n";

pub fn main(a: Args) -> Result<()> {
    let app = match a.app {
        Some(p) => p,
        None => {
            product::build(product::Args {
                target: "macos".into(),
                device: true,
                release: true,
                sign: false,
                settings: vec![],
            })?;
            target("macos")?.app(true, true)
        }
    };
    let volume = root().join(".build/package/dmg");
    let _ = std::fs::remove_dir_all(&volume);
    std::fs::create_dir_all(&volume)?;
    let staged = volume.join("Wawona.app");
    run(cmd("ditto").arg(&app).arg(&staged))?;
    std::os::unix::fs::symlink("/Applications", volume.join("Applications"))?;
    write(volume.join("README.txt"), README)?;

    let keychain = Keychain::from_env()?;
    let identity = identity(keychain.as_ref())?;
    sign_bundle(&staged, &identity)?;
    run(cmd("codesign").args(["--verify", "--deep", "--strict", "--verbose=2"]).arg(&staged))?;

    let dmg = dist()?.join(format!("Wawona-{}-macOS-arm64.dmg", version()?));
    let _ = std::fs::remove_file(&dmg);
    run(cmd("hdiutil")
        .args(["create", "-volname", "Wawona", "-format", "UDZO", "-ov", "-srcfolder"])
        .arg(&volume)
        .arg(&dmg))?;
    sign(&dmg, &identity, None)?;
    if a.notarize {
        notarize(&dmg)?;
    }
    println!("{}", dmg.display());
    Ok(())
}

/// Nested code first: frameworks, loose dylibs, helper executables, then
/// the main executable and the bundle seal with the entitlements.
fn sign_bundle(app: &Path, identity: &str) -> Result<()> {
    let contents = app.join("Contents");
    let main = contents.join("MacOS/Wawona");
    let mut frameworks = vec![];
    let mut code = vec![];
    for e in walkdir::WalkDir::new(&contents).contents_first(true) {
        let e = e?;
        let p = e.path();
        if p.extension().is_some_and(|x| x == "framework") {
            frameworks.push(p.to_path_buf());
        } else if e.file_type().is_file()
            && p != main
            && !p.components().any(|c| c.as_os_str().to_string_lossy().ends_with(".framework"))
            && is_macho(p)
        {
            code.push(p.to_path_buf());
        }
    }
    for p in code.iter().chain(&frameworks) {
        sign(p, identity, None)?;
    }
    let ents = root().join("src/resources/app-bundle/Wawona-macOS-DeveloperID.entitlements");
    sign(&main, identity, Some(&ents))?;
    sign(app, identity, Some(&ents))
}

fn sign(p: &Path, identity: &str, entitlements: Option<&Path>) -> Result<()> {
    let mut c = cmd("codesign");
    c.args(["--force", "--sign", identity]);
    if identity != "-" {
        c.args(["--options", "runtime", "--timestamp"]);
    }
    if let Some(e) = entitlements {
        c.arg("--entitlements").arg(e);
    }
    run(c.arg(p))
}

/// WAWONA_CODESIGN_IDENTITY, else the Developer ID Application identity in
/// the keychain search list, else ad hoc for a local test DMG.
fn identity(keychain: Option<&Keychain>) -> Result<String> {
    if let Ok(i) = std::env::var("WAWONA_CODESIGN_IDENTITY") {
        return Ok(i);
    }
    let mut c = cmd("security");
    c.args(["find-identity", "-v", "-p", "codesigning"]);
    if let Some(k) = keychain {
        c.arg(&k.path);
    }
    let found = output(&mut c)?
        .lines()
        .find(|l| l.contains("Developer ID Application"))
        .and_then(|l| l.split('"').nth(1).map(str::to_string));
    match (found, keychain) {
        (Some(i), _) => Ok(i),
        (None, Some(_)) => bail!("the imported P12 has no Developer ID Application identity"),
        (None, None) => {
            eprintln!("note: no Developer ID Application identity; signing ad hoc (not distributable)");
            Ok("-".into())
        }
    }
}

/// A throwaway keychain holding DEVELOPER_ID_APPLICATION_P12_BASE64 (CI).
struct Keychain {
    path: PathBuf,
}

impl Keychain {
    fn from_env() -> Result<Option<Self>> {
        let Ok(p12) = std::env::var("DEVELOPER_ID_APPLICATION_P12_BASE64") else { return Ok(None) };
        let pass = std::env::var("MATCH_PASSWORD").context("MATCH_PASSWORD (the P12 passphrase)")?;
        let dir = root().join(".build/package/keychain");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir)?;
        let k = Keychain { path: dir.join("wawona-devid.keychain-db") };
        let p12_path = dir.join("devid.p12");
        run(cmd("sh")
            .arg("-c")
            .arg("printf %s \"$P12\" | base64 -d > \"$OUT\"")
            .env("P12", p12)
            .env("OUT", &p12_path))?;
        let kpass = output(cmd("openssl").args(["rand", "-base64", "24"]))?;
        run(cmd("security").args(["create-keychain", "-p", &kpass]).arg(&k.path))?;
        run(cmd("security").args(["set-keychain-settings", "-lut", "21600"]).arg(&k.path))?;
        run(cmd("security").args(["unlock-keychain", "-p", &kpass]).arg(&k.path))?;
        let list = output(cmd("security").args(["list-keychains", "-d", "user"]))?;
        let existing: Vec<String> = list.lines().map(|l| l.trim().trim_matches('"').to_string()).collect();
        run(cmd("security").args(["list-keychains", "-d", "user", "-s"]).arg(&k.path).args(&existing))?;
        run(cmd("security").arg("import").arg(&p12_path).arg("-k").arg(&k.path).args([
            "-P",
            &pass,
            "-T",
            "/usr/bin/codesign",
        ]))?;
        run(cmd("security")
            .args(["set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", &kpass])
            .arg(&k.path))?;
        std::fs::remove_file(&p12_path)?;
        Ok(Some(k))
    }
}

impl Drop for Keychain {
    fn drop(&mut self) {
        let _ = cmd("security").arg("delete-keychain").arg(&self.path).status();
    }
}

fn notarize(dmg: &Path) -> Result<()> {
    let var = |k: &str| std::env::var(k).with_context(|| format!("--notarize needs {k}"));
    let key = root().join(".build/package/AuthKey.p8");
    run(cmd("sh")
        .arg("-c")
        .arg("printf %s \"$K\" | base64 -d > \"$OUT\"")
        .env("K", var("APP_STORE_CONNECT_API_KEY")?)
        .env("OUT", &key))?;
    let r = run(cmd("xcrun").args(["notarytool", "submit"]).arg(dmg).arg("--key").arg(&key).args([
        "--key-id",
        &var("APP_STORE_CONNECT_KEY_ID")?,
        "--issuer",
        &var("APP_STORE_CONNECT_ISSUER_ID")?,
        "--wait",
    ]));
    std::fs::remove_file(&key)?;
    r?;
    run(cmd("xcrun").args(["stapler", "staple"]).arg(dmg))?;
    run(cmd("spctl")
        .args(["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4"])
        .arg(dmg))
}
