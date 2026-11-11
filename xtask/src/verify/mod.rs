//! `cargo xtask verify <check>...`: repository gates CI and the build phases run.
//!
//! Each check reads the checkout, records every violation and prints one
//! verdict. A check fails closed when a file it names is missing.

mod android;
mod apple;
mod linux;
pub mod report;
mod wayland;

use crate::util::*;
use anyhow::{bail, Result};
use std::path::{Path, PathBuf};

#[derive(clap::Args)]
pub struct Args {
    /// Checks to run (`--list` names them).
    names: Vec<String>,
    /// Run every check.
    #[arg(long)]
    all: bool,
    /// Print the checks and what each guards.
    #[arg(long)]
    list: bool,
    /// wayland-runtime-ownership: fail when a Smithay-equivalent interface is still custom.
    #[arg(long)]
    strict: bool,
    /// wayland-profile-smoke: nix build the flake outputs instead of evaluating them.
    #[arg(long)]
    build: bool,
    /// Directory for the JSON inventories the Wayland checks write.
    #[arg(long)]
    json_out: Option<PathBuf>,
}

pub struct Opts {
    pub strict: bool,
    pub build: bool,
    pub json_out: Option<PathBuf>,
}

/// Violations found by one check, with the file helpers checks share.
pub struct Check {
    pub root: PathBuf,
    errors: Vec<String>,
}

impl Check {
    pub fn fail(&mut self, msg: impl Into<String>) {
        self.errors.push(msg.into());
    }

    pub fn path(&self, rel: &str) -> PathBuf {
        self.root.join(rel)
    }

    /// The file's text, or `None` after recording it as missing.
    pub fn text(&mut self, rel: &str) -> Option<String> {
        match std::fs::read_to_string(self.path(rel)) {
            Ok(t) => Some(t),
            Err(_) => {
                self.fail(format!("missing {rel}"));
                None
            }
        }
    }

    /// Records each needle `rel` lacks, worded by `why`.
    pub fn need(&mut self, rel: &str, needles: &[&str], why: &str) {
        if let Some(t) = self.text(rel) {
            for n in needles {
                if !t.contains(n) {
                    self.fail(format!("{rel}: missing {n:?} ({why})"));
                }
            }
        }
    }

    /// Records each needle `rel` contains, worded by `why`.
    pub fn forbid(&mut self, rel: &str, needles: &[&str], why: &str) {
        if let Some(t) = self.text(rel) {
            for n in needles {
                if t.contains(n) {
                    self.fail(format!("{rel}: forbidden {n:?} ({why})"));
                }
            }
        }
    }

    pub fn must_not_exist(&mut self, rel: &str, why: &str) {
        if self.path(rel).exists() {
            self.fail(format!("{rel} must stay deleted ({why})"));
        }
    }

    pub fn rel(&self, p: &Path) -> String {
        p.strip_prefix(&self.root).unwrap_or(p).display().to_string()
    }
}

/// Files under `dir` (relative to the checkout) whose name ends with `suffix`.
pub fn files_under(root: &Path, dir: &str, suffix: &str) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = walkdir::WalkDir::new(root.join(dir))
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file() && e.file_name().to_string_lossy().ends_with(suffix))
        .map(|e| e.into_path())
        .collect();
    v.sort();
    v
}

pub fn line_count(p: &Path) -> usize {
    std::fs::read(p).map(|b| b.iter().filter(|&&c| c == b'\n').count()).unwrap_or(0)
}

/// A check returns the summary its OK line prints.
type CheckFn = fn(&mut Check, &Opts) -> Result<String>;

