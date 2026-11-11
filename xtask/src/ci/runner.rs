//! Runner-side steps: the branch-tip supersede, the Xcode pin, Apple SDK
//! warm-up, product artifact handoff, transient-failure retry and the Nix
//! producer gates.

use crate::util::*;
use anyhow::{bail, Context, Result};
use std::time::{Duration, Instant};

/// Appends `K=V` lines to the file a GitHub Actions variable names, or
/// prints them outside Actions.
pub fn gh_append(var: &str, lines: &[String]) -> Result<()> {
    let body: String = lines.iter().map(|l| format!("{l}\n")).collect();
    match std::env::var(var) {
        Ok(p) if !p.is_empty() => std::io::Write::write_all(
            &mut std::fs::OpenOptions::new().append(true).create(true).open(p)?,
            body.as_bytes(),
        )?,
        _ => print!("{body}"),
    }
    Ok(())
}

fn env(k: &str) -> String {
    std::env::var(k).unwrap_or_default()
}

/// Soft supersede for WIP CI (wawona-ci-no-cancel): an obsolete commit sets
/// is_tip=false and stays green; the tip runs the real checks. Always exits 0.
pub fn tip(force: bool) -> Result<()> {
    let (event, sha, branch) = (env("GITHUB_EVENT_NAME"), env("GITHUB_SHA"), env("GITHUB_REF_NAME"));
    let (is_tip, reason, human): (bool, String, String) = if force || env("WAWONA_CI_FORCE_TIP") == "1" {
        (true, "force".into(), "Forced run. Checking this commit.".into())
    } else if matches!(event.as_str(), "workflow_dispatch" | "schedule" | "release") {
        (true, format!("event:{event}"), "Manual or scheduled run. Checking this commit.".into())
    } else if event == "workflow_call" && !env("WAWONA_CI_INTENDED_REF").is_empty() {
        (true, format!("workflow_call:{}", env("WAWONA_CI_INTENDED_REF")), "Called for a specific ref.".into())
    } else if sha.is_empty() || branch.is_empty() {
        (true, "missing-sha-or-ref".into(), "Could not read commit or branch. Running checks to be safe.".into())
    } else if event == "pull_request" {
        (true, "pull_request".into(), "Pull request. Running checks on this PR commit.".into())
    } else {
        let _ = cmd("git").args(["fetch", "--no-tags", "--depth=1", "origin", &branch]).output();
        match try_output(cmd("git").args(["rev-parse", &format!("origin/{branch}")])) {
            None => (true, "tip-unresolved".into(), "Could not see the branch tip. Running checks to be safe.".into()),
            Some(t) if t == sha => (true, "branch-tip".into(), format!("This is the latest commit on {branch}.")),
            Some(t) => (
                false,
                format!("superseded:tip={}:sha={}", &t[..7], &sha[..sha.len().min(7)]),
                format!("Not the latest commit anymore (newer: {}). Skipping. This is OK, not a failure.", &t[..7]),
            ),
        }
    };
    gh_append("GITHUB_OUTPUT", &[format!("is_tip={is_tip}"), format!("reason={reason}")])?;
    if !env("GITHUB_STEP_SUMMARY").is_empty() {
        let verdict = if is_tip { "**YES. Run the checks.**" } else { "**NO. Skipped (not a failure).**" };
        gh_append(
            "GITHUB_STEP_SUMMARY",
            &[
                format!("# Latest commit?\n\n{verdict}\n\n{human}\n"),
                format!("- Branch: `{branch}`\n- This commit: `{sha}`"),
            ],
        )?;
    }
    println!("Latest commit: {}. {human}", if is_tip { "YES" } else { "NO (skipped)" });
    Ok(())
}

/// The CI Xcode pin (the macos-27 image). Bumping it is a deliberate change:
/// a silent newest-Xcode selection invalidates the impure Apple hashes.
const XCODE_APP: &str = "/Applications/Xcode_27.2.app";

