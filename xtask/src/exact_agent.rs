//! Exact agent driver wrapped for cargo xtask (bun under a Rust flow).
//!
//! Exact UI is agent-controllable (`bun exact.mjs agent …`). Agents must not
//! use host computer-use for Exact chrome. This module is the Wawona entry:
//! `cargo xtask agent macos …` and `cargo xtask agent grade macos`.

use crate::exact_host::{self, app_dir, exact_root};
use crate::product::{self, RunArgs};
use crate::util::{cmd, root, run};
use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Subcommand)]
pub enum Cmd {
    /// Drive Exact UI via `bun exact.mjs agent` (pass-through ops after `--`).
    #[command(name = "drive", visible_alias = "run")]
    Drive(DriveArgs),
    /// Full Exact chrome grade: rebuild optional, drive every screen-graph route, write history JSON stub path.
    Grade(GradeArgs),
}

#[derive(Parser)]
pub struct DriveArgs {
    /// Exact agent host: macos, ios, web, linux, android, windows.
    pub host: String,
    /// Viewport `WxH` (macOS Exact chrome default 900x700 for wide split).
    #[arg(long, default_value = "900x700")]
    pub size: String,
    /// Named Exact scratch store.
    #[arg(long)]
    pub storage: Option<String>,
    /// Forward `--json` to Exact agent.
    #[arg(long)]
    pub json: bool,
    /// Exact agent ops (`tree`, `tap …`, `screenshot …`, …).
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub ops: Vec<String>,
}

#[derive(Parser)]
pub struct GradeArgs {
    /// Host to grade (macos today for Exact chrome loop).
    pub host: String,
    /// Rebuild `.build/exact/<host>/Wawona.app` before the drive.
    #[arg(long)]
    pub rebuild: bool,
    /// Also `open` the app via `cargo xtask run` (human watch). Agent drive still owns evidence.
    #[arg(long)]
    pub open: bool,
    /// Directory for screenshots (default: docs/ui-quality/history/artifacts).
    #[arg(long)]
    pub out: Option<PathBuf>,
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Drive(a) => drive(a),
        Cmd::Grade(a) => grade(a),
    }
}

fn drive(a: DriveArgs) -> Result<()> {
    if a.ops.is_empty() {
        bail!("cargo xtask agent drive: pass Exact ops (e.g. tree state)");
    }
    let chrome = if a.host == "macos" {
        Some("platform")
    } else {
        None
    };
    run_agent(
        &a.host,
        &a.size,
        a.storage.as_deref(),
        a.json,
        chrome,
        &a.ops,
    )
}

/// Keep the panel awake for CGWindowListCreateImage during a long grade.
/// Initial HID poke + parent `caffeinate -dims`, then periodic F5 / `-u`.
struct DisplayWakeGuard {
    stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
    join: Option<std::thread::JoinHandle<()>>,
    _caffeinate: Option<std::process::Child>,
}

impl DisplayWakeGuard {
    fn poke_hid() {
        // F5 only. Escape (53) wakes some panels but dismisses Exact modal
        // sheets mid-grade (Settings / Add) and empties CGWindow captures.
        let _ = std::process::Command::new("osascript")
            .args(["-e", "tell application \"System Events\" to key code 96"])
            .status();
        let _ = std::process::Command::new("caffeinate")
            .args(["-u", "-t", "2"])
            .status();
    }

    fn arm() -> Self {
        Self::poke_hid();
        let caffeinate = std::process::Command::new("caffeinate")
            .args(["-dims", "-w", &std::process::id().to_string()])
            .spawn()
            .ok();
        let stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let flag = stop.clone();
        let join = std::thread::spawn(move || {
            while !flag.load(std::sync::atomic::Ordering::Relaxed) {
                Self::poke_hid();
                for _ in 0..20 {
                    if flag.load(std::sync::atomic::Ordering::Relaxed) {
                        return;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(100));
                }
            }
        });
        Self {
            stop,
            join: Some(join),
            _caffeinate: caffeinate,
        }
    }
}

impl Drop for DisplayWakeGuard {
    fn drop(&mut self) {
        self.stop
            .store(true, std::sync::atomic::Ordering::Relaxed);
        if let Some(h) = self.join.take() {
            let _ = h.join();
        }
        if let Some(mut c) = self._caffeinate.take() {
            let _ = c.kill();
        }
    }
}