const CHECKS: &[(&str, &str, CheckFn)] = &[
    ("calver", "VERSION and Cargo.toml carry today's CalVer", |_, _| calver().map(|_| "today".into())),
    ("android-config", "Gradle SDK and NDK pins match wwn-toolchain's sdk-config.nix", android::config),
    ("android-nochroot", "no Android derivation sets __noChroot", android::nochroot),
    ("android-maintainability", "Android recipes stay small and never swallow failures", android::maintainability),
    ("android-meson-sandbox", "Android meson recipes use androidMesonSandbox.apply", android::meson_sandbox),
    ("android-shell-tools", "Android ships zsh, fastfetch, phoon, waypipe and OpenSSH", android::shell_tools),
    ("android-upgrade-guardrails", "the upgrade checklist and blocker signatures exist", android::upgrade_guardrails),
    ("apple-sdk-warm", "Apple jobs pin Xcode and warm the platform SDKs", apple::sdk_warm),
    ("darwin-cli-mode-a", "Mode A Darwin CLI sources use public APIs only", apple::darwin_cli_mode_a),
    ("ios-shell-tools", "Apple mobile links zsh, fastfetch and libssh2 ssh-cli", apple::ios_shell_tools),
    ("no-objc-glue", "no Wawona-owned ObjC; Sources/WawonaApple files stay under 400 lines", apple::no_objc_glue),
    ("settings-in-app", "Global Settings stay in the app", apple::settings_in_app),
    ("ssh-backends", "Apple mobile uses libssh2; Android uses OpenSSH", apple::ssh_backends),
    ("waypipe-remote-sway-env", "the remote sway fallback runs through env(1) (issue #54)", apple::waypipe_sway_env),
    ("wawona-wasm", "Relay wasm links on every mobile slice, watchOS included", apple::wasm),
    ("linux-bundled-clients", "the Linux client catalog matches Android's", linux::bundled_clients),
    ("linux-machines-parity", "the Linux machine profile model matches the shared schema", linux::machines_parity),
    ("linux-package-wiring", "Linux wrappers take the UI binary and stay LF", linux::package_wiring),
    ("linux-shell-tools", "the Linux wrapper carries the shell and client runtimes", linux::shell_tools),
    ("nixpkgs-lineage", "build-critical inputs follow the root nixpkgs (issue #47)", linux::nixpkgs_lineage),
    ("no-tar-wildcards", "no Nix recipe uses tar --wildcards (a bsdtar no-op)", linux::no_tar_wildcards),
    ("smithay-coverage", "the protocol manifest agrees with the Smithay runtime", wayland::smithay_coverage),
    ("wayland-no-equivalent-closure", "every no-equivalent protocol has a disposition", wayland::no_equivalent_closure),
    ("wayland-profile-smoke", "protocol profiles stay consistent; the flake outputs evaluate", wayland::profile_smoke),
    ("wayland-protocol-manifest", "the protocol manifest is complete and well formed", wayland::protocol_manifest),
    ("wayland-runtime-ownership", "who owns each protocol at runtime", wayland::runtime_ownership),
];

pub fn main(a: Args) -> Result<()> {
    if a.list {
        for (name, doc, _) in CHECKS {
            println!("{name:32} {doc}");
        }
        return Ok(());
    }
    let names: Vec<&str> =
        if a.all { CHECKS.iter().map(|c| c.0).collect() } else { a.names.iter().map(String::as_str).collect() };
    if names.is_empty() {
        bail!("name a check or pass --all (--list names them)");
    }
    let opts = Opts { strict: a.strict, build: a.build, json_out: a.json_out };
    let mut failed = Vec::new();
    for name in names {
        let Some((_, _, f)) = CHECKS.iter().find(|c| c.0 == name) else {
            bail!("unknown check {name} (--list names them)");
        };
        let mut c = Check { root: root(), errors: Vec::new() };
        let summary = f(&mut c, &opts);
        match (summary, c.errors.is_empty()) {
            (Ok(s), true) => println!("{name}: OK ({s})"),
            (r, _) => {
                println!("{name}: FAILED");
                for e in &c.errors {
                    println!("- {e}");
                }
                if let Err(e) = r {
                    println!("- {e:#}");
                }
                failed.push(name);
            }
        }
    }
    if !failed.is_empty() {
        bail!("failed: {}", failed.join(", "));
    }
    Ok(())
}

/// Fails closed when the CalVer is not today's. A release rebuild of a past
/// tip sets WAWONA_ALLOW_STALE_CALVER=1.
pub fn calver() -> Result<()> {
    if std::env::var("WAWONA_ALLOW_STALE_CALVER").as_deref() == Ok("1") {
        eprintln!("calver: skipped (WAWONA_ALLOW_STALE_CALVER=1)");
        return Ok(());
    }
    let today = output(cmd("date").env("TZ", "America/Los_Angeles").arg("+%y.%-m.%-d"))?;
    let root = root();
    let file = read(root.join("VERSION"))?.trim().to_string();
    let manifest: toml::Table = toml::from_str(&read(root.join("Cargo.toml"))?)?;
    let cargo = manifest.get("package").and_then(|p| p.get("version")).and_then(|v| v.as_str()).unwrap_or("");
    if file != today || cargo != today {
        bail!(
            "CalVer mismatch: today (America/Los_Angeles) {today}, VERSION {file}, Cargo.toml {cargo}.\n\
             Bump VERSION and Cargo.toml to {today} and sync Cargo.lock. A deliberate stale rebuild sets WAWONA_ALLOW_STALE_CALVER=1."
        );
    }
    Ok(())
}