/// Selects the pinned Xcode 27 (WAWONA_XCODE_APP or WAWONA_XCODE_VERSION
/// override it) and exports DEVELOPER_DIR to the job.
pub fn select_xcode() -> Result<()> {
    let app = match (env("WAWONA_XCODE_APP"), env("WAWONA_XCODE_VERSION")) {
        (a, _) if !a.is_empty() => a,
        (_, v) if !v.is_empty() => format!("/Applications/Xcode_{v}.app"),
        _ => XCODE_APP.into(),
    };
    // Runner images often symlink Xcode_27.2.app to a release candidate.
    let app = std::fs::canonicalize(&app).with_context(|| {
        let have: Vec<_> = std::fs::read_dir("/Applications")
            .into_iter()
            .flatten()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.starts_with("Xcode"))
            .collect();
        format!(
            "pinned Xcode {app} not found (installed: {have:?}); set WAWONA_XCODE_APP or bump the pin in ci/runner.rs"
        )
    })?;
    let dev = app.join("Contents/Developer");
    run(cmd("sudo").arg("xcode-select").arg("-s").arg(&app))?;
    let out = output(cmd(dev.join("usr/bin/xcodebuild")).arg("-version"))?;
    println!("Selected Xcode (pinned): {}\n{out}", app.display());
    let ver = out.lines().find_map(|l| l.strip_prefix("Xcode ")).unwrap_or_default().to_string();
    if !ver.starts_with("27") {
        bail!("Wawona requires Xcode 27 (SDK 27); selected {ver}");
    }
    let path = format!("{}/usr/bin:{}", dev.display(), env("PATH"));
    gh_append(
        "GITHUB_ENV",
        &[
            format!("DEVELOPER_DIR={}", dev.display()),
            format!("XCODE_APP={}", app.display()),
            format!("PATH={path}"),
            "TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault".into(),
        ],
    )?;
    gh_append(
        "GITHUB_OUTPUT",
        &[format!("version={ver}"), format!("developer_dir={}", dev.display()), format!("xcode_app={}", app.display())],
    )
}

fn sdk_present(token: &str) -> bool {
    try_output(cmd("xcrun").args(["--sdk", token, "--show-sdk-path"]))
        .is_some_and(|p| std::path::Path::new(&p).is_dir())
}

/// Makes the platform SDKs the given Apple targets need visible to xcrun,
/// downloading the platform packs that are missing.
pub fn warm_sdk(platforms: &[String]) -> Result<()> {
    let platforms: Vec<&str> = match platforms.iter().map(String::as_str).collect::<Vec<_>>() {
        p if p.is_empty() => vec!["ios"],
        p if p.contains(&"all") => vec!["ios", "tvos", "watchos", "visionos"],
        p => p,
    };
    let table = |p: &str| match p {
        "ios" | "ipados" => Ok(("iphonesimulator", "iphoneos", "iOS")),
        "tvos" => Ok(("appletvsimulator", "appletvos", "tvOS")),
        "watchos" => Ok(("watchsimulator", "watchos", "watchOS")),
        "visionos" => Ok(("xrsimulator", "xros", "xrOS")),
        _ => bail!("unknown platform {p} (ios, ipados, tvos, watchos, visionos, all)"),
    };
    // The tv, watch and vision device packs are separate downloads.
    let device = platforms.iter().any(|p| matches!(*p, "tvos" | "watchos" | "visionos"));
    let mut need: Vec<(&'static str, &'static str)> = vec![("iphoneos", "iOS")];
    for p in &platforms {
        let (sim, dev, pack) = table(p)?;
        need.push((sim, pack));
        if device {
            need.push((dev, pack));
        }
    }
    need.sort();
    need.dedup();
    let missing =
        |n: &[(&'static str, &'static str)]| n.iter().filter(|(t, _)| !sdk_present(t)).cloned().collect::<Vec<_>>();
    let mut m = missing(&need);
    if !m.is_empty() {
        println!("warming platforms for {m:?}");
        let mut packs: Vec<&str> = m.iter().map(|(_, p)| *p).collect();
        packs.dedup();
        for p in packs {
            if !cmd("xcodebuild").args(["-downloadPlatform", p]).status()?.success() {
                println!("::warning::xcodebuild -downloadPlatform {p} failed");
            }
        }
        for _ in 0..15 {
            m = missing(&need);
            if m.is_empty() {
                break;
            }
            std::thread::sleep(Duration::from_secs(3));
        }
    }
    if m.is_empty() {
        println!("all required Apple SDK paths present");
        gh_append("GITHUB_ENV", &["WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1".into()])
    } else {
        println!("::warning::still missing SDK paths: {m:?}");
        Ok(())
    }
}

