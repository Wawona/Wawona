//! `cargo xtask rove <lane>`: run one Verification report lane's tools and
//! record each failure, or each missing tool, as one NDJSON finding
//! (`cargo xtask report`). The lane fails when any finding is an error;
//! warnings mark research tools that have no pinned CI install yet
//! (docs/verification-matrix.md).

mod native;

use crate::util::*;
use crate::verify::report;
use anyhow::{bail, Context, Result};
use serde_json::json;
use std::collections::BTreeSet;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The Kani release CI installs (`prove install-kani`).
const KANI: &str = "0.68.0";
/// The Verus release Relay pins.
const VERUS: &str = "0.2026.09.27.3cf1832";
/// The nightly Miri runs on.
const MIRI_NIGHTLY: &str = "nightly-2026-09-29";
const HELPERS: &str = "verification/helpers-check/Cargo.toml";

#[derive(clap::Args)]
pub struct Args {
    #[command(subcommand)]
    lane: LaneName,
}

#[derive(clap::Subcommand)]
enum LaneName {
    /// clippy, cargo-deny, proptest, Kani, protocol proofs, Miri, Loom, Verus.
    Formal(Out),
    /// Kani harnesses for the Wayland protocol erroneous-check helpers.
    ProtocolProofs(Out),
    /// Verus on the rect clamp and SSH host models.
    Verus,
    /// cargo-fuzz under ASan, plus the research provers.
    Heavy(Out),
    /// Parse every .nix file, format-check and lint flake.nix.
    Nix(Out),
    /// Sanitizers, analyzers and model checkers on Wawona's C helpers.
    C(Out),
    /// The Swift SSH host differential, strict concurrency and sanitizers.
    Swift(Out),
    /// Android unit tests, detekt, lint, JBMC and Java PathFinder.
    Kotlin(Out),
    /// Install a Kani release tarball and its toolchain (Linux CI).
    InstallKani {
        #[arg(default_value = KANI)]
        version: String,
        #[arg(default_value = "x86_64-unknown-linux-gnu")]
        target: String,
    },
}

#[derive(clap::Args)]
struct Out {
    /// NDJSON findings file (default verification-out/<lane>.ndjson).
    #[arg(long)]
    out: Option<PathBuf>,
}

pub fn main(a: Args) -> Result<()> {
    std::env::set_current_dir(root())?;
    let out = |name: &str, o: Out| o.out.unwrap_or_else(|| root().join(format!("verification-out/{name}.ndjson")));
    match a.lane {
        LaneName::Formal(o) => formal(Lane::new("formal", out("formal", o))?),
        LaneName::ProtocolProofs(o) => protocol_proofs(Lane::new("protocol-proofs", out("protocol-proofs", o))?),
        LaneName::Verus => verus(),
        LaneName::Heavy(o) => heavy(Lane::new("heavy", out("heavy", o))?),
        LaneName::Nix(o) => nix(Lane::new("nix", out("nix", o))?),
        LaneName::C(o) => native::c(Lane::new("c", out("c", o))?),
        LaneName::Swift(o) => native::swift(Lane::new("swift", out("swift", o))?),
        LaneName::Kotlin(o) => native::kotlin(Lane::new("kotlin", out("kotlin", o))?),
        LaneName::InstallKani { version, target } => install_kani(&version, &target),
    }
}

/// One lane's findings file.
pub struct Lane {
    name: &'static str,
    out: PathBuf,
}

impl Lane {
    fn new(name: &'static str, out: PathBuf) -> Result<Lane> {
        let out = if out.is_absolute() { out } else { root().join(out) };
        write(&out, "")?;
        Ok(Lane { name, out })
    }

    fn record(&self, severity: &str, tool: &str, file: &str, rule: &str, failure: &str, fix: &str) {
        let row = json!({"tool": tool, "file": file, "line": 1, "rule": rule, "failure": failure, "fix": fix, "severity": severity});
        if let Err(e) = report::append(&self.out, &row) {
            eprintln!("cannot record {tool} finding: {e:#}");
        }
    }

    pub fn error(&self, tool: &str, file: &str, rule: &str, failure: &str, fix: &str) {
        self.record("error", tool, file, rule, failure, fix);
    }