fn grade(a: GradeArgs) -> Result<()> {
    if a.host != "macos" {
        bail!(
            "cargo xtask agent grade: macos Exact chrome loop only today (got {})",
            a.host
        );
    }
    // Hold display + idle sleep off for the whole grade. CGWindowListCreateImage
    // returns an empty picture when the display is asleep / locked.
    // `caffeinate -d` does not wake an already-asleep panel; poke HID first.
    // Mid-pass the panel can still sleep (long settle clocks); keep poking.
    let _wake = DisplayWakeGuard::arm();
    if a.rebuild {
        // Contract UI loop: bun Exact rebuild only. Full deps/backend via
        // `cargo xtask build macos`.
        let t = exact_host::target("macos")?;
        let tip = exact_host::build_apple_quick(&t)?;
        eprintln!("cargo xtask agent grade: rebuilt {}", tip.display());
        // Tip relaunch can leave CGWindowList empty for a beat (asleep /
        // offscreen). Wall wait before the agent opens.
        std::thread::sleep(std::time::Duration::from_millis(4500));
    }
    if a.open {
        product::run_app(RunArgs {
            target: "macos".into(),
            no_rebuild: true,
        })?;
    }

    let out = a.out.unwrap_or_else(|| {
        root().join("docs/ui-quality/history/artifacts")
    });
    std::fs::create_dir_all(&out).with_context(|| format!("mkdir {}", out.display()))?;
    let stamp = chrono_stamp();
    let shot = |name: &str| out.join(format!("{stamp}-{name}.png")).display().to_string();

    // Full screen-graph pass. Targets are contract testIds.
    // Wide Mac: browser pane owns New/Settings/search; sidebar stays sourceList.
    // Prefer `screenshot … window` (viewport readback can answer no sRGB PNG).
    // Chunked: long single agent runs lose CGWindow when the panel sleeps;
    // poke HID between chunks (DisplayWakeGuard alone is not enough).
    let storage = format!("wawona-grade-{stamp}");
    let chunks: [Vec<String>; 3] = [
        vec![
            "tree".into(),
            "state window".into(),
            "clock settle".into(),
            "clock +2000 real".into(),
            "tap machines-search".into(),
            "clock settle".into(),
            "state window".into(),
            "clock +800 real".into(),
            "tap machines-search".into(),
            "clock settle".into(),
            format!("screenshot {} window", shot("catalog")),
            // Inset-grouped list rows (unsaid list-detail). Not card browser ids.
            "tap wwn.machines.row.auth51".into(),
            "clock settle".into(),
            format!("screenshot {} window", shot("inspector-planned")),
            "back".into(),
            "clock settle".into(),
        ],
        {
            DisplayWakeGuard::poke_hid();
            vec![
                "clock +1200 real".into(),
                "tap toolbar-settings".into(),
                "clock settle".into(),
                "clock +800 real".into(),
                format!("screenshot {} window", shot("settings-display")),
                "tree".into(),
                "tap settings-all-categories".into(),
                "clock settle".into(),
                "clock +800 real".into(),
                format!("screenshot {} window", shot("settings")),
                "back".into(),
                "clock settle".into(),
                "tap machine-add".into(),
                "clock settle".into(),
                "clock +500 real".into(),
                format!("screenshot {} window", shot("add")),
                "back".into(),
                "clock settle".into(),
            ]
        },
        {
            DisplayWakeGuard::poke_hid();
            vec![
                // Library tabs → Mac sourceList. Sessions only here: switching
                // Sessions → Machines re-enters SplitHost reveal and can hang
                // the agent (120s). Machines inspector already graded in chunk 1.
                "tap wwn.nav.sessions".into(),
                "clock settle".into(),
                format!("screenshot {} window", shot("tabs")),
                "tap wwn.nav.images".into(),
                "clock settle".into(),
                format!("screenshot {} window", shot("images")),
                "tap wwn.nav.runtimes".into(),
                "clock settle".into(),
                format!("screenshot {} window", shot("runtimes")),
                "tree".into(),
                "state window".into(),
            ]
        },
    ];

    for (i, ops) in chunks.iter().enumerate() {
        if i > 0 {
            DisplayWakeGuard::poke_hid();
            std::thread::sleep(std::time::Duration::from_millis(400));
        }
        run_agent(
            "macos",
            "900x700",
            Some(&storage),
            false,
            Some("platform"),
            ops,
        )?;
    }
    eprintln!(
        "cargo xtask agent grade: screenshots under {}\nWrite score JSON to docs/ui-quality/history/ using the rubric.",
        out.display()
    );
    Ok(())
}

fn run_agent(
    host: &str,
    size: &str,
    storage: Option<&str>,
    json: bool,
    chrome: Option<&str>,
    ops: &[String],
) -> Result<()> {
    let exact = exact_root()?;
    let app = app_dir(&exact);
    // Relative path required: absolute `…/scripts/exact.mjs` resolves as the
    // app-facing `exact` shim ("no verb agent"). Drive via agent.mjs directly.
    let mut c = cmd(exact_host::bun());
    c.current_dir(&exact)
        .arg("scripts/agent.mjs")
        .arg(host)
        .arg("--app")
        .arg("wawona")
        .arg("--size")
        .arg(size)
        .env("EXACT_APP_DIR", &app)
        .env("EXACT_ROOT", &exact);
    // Exact agent asks rustc for its host; cargo bin must be on PATH.
    if let Some(home) = std::env::var_os("HOME") {
        let cargo_bin = PathBuf::from(home).join(".cargo/bin");
        let path = std::env::var_os("PATH").unwrap_or_default();
        let mut parts = std::env::split_paths(&path).collect::<Vec<_>>();
        if !parts.iter().any(|p| p == &cargo_bin) {
            parts.insert(0, cargo_bin);
            if let Ok(joined) = std::env::join_paths(parts) {
                c.env("PATH", joined);
            }
        }
    }

    // Prefer the Wawona-mirrored tip when present so grade matches `xtask run`.
    let tip_bin = root()
        .join(".build/exact/macos/Wawona.app/Contents/MacOS/Wawona");
    if host == "macos" && tip_bin.is_file() {
        c.env("EXACT_MAC_BIN", &tip_bin);
    }

    if let Some(s) = storage {
        c.arg("--storage").arg(s);
    }
    if let Some(chrome) = chrome {
        c.arg("--chrome").arg(chrome);
    }
    if json {
        c.arg("--json");
    }
    for op in ops {
        c.arg(op);
    }
    run(&mut c)
}

fn chrono_stamp() -> String {
    // Local calendar day + HMS without pulling chrono (keep xtask light).
    let out = std::process::Command::new("date")
        .arg("+%Y-%m-%dT%H%M%S")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_else(|| "now".into());
    out.trim().to_string()
}
