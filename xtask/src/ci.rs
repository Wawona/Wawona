//! `cargo xtask ci <task>`: GitHub Actions bookkeeping run through `gh`.

use crate::util::*;
use anyhow::{bail, Context, Result};
use regex::Regex;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Classify the failed jobs of recent runs by known signatures.
    Baseline(BaselineArgs),
    /// Write Gate: packages' matrix from .github/ci-package-matrix.json to
    /// GITHUB_OUTPUT, failing closed when a target is not a flake package.
    /// WAWONA_CI_NATIVE=false drops the macOS rows.
    Matrix,
    /// Gate: wasm-wayland. Run the locked Relay SHM guest under the Nix-built
    /// host runtime against headless Weston.
    WasmSmoke,
    /// Grade a WLCS run: GoogleTest XML into summary.json and summary.md.
    WlcsGrade(crate::wlcs::Args),
    /// Import TestFlight screenshot and crash feedback into GitHub issues.
    Testflight(crate::testflight::Args),
    /// Gate iOS against Android snapshots of the same screens.
    UiParity(crate::parity::Args),
    /// Start a command in its own session, so a closing agent or CI shell
    /// cannot hang it up; append its output to --log and print its pid.
    Detach {
        #[arg(long)]
        log: String,
        #[arg(long)]
        pid_file: Option<String>,
        /// Set in the child only: K=V.
        #[arg(long = "env", value_parser = parse_kv)]
        env: Vec<(String, String)>,
        /// Remove from the child's environment.
        #[arg(long)]
        unset: Vec<String>,
        #[arg(last = true, required = true)]
        cmd: Vec<String>,
    },
    /// Wait until a Unix socket accepts a connection; exit 1 after --timeout seconds.
    WaitSocket {
        path: String,
        #[arg(long, default_value_t = 30)]
        timeout: u64,
    },
    /// Run a command, echoing its output, until a line contains MARKER; exit
    /// 124 after --timeout seconds without it.
    Until {
        #[arg(long)]
        marker: String,
        #[arg(long, default_value_t = 60)]
        timeout: u64,
        #[arg(last = true, required = true)]
        cmd: Vec<String>,
    },
}

#[derive(clap::Args)]
pub struct BaselineArgs {
    #[arg(long, default_value = "Wawona/Wawona")]
    repo: String,
    #[arg(long, default_value = "nix.yml")]
    workflow: String,
    /// Runs to inspect.
    #[arg(long, default_value_t = 11)]
    limit: u32,
    #[arg(long, default_value = "ci-failure-baseline.md")]
    out: String,
    #[arg(long, default_value = "ci-failure-baseline.json")]
    out_json: String,
    /// Fail when this run has more than --max-blocker-count jobs per blocker signature.
    #[arg(long)]
    enforce_run_id: Option<String>,
    #[arg(long, num_args = 0.., default_values = ["toolchain_path_missing", "neon_builtin_mismatch", "gradle_daemon"])]
    blocker_signatures: Vec<String>,
    #[arg(long, default_value_t = 0)]
    max_blocker_count: usize,
}

/// Failure signatures, first match wins. docs/android-upgrade-guardrails.md
/// names the blockers among them.
pub const SIGNATURES: &[(&str, &str)] = &[
    ("neon_builtin_mismatch", r"incompatible constant for this __builtin_neon function"),
    ("toolchain_path_missing", r"is not a full path to an existing compiler tool"),
    ("libffi_print_multi_os", r"unsupported option '-print-multi-os-directory'"),
    ("cmake_notfound", r"The following variables are used in this project, but they are set to NOTFOUND"),
    ("cmake_asm_not_set", r"CMAKE_ASM_COMPILER not set"),
    ("cts_unknown_gl_target", r"ninja: error: unknown target 'glcts'"),
    ("cts_unknown_vk_target", r"ninja: error: unknown target 'deqp-vk'"),
    ("gradle_daemon", r"Could not connect to the Gradle daemon"),
    ("ios_errno_missing", r"fatal error: 'errno\.h' file not found"),
    ("network_dns", r"Could not resolve host"),
    ("gradle_oom", r"OutOfMemoryError: Java heap space"),
];

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Baseline(a) => baseline(a),
        Cmd::Matrix => matrix(),
        Cmd::WasmSmoke => wasm_smoke(),
        Cmd::WlcsGrade(a) => crate::wlcs::grade(a),
        Cmd::Testflight(a) => crate::testflight::main(a),
        Cmd::UiParity(a) => crate::parity::main(a),
        Cmd::Until { marker, timeout, cmd } => until(&marker, timeout, &cmd),
        Cmd::Detach { log, pid_file, env, unset, cmd } => detach(&log, pid_file, env, unset, &cmd),
        Cmd::WaitSocket { path, timeout } => {
            let end = std::time::Instant::now() + std::time::Duration::from_secs(timeout);
            while std::os::unix::net::UnixStream::connect(&path).is_err() {
                if std::time::Instant::now() >= end {
                    bail!("{path} accepted no connection within {timeout}s");
                }
                std::thread::sleep(std::time::Duration::from_millis(400));
            }
            Ok(())
        }
    }
}