    pub fn warn(&self, tool: &str, file: &str, rule: &str, failure: &str, fix: &str) {
        self.record("warning", tool, file, rule, failure, fix);
    }

    /// The directory beside the findings file, for build outputs.
    pub fn dir(&self) -> PathBuf {
        self.out.parent().unwrap_or(Path::new(".")).to_path_buf()
    }

    /// Writes `<lane>.md` and fails when any finding is an error.
    pub fn finish(self) -> Result<()> {
        report::summarize(std::slice::from_ref(&self.out), &self.dir().join(format!("{}.md", self.name)))
    }
}

/// Runs `c` with inherited output; true when it exits 0.
pub fn ok(c: &mut Command) -> bool {
    eprintln!("+ {}", render(c));
    c.status().is_ok_and(|s| s.success())
}

/// Runs `c` capturing its output; on failure returns the last `lines` lines
/// joined on one line, for the finding's failure text.
pub fn tail_on_failure(c: &mut Command, lines: usize) -> Option<String> {
    eprintln!("+ {}", render(c));
    let o = match c.output() {
        Ok(o) => o,
        Err(e) => return Some(e.to_string()),
    };
    if o.status.success() {
        return None;
    }
    let text = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
    let v: Vec<&str> = text.lines().collect();
    Some(v[v.len().saturating_sub(lines)..].join(" "))
}

fn formal(lane: Lane) -> Result<()> {
    let lints = ["--", "-D", "clippy::correctness", "-D", "clippy::suspicious"];
    if !ok(cmd("cargo").args(["clippy", "--locked", "--all-targets"]).args(lints))
        && !ok(cmd("cargo").args(["clippy", "--manifest-path", HELPERS]).args(lints))
    {
        lane.error(
            "clippy",
            "Cargo.toml",
            "clippy::correctness",
            "clippy denied a correctness or suspicious lint",
            "cargo clippy --locked --all-targets -- -D clippy::correctness -D clippy::suspicious",
        );
    }
    // The full-tree deny is Gate: packages'; this floor checks the helpers.
    if !ok(cmd("cargo").args(["deny", "--manifest-path", HELPERS, "check"]))
        && !ok(cmd("cargo").args(["deny", "check"]))
    {
        lane.warn(
            "cargo-deny",
            "deny.toml",
            "deny-unavailable",
            "cargo-deny could not check (advisory failure or no cargo-deny)",
            "cargo deny --manifest-path verification/helpers-check/Cargo.toml check",
        );
    }
    if !ok(cmd("cargo").args(["test", "--manifest-path", HELPERS])) {
        lane.error(
            "proptest",
            "src/core/invariants.rs",
            "proptest",
            "helper tests failed",
            "cargo test --manifest-path verification/helpers-check/Cargo.toml",
        );
    }
    let harnesses = ["clamped_rect_stays_inside_nonnegative_bounds", "sanitize_ascii_has_no_shell_metacharacters"];
    match kani() {
        Some(mut k) => {
            k.args(["--manifest-path", HELPERS, "--output-format", "terse"]);
            for h in &harnesses {
                k.args(["--harness", h]);
            }
            if !ok(&mut k) {
                lane.error(
                    "kani",
                    "verification/helpers-check",
                    "helpers-check-kani",
                    "Kani failed helpers-check harnesses",
                    &format!("cargo kani --manifest-path {HELPERS} --harness {}", harnesses.join(" --harness ")),
                );
            }
        }
        None => lane.error("kani", "xtask/src/prove/mod.rs", "missing-tool", "Kani is not installed", &install_hint()),
    }
    let proofs = Lane::new("protocol-proofs", lane.dir().join("protocol-proofs.ndjson"))?;
    if let Err(e) = protocol_proofs(proofs) {
        lane.error(
            "kani",
            "src/core/wayland/protocol_proofs.rs",
            "protocol-proofs",
            &format!("protocol erroneous-check proofs failed: {e:#}"),
            "cargo xtask prove protocol-proofs",
        );
    }
    let toolchains = try_output(cmd("rustup").args(["toolchain", "list"])).unwrap_or_default();
    if toolchains.contains(MIRI_NIGHTLY) {
        // proptest's failure persistence calls getcwd, which isolation blocks.
        let flags = env_or("MIRIFLAGS", "-Zmiri-disable-isolation");
        let mut m = cmd("cargo");
        m.arg(format!("+{MIRI_NIGHTLY}")).args(["miri", "test", "--manifest-path", HELPERS, "--", "--test-threads=1"]);
        if !ok(m.env("MIRIFLAGS", flags)) {
            lane.error(
                "miri",
                "src/core/invariants.rs",
                "miri",
                "Miri failed the helper unit tests",
                &format!(
                    "MIRIFLAGS=-Zmiri-disable-isolation cargo +{MIRI_NIGHTLY} miri test --manifest-path {HELPERS}"
                ),
            );
        }
    } else {
        lane.error(
            "miri",
            "xtask/src/prove/mod.rs",
            "missing-toolchain",
            &format!("{MIRI_NIGHTLY} is not installed"),
            &format!("rustup toolchain install {MIRI_NIGHTLY} --component miri"),
        );
    }
    let loom = root().join("verification/loom-counter");
    if loom.is_dir()
        && !ok(cmd("cargo").args(["test", "--", "--test-threads=1"]).current_dir(&loom).env("RUSTFLAGS", "--cfg loom"))
    {
        lane.error(
            "loom",
            "src/core/generation_counter.rs",
            "loom",
            "Loom model of the generation counter failed",
            "cd verification/loom-counter && RUSTFLAGS='--cfg loom' cargo test",
        );
    }
    if let Err(e) = verus() {
        lane.error(
            "verus",
            "verification/verus/sanitize_ssh_host.rs",
            "verus",
            &format!("Verus rejected the rect or sanitize model: {e:#}"),
            "cargo xtask prove verus",
        );
    }
    lane.finish()
}