/// Workflows whose runs upload product-* artifacts.
const PRODUCERS: &[&str] = &[
    "device-gate.yml",
    "release.yml",
    "product-build.yml",
    "product-ios-sim.yml",
    "product-android-apk.yml",
    "product-macos-app.yml",
    "product-appimage.yml",
    "product-apple-family.yml",
    "product-ios-modeb.yml",
];

/// Downloads a product artifact a successful run built for `sha`, waiting
/// while a producer for it is still running. Fails fast when none is.
pub fn fetch_product(sha: &str, artifact: &str, dest: &str, wait: u64) -> Result<()> {
    let repo = crate::util::env_or("GITHUB_REPOSITORY", "Wawona/Wawona");
    let grace = Duration::from_secs(env("RESOLVE_PRODUCT_GRACE_SECS").parse().unwrap_or(120));
    let (start, deadline) = (Instant::now(), Instant::now() + Duration::from_secs(wait));
    let runs = |wf: &str, filter: &str| -> Vec<String> {
        try_output(cmd("gh").args([
            "run",
            "list",
            "--repo",
            &repo,
            "--workflow",
            wf,
            "--commit",
            sha,
            "--limit",
            "30",
            "--json",
            "databaseId,status,conclusion",
            "--jq",
            &format!("[.[] | select({filter})] | .[].databaseId"),
        ]))
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
    };
    let has = |id: &str| {
        try_output(cmd("gh").args([
            "api",
            &format!("repos/{repo}/actions/runs/{id}/artifacts"),
            "--jq",
            &format!("[.artifacts[] | select(.name == \"{artifact}\" and .expired == false)] | length > 0"),
        ]))
        .is_some_and(|o| o == "true")
    };
    let run_id = loop {
        if let Some(id) = PRODUCERS
            .iter()
            .flat_map(|wf| runs(wf, r#".status=="completed" and .conclusion=="success""#))
            .find(|id| has(id))
        {
            break id;
        }
        if Instant::now() >= deadline {
            bail!("no successful product run with artifact {artifact} for {sha} within {wait}s");
        }
        if PRODUCERS.iter().any(|wf| !runs(wf, r#".status=="in_progress" or .status=="queued""#).is_empty()) {
            println!("== a product run for {sha} is still running; waiting for {artifact} ==");
            std::thread::sleep(Duration::from_secs(30));
        } else if start.elapsed() >= grace {
            bail!("no product producer is running for {sha} after {}s (artifact {artifact}); call a product-*.yml from this workflow instead", grace.as_secs());
        } else {
            std::thread::sleep(Duration::from_secs(15));
        }
    };
    std::fs::create_dir_all(dest)?;
    println!("== downloading {artifact} from run {run_id} into {dest} ==");
    run(cmd("gh").args(["run", "download", &run_id, "--repo", &repo, "--name", artifact, "--dir", dest]))
}

/// Network flakes, and the read-only MetalToolchain cleanup Xcode can fail
/// on after a successful build.
const TRANSIENT: &str = r"Could not resolve host|HTTP error 418|timed out|Connection reset by peer|502 Bad Gateway|503 Service Unavailable|504 Gateway Timeout|cannot unlink .*Read-only file system|MetalToolchain/.*/RestoreVersion\.plist";

/// Runs a command up to three times, retrying only transient failures.
pub fn retry(argv: &[String]) -> Result<()> {
    let transient = regex::Regex::new(TRANSIENT)?;
    for attempt in 1..=3 {
        println!("==> attempt {attempt}/3: {}", argv.join(" "));
        let mut c = cmd(&argv[0]);
        c.args(&argv[1..]).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::piped());
        let out = c.output()?;
        let log = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        print!("{log}");
        if out.status.success() {
            return Ok(());
        }
        if !transient.is_match(&log) || attempt == 3 {
            break;
        }
        println!("transient failure; retrying in {}s", attempt * 20);
        std::thread::sleep(Duration::from_secs(attempt * 20));
    }
    bail!("{} failed (non-retryable, or retries exhausted)", argv.join(" "))
}

/// Clones wwn-toolchain and repo.wawona.io at their flake.lock revisions,
/// for the cross-repository checks on a Wawona-only checkout.
pub fn flake_inputs() -> Result<()> {
    let lock: serde_json::Value = serde_json::from_str(&read(root().join("flake.lock"))?)?;
    for (input, dir) in [("wwn-toolchain", "wwn-toolchain"), ("repo-wawona-io", "repo.wawona.io")] {
        let dest = root().join(dir);
        if dest.join(".git").exists() {
            println!("using existing {}", dest.display());
            continue;
        }
        let l = &lock["nodes"][input]["locked"];
        let rev = l["rev"].as_str().with_context(|| format!("flake.lock has no locked rev for {input}"))?;
        // FlakeHub tarball locks omit owner and repo; DAG nodes are Wawona/<input>.
        let owner = l["owner"].as_str().unwrap_or("Wawona");
        let repo = l["repo"].as_str().unwrap_or(input);
        run(cmd("git")
            .args(["clone", "--filter=blob:none", &format!("https://github.com/{owner}/{repo}.git")])
            .arg(&dest))?;
        run(cmd("git").arg("-C").arg(&dest).args(["checkout", rev]))?;
    }
    Ok(())
}

/// Nix producer gates: the bundled shell tools, and the Android meson stack
/// under a sandbox that denies /usr/bin/env (NIX_SANDBOX, default relaxed).
pub fn nix_gate(group: &str) -> Result<()> {
    let (attrs, extra): (&[&str], Vec<String>) = match group {
        "shell-tools" => (
            &[
                "zsh-ios-sim",
                "fastfetch-ios",
                "phoon-ios",
                "phoon-tvos",
                "phoon-watchos",
                "phoon-visionos",
                "wawona-pty-ios-sim",
                "wawona-rootfs-ios-sim",
                "zsh-android",
                "fastfetch-android",
                "phoon-android",
            ],
            vec!["--print-build-logs".into()],
        ),
        "android-meson" => {
            let mut e = vec!["--no-link".into(), "--option".into(), "sandbox".into(), env_or("NIX_SANDBOX", "relaxed")];
            for (k, input) in [("WWN_TOOLCHAIN_ROOT", "wwn-toolchain"), ("REPO_WAWONA_IO_ROOT", "repo-wawona-io")] {
                if std::path::Path::new(&env(k)).is_dir() && !env(k).is_empty() {
                    e.extend(["--override-input".into(), input.into(), format!("path:{}", env(k))]);
                }
            }
            if env("VERIFY_REBUILD") == "1" {
                e.push("--rebuild".into());
            }
            (
                &[
                    "freetype-android",
                    "fontconfig-android",
                    "pixman-android",
                    "cairo-android",
                    "glib-android",
                    "harfbuzz-android",
                    "fribidi-android",
                    "pango-android",
                    "weston-android",
                    "weston-compositor-android",
                ],
                e,
            )
        }
        _ => bail!("unknown Nix gate {group} (shell-tools, android-meson)"),
    };
    let mut c = cmd("nix");
    c.arg("build").args(attrs.iter().map(|a| format!(".#{a}"))).args(extra).current_dir(root());
    run(&mut c)?;
    println!("nix gate {group}: OK");
    Ok(())
}
