//! `cargo xtask deps`: the per-SDK C libraries and bundle trees under `.deps`.
//!
//! Nix builds each slice (`.#deps-<sdk>`) in CI; `deps pack` makes it
//! relocatable and `deps push` publishes it to GHCR as an OCI artifact.
//! `deps.lock` records each slice's digest, and `cargo xtask deps get <sdk>`
//! downloads, verifies and unpacks it. `--nix` builds the slice locally
//! instead, which is how a C dependency change is tried before CI.

mod oci;
mod pack;

use crate::util::*;
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::io::Read;
use std::path::{Path, PathBuf};

pub const REGISTRY: &str = "ghcr.io";
pub const REPOSITORY: &str = "wawona/deps";

#[derive(Serialize, Deserialize, Default)]
pub struct Lock {
    #[serde(default)]
    pub slices: BTreeMap<String, Entry>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Entry {
    /// The Nix output's narHash, so CI publishes only a slice that changed.
    pub nar: String,
    /// sha256 of the .tar.zst, which is also its OCI blob digest.
    pub sha256: String,
    pub size: u64,
}

impl Lock {
    pub fn path() -> PathBuf {
        root().join("deps.lock")
    }
    pub fn load() -> Result<Self> {
        let p = Self::path();
        if !p.exists() {
            return Ok(Self::default());
        }
        Ok(toml::from_str(&read(p)?)?)
    }
    pub fn save(&self) -> Result<()> {
        let head = "# Prebuilt dependency slices (ghcr.io/wawona/deps). The deps workflow\n\
                    # writes this file; `cargo xtask deps get <sdk>` reads it.\n\n";
        write(Self::path(), format!("{head}{}", toml::to_string(self)?))
    }
}

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Fetch slices (an Xcode PLATFORM_NAME, android, or src) into .deps.
    Get(GetArgs),
    /// Make a Nix-built slice relocatable and archive it (CI).
    Pack { sdk: String, from: PathBuf, out: PathBuf },
    /// Publish an archive to GHCR and record it in deps.lock (CI).
    Push {
        sdk: String,
        archive: PathBuf,
        #[arg(long)]
        nar: String,
    },
    /// Print the narHash deps.lock records for a slice.
    Nar { sdk: String },
    /// Fold the entries of other deps.lock files into this one (CI: one
    /// matrix job publishes each slice).
    Merge { locks: Vec<PathBuf> },
}

#[derive(clap::Args)]
pub struct GetArgs {
    pub sdks: Vec<String>,
    /// Build the slices with Nix instead of downloading them.
    #[arg(long)]
    pub nix: bool,
    /// Extra `nix build` arguments after `--`, such as
    /// `--override-input wwn-zsh path:../wwn-zsh`; they imply `--nix`.
    #[arg(last = true)]
    pub nix_args: Vec<String>,
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Get(a) => get(a),
        Cmd::Pack { sdk, from, out } => pack::pack(&sdk, &from, &out),
        Cmd::Push { sdk, archive, nar } => push(&sdk, &archive, &nar),
        Cmd::Nar { sdk } => {
            println!("{}", Lock::load()?.slices.get(&sdk).map(|e| e.nar.as_str()).unwrap_or(""));
            Ok(())
        }
        Cmd::Merge { locks } => {
            let mut lock = Lock::load()?;
            let base = lock.slices.clone();
            for p in locks {
                let other: Lock = toml::from_str(&read(&p)?)?;
                for (k, v) in other.slices {
                    if base.get(&k).map(|e| &e.sha256) != Some(&v.sha256) {
                        lock.slices.insert(k, v);
                    }
                }
            }
            lock.save()
        }
    }
}

/// Slices one SDK needs: the watch app embeds in the iPhone app, and every
/// build reads the shared source slice.
fn expand(sdks: &[String]) -> Vec<String> {
    let mut v = vec!["src".to_string()];
    for s in sdks {
        let s = crate::slices::deps_name(s).to_string();
        let watch = match s.as_str() {
            "iphoneos" => Some("watchos"),
            "iphonesimulator" => Some("watchsimulator"),
            _ => None,
        };
        for x in std::iter::once(s).chain(watch.map(str::to_string)) {
            if !v.contains(&x) {
                v.push(x);
            }
        }
    }
    v
}