fn parse_kv(s: &str) -> Result<(String, String)> {
    let (k, v) = s.split_once('=').context("expected K=V")?;
    Ok((k.into(), v.into()))
}

fn detach(
    log: &str,
    pid_file: Option<String>,
    env: Vec<(String, String)>,
    unset: Vec<String>,
    argv: &[String],
) -> Result<()> {
    use std::os::unix::process::CommandExt;
    let out = std::fs::OpenOptions::new().create(true).append(true).open(log)?;
    let mut c = cmd(&argv[0]);
    c.args(&argv[1..]).envs(env).stdin(std::process::Stdio::null()).stdout(out.try_clone()?).stderr(out);
    for k in unset {
        c.env_remove(k);
    }
    // SAFETY: setsid is async-signal-safe and touches no parent state.
    unsafe {
        c.pre_exec(|| if libc::setsid() < 0 { Err(std::io::Error::last_os_error()) } else { Ok(()) });
    }
    let pid = c.spawn().with_context(|| format!("spawn {}", argv[0]))?.id();
    if let Some(p) = pid_file {
        write(p, pid.to_string())?;
    }
    println!("{pid}");
    Ok(())
}

fn wasm_smoke() -> Result<()> {
    const MARKER: &str = "XRGB8888 committed (xdg interactive)";
    let root = root();
    let lock: Value = serde_json::from_str(&read(root.join("flake.lock"))?)?;
    let relay = &lock["nodes"]["wwn-relay"]["locked"];
    let Some(rev) = relay["rev"].as_str() else { bail!("flake.lock has no wwn-relay rev") };
    let (owner, repo) = (relay["owner"].as_str().unwrap_or("Wawona"), relay["repo"].as_str().unwrap_or("Relay"));
    run(cmd("nix").current_dir(&root).args(["build", ".#wawona-wasm", "-o", "result-wawona-wasm", "-L"]))?;
    let runtime = root.join("result-wawona-wasm/bin/wasm");
    if !runtime.is_file() {
        bail!("missing {} (the linux and macos recipes install bin/wasm)", runtime.display());
    }
    let work = std::env::temp_dir().join(format!("wawona-relay-wasm-src-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&work);
    run(cmd("git")
        .args(["clone", "--filter=blob:none", &format!("https://github.com/{owner}/{repo}.git")])
        .arg(&work))?;
    run(cmd("git").arg("-C").arg(&work).args(["checkout", "--quiet", rev]))?;
    let dir = work.join("import/wasm");
    let smoke = dir.join(".github/scripts/smoke-wayland-shm.sh");
    // The locked smoke still asserts the old 256x256 guest; the guest now
    // takes the compositor's size, so accept any committed size.
    let old = "if ! grep -q 'wayland-shm: 256x256 XRGB8888 committed' \"$OUT\"; then";
    let new = "if ! grep -Eq 'wayland-shm: [0-9]+x[0-9]+ XRGB8888 committed' \"$OUT\"; then";
    let src = read(&smoke)
        .with_context(|| format!("locked Relay @{rev} has no import/wasm smoke-wayland-shm.sh; bump wwn-relay"))?;
    if !src.contains(old) {
        bail!("the locked Relay smoke assertion changed; review before adapting it");
    }
    write(&smoke, src.replacen(old, new, 1))?;
    // The guest is interactive and stays open after its first commit.
    let wrapper = work.join("wasm-until-commit");
    let me = std::env::current_exe()?;
    write(
        &wrapper,
        format!("#!/bin/sh\nexec '{}' ci until --marker '{MARKER}' -- '{}' \"$@\"\n", me.display(), runtime.display()),
    )?;
    run(cmd("chmod").arg("+x").arg(&wrapper).arg(&smoke))?;
    run(cmd("rustup").args(["target", "add", "wasm32-wasip1"]))?;
    let r = run(cmd("nix")
        .args(["shell", "nixpkgs#weston", "--command", "./.github/scripts/smoke-wayland-shm.sh"])
        .current_dir(&dir)
        .env("WASM_BIN", &wrapper));
    let _ = std::fs::remove_dir_all(&work);
    r?;
    println!("OK Gate: wasm-wayland");
    Ok(())
}

fn until(marker: &str, timeout: u64, argv: &[String]) -> Result<()> {
    use std::io::{BufRead, BufReader};
    use std::sync::mpsc;
    use std::time::{Duration, Instant};
    let mut child =
        cmd("sh").args(["-c", "exec \"$0\" \"$@\" 2>&1"]).args(argv).stdout(std::process::Stdio::piped()).spawn()?;
    let (tx, rx) = mpsc::channel();
    let out = child.stdout.take().unwrap();
    std::thread::spawn(move || {
        for l in BufReader::new(out).lines() {
            if tx.send(l.unwrap_or_default()).is_err() {
                break;
            }
        }
    });
    let deadline = Instant::now() + Duration::from_secs(timeout);
    loop {
        match rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok(l) => {
                println!("{l}");
                if l.contains(marker) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Ok(());
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                let s = child.wait()?;
                std::process::exit(s.code().unwrap_or(1));
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let _ = child.kill();
                let _ = child.wait();
                eprintln!("error: {marker:?} not seen within {timeout}s");
                std::process::exit(124);
            }
        }
    }
}

fn matrix() -> Result<()> {
    let data: Value = serde_json::from_str(&read(root().join(".github/ci-package-matrix.json"))?)?;
    let mut rows: Vec<&Value> = data["include"].as_array().into_iter().flatten().collect();
    if rows.is_empty() {
        bail!("ci-package-matrix.json include[] is empty");
    }
    let mut by_system: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for r in &rows {
        by_system.entry(r["system"].as_str().unwrap_or("")).or_default().push(r["target"].as_str().unwrap_or(""));
    }
    // One attrNames probe per system: per-target evals would build N Darwin IFD graphs on Linux.
    for (system, targets) in by_system {
        let names: Vec<String> = serde_json::from_str(&output(cmd("nix").current_dir(root()).args([
            "eval",
            "--json",
            &format!(".#packages.{system}"),
            "--apply",
            "builtins.attrNames",
        ]))?)?;
        let missing: Vec<&&str> = targets.iter().filter(|t| !names.iter().any(|n| n == **t)).collect();
        if !missing.is_empty() {
            bail!("matrix targets missing under packages.{system}: {missing:?}");
        }
    }
    if std::env::var("WAWONA_CI_NATIVE").map_or(true, |v| v.to_lowercase() == "true") {
        println!("ci matrix: {} rows", rows.len());
    } else {
        let before = rows.len();
        rows.retain(|r| !r["os"].as_str().unwrap_or("").starts_with("macos"));
        println!("ci matrix: native=false dropped {} Darwin rows", before - rows.len());
        if rows.is_empty() {
            bail!("the path filter removed every matrix row; keep at least one Linux cell");
        }
    }
    let slim: Vec<Value> =
        rows.iter().map(|r| serde_json::json!({"system": r["system"], "os": r["os"], "target": r["target"]})).collect();
    let line = format!("matrix={}\n", serde_json::json!({ "include": slim }));
    match std::env::var("GITHUB_OUTPUT") {
        Ok(p) => std::io::Write::write_all(
            &mut std::fs::OpenOptions::new().append(true).create(true).open(p)?,
            line.as_bytes(),
        )?,
        Err(_) => print!("{line}"),
    }
    Ok(())
}

fn gh_json(args: &[&str]) -> Result<Value> {
    Ok(serde_json::from_str(&output(cmd("gh").args(args))?)?)
}

/// (job name, signature, first error line) for each failed job of a run.
fn failed_jobs(repo: &str, run: &str) -> Result<Vec<(String, String, String)>> {
    let first = Regex::new(r"(error: Cannot build .*|CMake Error:.*|ninja: error:.*|fatal error:.*|clang: error:.*)")?;
    let view = gh_json(&["run", "view", run, "--repo", repo, "--json", "status,conclusion,jobs"])?;
    let mut out = Vec::new();
    for j in view["jobs"].as_array().into_iter().flatten().filter(|j| j["conclusion"] == "failure") {
        let id = j["databaseId"].to_string();
        let log = try_output(cmd("gh").args(["api", &format!("repos/{repo}/actions/jobs/{id}/logs")]))
            .unwrap_or_else(|| "log-fetch-failed".into());
        let sig = SIGNATURES.iter().find(|(_, p)| Regex::new(p).unwrap().is_match(&log)).map_or("unknown", |s| s.0);
        let err = first.captures(&log).map(|m| m[1].trim().to_string()).unwrap_or_default();
        out.push((j["name"].as_str().unwrap_or("").to_string(), sig.to_string(), err));
    }
    Ok(out)
}

fn baseline(a: BaselineArgs) -> Result<()> {
    let runs = gh_json(&[
        "run",
        "list",
        "--repo",
        &a.repo,
        "--workflow",
        &a.workflow,
        "--limit",
        &a.limit.to_string(),
        "--json",
        "databaseId,status,conclusion,displayTitle,createdAt,url",
    ])?;
    let mut md = String::from(
        "# Gate: packages failure baseline\n\n| Run ID | Created | Failed Jobs | Top Signatures |\n|---|---|---:|---|\n",
    );
    let mut details = String::from("\n## Failed Job Details\n\n");
    let mut rows = Vec::new();
    for r in runs.as_array().into_iter().flatten() {
        let id = r["databaseId"].to_string();
        let jobs = failed_jobs(&a.repo, &id)?;
        let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
        for j in &jobs {
            *counts.entry(&j.1).or_default() += 1;
        }
        let mut top: Vec<_> = counts.into_iter().collect();
        top.sort_by_key(|x| std::cmp::Reverse(x.1));
        let top = if top.is_empty() {
            "none".to_string()
        } else {
            top.iter().take(4).map(|(k, v)| format!("{k}:{v}")).collect::<Vec<_>>().join(", ")
        };
        let (created, title) = (r["createdAt"].as_str().unwrap_or(""), r["displayTitle"].as_str().unwrap_or(""));
        md.push_str(&format!("| {id} | {created} | {} | {top} |\n", jobs.len()));
        details.push_str(&format!("### {id}. {title}\n"));
        if jobs.is_empty() {
            details.push_str("- No failed jobs.\n");
        }
        for (name, sig, err) in &jobs {
            if err.is_empty() {
                details.push_str(&format!("- `{name}`: `{sig}`\n"));
            } else {
                details.push_str(&format!("- `{name}`: `{sig}`. `{err}`\n"));
            }
        }
        details.push('\n');
        rows.push(serde_json::json!({"run_id": r["databaseId"], "createdAt": created, "title": title,
            "failed_count": jobs.len(), "top_signatures": top, "failed_jobs": jobs}));
    }
    write(&a.out, md + &details)?;
    write(&a.out_json, serde_json::to_string_pretty(&rows)?)?;
    println!("Wrote {}\nWrote {}", a.out, a.out_json);
    if let Some(run) = &a.enforce_run_id {
        let jobs = failed_jobs(&a.repo, run)?;
        let mut breach = Vec::new();
        for sig in &a.blocker_signatures {
            let n = jobs.iter().filter(|j| &j.1 == sig).count();
            if n > a.max_blocker_count {
                breach.push(format!("{sig}: {n} (max {})", a.max_blocker_count));
            }
        }
        if !breach.is_empty() {
            bail!("blocker threshold exceeded: {}", breach.join(", "));
        }
        println!("Blocker thresholds satisfied.");
    }
    Ok(())
}