/// The harnesses named by `ErroneousChecks::Helpers(&[...])` entries.
fn proof_harnesses(src: &str) -> BTreeSet<String> {
    let entry = regex::Regex::new(r"Helpers\(&\[([^\]]*)\]\)").unwrap();
    let name = regex::Regex::new(r#""([^"]+)""#).unwrap();
    entry
        .captures_iter(src)
        .flat_map(|c| name.captures_iter(&c[1]).map(|n| n[1].to_string()).collect::<Vec<_>>())
        .collect()
}

fn protocol_proofs(lane: Lane) -> Result<()> {
    let src_file = "src/core/wayland/protocol_proofs.rs";
    if !ok(cmd("cargo").args(["test", "--manifest-path", HELPERS, "protocol_proofs", "--", "--nocapture"])) {
        lane.error(
            "protocol-proofs",
            src_file,
            "protocol-proof-unit",
            "protocol_proofs unit tests failed",
            &format!("cargo test --manifest-path {HELPERS} protocol_proofs"),
        );
    }
    let harnesses = proof_harnesses(&read(root().join(src_file))?);
    if harnesses.is_empty() {
        lane.error(
            "protocol-proofs",
            src_file,
            "no-harnesses",
            "PROTOCOL_PROOF_OBLIGATIONS lists no Helpers to prove",
            "add ErroneousChecks::Helpers entries with Kani harnesses",
        );
        return lane.finish();
    }
    match kani() {
        Some(mut k) => {
            k.args(["--manifest-path", HELPERS, "--output-format", "terse"]);
            for h in &harnesses {
                k.args(["--harness", h]);
            }
            if !ok(&mut k) {
                lane.error(
                    "kani",
                    src_file,
                    "protocol-proof-kani",
                    "Kani failed one or more protocol erroneous-check harnesses",
                    "cargo xtask prove protocol-proofs",
                );
            }
        }
        None => lane.error("kani", "xtask/src/prove/mod.rs", "missing-tool", "Kani is not installed", &install_hint()),
    }
    lane.finish()
}

fn verus() -> Result<()> {
    let home = env_or("HOME", "");
    let default = format!("{home}/.local/share/wawona/verus/{VERUS}/verus-arm64-macos/verus");
    let bin = std::env::var("VERUS_BIN").unwrap_or(default);
    let bin = if Path::new(&bin).is_file() {
        bin
    } else if have("verus") {
        "verus".into()
    } else {
        bail!("Verus {VERUS} is required (VERUS_BIN or {bin})");
    };
    for model in ["rect_clamp.rs", "sanitize_ssh_host.rs"] {
        run(cmd(&bin).arg(root().join("verification/verus").join(model)))?;
    }
    Ok(())
}

fn heavy(lane: Lane) -> Result<()> {
    let target = "fuzz/fuzz_targets/clamp_rect.rs";
    let fuzz_install = "cargo +nightly install cargo-fuzz --version 0.13.2 --locked";
    if !have("cargo-fuzz")
        && !ok(cmd("cargo").args(["+nightly", "install", "cargo-fuzz", "--version", "0.13.2", "--locked"]))
    {
        lane.error(
            "cargo-fuzz",
            target,
            "missing-or-failed",
            "cargo-fuzz is not installed and its install failed",
            fuzz_install,
        );
    }
    if have("cargo-fuzz") && root().join("fuzz/Cargo.toml").is_file() {
        let run = [
            "+nightly",
            "fuzz",
            "run",
            "-s",
            "address",
            "clamp_rect",
            "--",
            "-max_total_time=60",
            "-use_value_profile=1",
        ];
        if let Some(tail) = tail_on_failure(cmd("cargo").args(run), 3) {
            lane.error(
                "cargo-fuzz",
                target,
                "missing-or-failed",
                &format!("clamp_rect fuzz failed: {tail}"),
                "cargo +nightly fuzz run -s address clamp_rect -- -max_total_time=60",
            );
        }
    }
    // Research provers: an install attempt, then a warning while unpinned.
    let research = [
        ("rudra", "rudra", "Cargo.toml"),
        ("mirai-driver", "mirai", "Cargo.toml"),
        ("cargo-creusot", "creusot", "src/core/invariants.rs"),
        ("flux", "flux", "src/core/invariants.rs"),
        ("aeneas", "aeneas", "src/core/invariants.rs"),
        ("haybale", "haybale", "src/core/invariants.rs"),
    ];
    for (bin, krate, file) in research {
        if have(bin) {
            continue;
        }
        if let Some(blocker) = tail_on_failure(cmd("cargo").args(["install", krate, "--locked"]), 2) {
            lane.warn(
                bin,
                file,
                "missing-or-failed",
                &format!("{bin} install failed or binary missing after install attempt"),
                &format!("cargo install {krate} --locked; blocker: {blocker}"),
            );
        }
    }
    if !have("prusti-rustc") {
        lane.warn(
            "prusti-rustc",
            "src/core/invariants.rs",
            "missing-or-failed",
            "Prusti is not installed (no cargo install path)",
            "install a Prusti release for clamp_rect",
        );
    }
    lane.finish()
}

fn nix(lane: Lane) -> Result<()> {
    let skip = |p: &Path| {
        let r = p.strip_prefix(root()).unwrap_or(p).to_string_lossy().to_string();
        [".git", ".direnv", "target", "android/.gradle"].iter().any(|d| r == *d) || r.starts_with("result")
    };
    let files: Vec<PathBuf> = walkdir::WalkDir::new(root())
        .into_iter()
        .filter_entry(|e| !skip(e.path()))
        .flatten()
        .filter(|e| e.file_type().is_file() && e.path().extension().is_some_and(|x| x == "nix"))
        .map(|e| e.into_path())
        .collect();
    for f in &files {
        let rel = f.strip_prefix(root()).unwrap_or(f).display().to_string();
        if let Some(err) =
            tail_on_failure(cmd("nix-instantiate").arg("--parse").arg(f).stdout(std::process::Stdio::null()), 20)
        {
            lane.error("nix-parse", &rel, "parse", &err, &format!("nix-instantiate --parse {rel}"));
        }
    }
    // Lint findings on the input graph are recorded but do not fail the floor.
    let tool = |attr: &str, args: &[&str]| -> Command {
        if have(attr) {
            let mut c = cmd(attr);
            c.args(args);
            c
        } else {
            let mut c = cmd("nix");
            c.args(["shell", &format!("nixpkgs#{attr}"), "-c", attr]).args(args);
            c
        }
    };
    if !ok(&mut tool("alejandra", &["--check", "flake.nix"])) {
        lane.error("alejandra", "flake.nix", "alejandra", "alejandra --check failed", "alejandra flake.nix");
    }
    for (name, args) in [("statix", &["check", "flake.nix"][..]), ("deadnix", &["-f", "flake.nix"][..])] {
        if let Some(t) = tail_on_failure(&mut tool(name, args), 8) {
            lane.warn(
                name,
                "flake.nix",
                name,
                &t.chars().take(400).collect::<String>(),
                &format!("{name} {}", args.join(" ")),
            );
        }
    }
    if let Some(t) = tail_on_failure(cmd("nix").args(["flake", "metadata", "--json"]), 5) {
        lane.error("flake-metadata", "flake.nix", "metadata", &t, "nix flake metadata --json");
    }
    lane.finish()
}

fn kani_home(version: &str) -> PathBuf {
    PathBuf::from(env_or("HOME", "")).join(format!(".kani/kani-{version}"))
}

fn install_hint() -> String {
    format!("cargo xtask prove install-kani {KANI} (Linux) or cargo install --locked kani-verifier")
}

/// `cargo kani` as a Command: a PATH install when there is one, else the
/// release `prove install-kani` unpacked, run as kani-driver under the name
/// `cargo-kani` with the environment its launcher sets.
fn kani() -> Option<Command> {
    if have("cargo-kani") {
        let mut c = cmd("cargo");
        c.arg("kani");
        return Some(c);
    }
    let home = kani_home(KANI);
    let driver = home.join("bin/kani-driver");
    let toolchain = std::fs::read_to_string(home.join("rust-toolchain-version")).ok()?;
    if !driver.is_file() {
        return None;
    }
    let mut c = Command::new(&driver);
    c.arg0("cargo-kani").arg("kani");
    let path = std::env::var_os("PATH").unwrap_or_default();
    let mut dirs = vec![home.join("bin")];
    dirs.extend(std::env::split_paths(&path));
    c.env("PATH", std::env::join_paths(dirs).ok()?).env("RUSTUP_TOOLCHAIN", toolchain.trim());
    // Another toolchain's lib directory breaks the driver's own rustc.
    if let Some(ld) = std::env::var_os("LD_LIBRARY_PATH") {
        let keep: Vec<PathBuf> = std::env::split_paths(&ld)
            .filter(|p| !(p.to_string_lossy().contains("/toolchains/") && p.ends_with("lib")))
            .collect();
        c.env("LD_LIBRARY_PATH", std::env::join_paths(keep).ok()?);
    }
    Some(c)
}

fn install_kani(version: &str, target: &str) -> Result<()> {
    let url = format!(
        "https://github.com/model-checking/kani/releases/download/kani-{version}/kani-{version}-{target}.tar.gz"
    );
    let tgz = std::env::temp_dir().join(format!("kani-{version}.tgz"));
    eprintln!("fetching {url}");
    let mut body = ureq::get(&url).call().with_context(|| format!("GET {url}"))?.into_body();
    std::io::copy(&mut body.as_reader(), &mut std::fs::File::create(&tgz)?)?;
    let home = kani_home(version);
    let _ = std::fs::remove_dir_all(&home);
    std::fs::create_dir_all(home.parent().unwrap())?;
    run(cmd("tar").arg("-xzf").arg(&tgz).arg("-C").arg(home.parent().unwrap()))?;
    let toolchain = read(home.join("rust-toolchain-version"))?.trim().to_string();
    let components = ["llvm-tools", "rustc-dev", "rust-src", "rustfmt"];
    let mut r = cmd("rustup");
    r.args(["toolchain", "install", &toolchain, "--profile", "minimal"]);
    for c in components {
        r.args(["--component", c]);
    }
    run(&mut r)?;
    let rustup_home = std::env::var("RUSTUP_HOME").unwrap_or_else(|_| format!("{}/.rustup", env_or("HOME", "")));
    symlink(PathBuf::from(rustup_home).join("toolchains").join(&toolchain), home.join("toolchain"))?;
    if version != KANI {
        eprintln!("note: the lanes run Kani {KANI}; {version} is unpacked beside it");
    }
    run(kani().context("Kani did not unpack")?.arg("--version"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn harnesses_come_from_helpers_entries() {
        let src = r#"
            Ob { checks: Helpers(&["b_proof", "a_proof"]) },
            Ob { checks: Helpers(&[
                "a_proof",
            ]) },
            Ob { checks: Inline },
        "#;
        let got: Vec<String> = super::proof_harnesses(src).into_iter().collect();
        assert_eq!(got, ["a_proof", "b_proof"]);
    }
}