pub fn get(a: GetArgs) -> Result<()> {
    if a.sdks.is_empty() {
        bail!("usage: cargo xtask deps get <sdk>... (macosx iphonesimulator iphoneos appletvsimulator xrsimulator android ...)");
    }
    let root = root();
    let dir = root.join(".deps");
    std::fs::create_dir_all(&dir)?;
    let lock = Lock::load()?;
    for sdk in expand(&a.sdks) {
        let dst = dir.join(&sdk);
        let nix_build = || -> Result<()> {
            remove(&dst)?;
            run(cmd("nix")
                .current_dir(&root)
                .args(["build", &format!(".#deps-{sdk}")])
                .args(&a.nix_args)
                .arg("--out-link")
                .arg(&dst))
        };
        if a.nix || !a.nix_args.is_empty() {
            nix_build()?;
            continue;
        }
        let Some(e) = lock.slices.get(&sdk) else {
            if dst.exists() {
                eprintln!("{sdk}: not in deps.lock; using the local {}", dst.display());
            } else if have("nix") {
                eprintln!("{sdk}: not in deps.lock; building it with Nix");
                nix_build()?;
            } else {
                bail!("deps.lock has no {sdk} slice yet, and Nix is not installed to build it");
            }
            continue;
        };
        if read(dst.join(".sha256")).ok().as_deref() == Some(e.sha256.as_str()) {
            eprintln!("{sdk}: up to date");
            continue;
        }
        fetch(&sdk, e, &dst)?;
    }
    if let Ok(team) = std::env::var("TEAM_ID") {
        if !team.is_empty() {
            write(dir.join("signing.xcconfig"), format!("DEVELOPMENT_TEAM = {team}\n"))?;
        }
    }
    for (link, target) in [("terminal", "src/terminal"), ("toolbar-keys", "src/toolbar-keys")] {
        symlink(target, dir.join(link))?;
    }
    link_path_crates(false)
}

/// Points the root Cargo.toml's path crates (`waypipe/`, `coreutils/`) at
/// .deps/src. Android's waypipe carries its own patch set.
pub fn link_path_crates(android: bool) -> Result<()> {
    let root = root();
    let src = root.join(".deps/src");
    for c in ["waypipe", "coreutils"] {
        let patched = src.join("android").join(c);
        let want = if android && patched.exists() { patched } else { src.join(c) };
        let link = root.join(c);
        if std::fs::read_link(&link).ok().as_deref() != Some(want.as_path()) {
            symlink(&want, &link)?;
        }
    }
    Ok(())
}

fn remove(p: &Path) -> Result<()> {
    match p.symlink_metadata() {
        Ok(m) if m.is_dir() => std::fs::remove_dir_all(p)?,
        Ok(_) => std::fs::remove_file(p)?,
        Err(_) => {}
    }
    Ok(())
}

fn fetch(sdk: &str, e: &Entry, dst: &Path) -> Result<()> {
    eprintln!("{sdk}: downloading {} MB", e.size / 1_000_000);
    let reader = oci::blob(&e.sha256)?;
    let mut hasher = Sha256::new();
    let tee = Tee { inner: reader, hasher: &mut hasher };
    let tmp = dst.with_extension("partial");
    remove(&tmp)?;
    std::fs::create_dir_all(&tmp)?;
    let mut ar = tar::Archive::new(zstd::Decoder::new(tee)?);
    ar.set_preserve_permissions(true);
    ar.unpack(&tmp).with_context(|| format!("unpack {sdk}"))?;
    // tar stops at its end blocks; hash the stream to its end.
    let mut rest = ar.into_inner().finish();
    std::io::copy(&mut rest, &mut std::io::sink())?;
    drop(rest);
    let got = hex(&hasher.finalize());
    if got != e.sha256 {
        remove(&tmp)?;
        bail!("{sdk}: sha256 {got} does not match deps.lock {}", e.sha256);
    }
    write(tmp.join(".sha256"), &e.sha256)?;
    remove(dst)?;
    std::fs::rename(&tmp, dst)?;
    // Readers that do not expand @SLICE@ (Gradle before the CMake replace,
    // older Studio caches) still need absolute paths on disk. Expand after
    // rename so the placeholder becomes the final .deps/<sdk> path.
    expand_slice_placeholders(dst)?;
    eprintln!("{sdk}: {}", dst.display());
    Ok(())
}

fn expand_slice_placeholders(dir: &Path) -> Result<()> {
    let abs = dir
        .canonicalize()
        .unwrap_or_else(|_| dir.to_path_buf())
        .to_string_lossy()
        .into_owned();
    for name in ["wawona.properties", "slice.json"] {
        let p = dir.join(name);
        if !p.is_file() {
            continue;
        }
        let s = read(&p)?;
        if s.contains("@SLICE@") {
            write(&p, s.replace("@SLICE@", &abs))?;
        }
    }
    Ok(())
}

struct Tee<'a, R> {
    inner: R,
    hasher: &'a mut Sha256,
}

impl<R: Read> Read for Tee<'_, R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.hasher.update(&buf[..n]);
        Ok(n)
    }
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn sha256_file(p: &Path) -> Result<String> {
    let mut f = std::fs::File::open(p)?;
    let mut h = Sha256::new();
    std::io::copy(&mut f, &mut h)?;
    Ok(hex(&h.finalize()))
}

fn push(sdk: &str, archive: &Path, nar: &str) -> Result<()> {
    let sha = sha256_file(archive)?;
    let size = std::fs::metadata(archive)?.len();
    oci::push(sdk, archive, &sha, size)?;
    let mut lock = Lock::load()?;
    lock.slices.insert(sdk.to_string(), Entry { nar: nar.to_string(), sha256: sha, size });
    lock.save()
}
