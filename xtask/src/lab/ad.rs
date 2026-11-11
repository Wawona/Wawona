//! The agent-device, simctl and adb steps the lab lanes share.
//!
//! Every lane is zero-AI: recorded `.ad` replays plus the fixed fallbacks
//! below, so CI burns no model credits.

use crate::util::*;
use anyhow::{bail, Result};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

pub const IOS_ID: &str = "com.aspauldingcode.Wawona";
pub const ANDROID_ID: &str = "com.aspauldingcode.wawona";

pub fn artifacts() -> Result<PathBuf> {
    let d = root().join(".agent-device/test-artifacts");
    std::fs::create_dir_all(&d)?;
    Ok(d)
}

pub fn sleep_ms(ms: u64) {
    std::thread::sleep(Duration::from_millis(ms));
}

pub fn require_agent_device() -> Result<()> {
    let Some(v) = try_output(cmd("agent-device").arg("--version")) else {
        bail!("agent-device not found on PATH (nix profile, or npm install -g agent-device)");
    };
    eprintln!("== agent-device {} ==", v.trim());
    Ok(())
}

/// Stops the daemon agent-device recorded for this checkout. Its per-device
/// runner lease outlives the CLI, and a lease the `prepare` daemon holds blocks
/// the daemon `replay` spawns ("already owned by another agent-device daemon").
pub fn stop_daemon() {
    let Some(dir) = try_output(cmd("agent-device").args(["session", "state-dir"])) else { return };
    let state = Path::new(dir.trim()).join("daemon.json");
    let Some(pid) = std::fs::read_to_string(&state)
        .ok()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
        .and_then(|v| v["pid"].as_u64())
    else {
        return;
    };
    let pid = pid as i32;
    let owner = try_output(cmd("ps").args(["-p", &pid.to_string(), "-o", "command="])).unwrap_or_default();
    if !owner.contains("agent-device") {
        return;
    }
    // SAFETY: kill(2) on the pid agent-device recorded, checked just above.
    unsafe { libc::kill(pid, libc::SIGTERM) };
    wait_for(5, 200, || !alive(pid as u32));
    sleep_ms(500);
}

/// One agent-device session: the flags every command in it repeats.
pub struct Ad {
    common: Vec<String>,
}

impl Ad {
    pub fn ios(device: &str, session: &str) -> Ad {
        // A UDID goes on --udid; a name on --device.
        let by = if is_udid(device) { "--udid" } else { "--device" };
        Ad::new(&["--platform", "ios", by, device, "--session", session])
    }

    pub fn android(serial: &str, session: &str) -> Ad {
        Ad::new(&["--platform", "android", "--serial", serial, "--session", session])
    }

    pub fn macos(session: &str) -> Ad {
        Ad::new(&["--platform", "macos", "--session", session])
    }

    pub fn new(common: &[&str]) -> Ad {
        Ad { common: common.iter().map(|s| s.to_string()).collect() }
    }

    pub fn with(mut self, extra: &[&str]) -> Ad {
        self.common.extend(extra.iter().map(|s| s.to_string()));
        self
    }

    pub fn args(&self) -> Vec<String> {
        self.common.clone()
    }

    fn command(&self, args: &[&str]) -> Command {
        let mut c = cmd("agent-device");
        c.args(args).args(&self.common);
        c
    }

    /// Runs with output shown; failure is the caller's.
    pub fn run(&self, args: &[&str]) -> Result<()> {
        run(&mut self.command(args))
    }

    /// Runs with output shown and ignores failure.
    pub fn soft(&self, args: &[&str]) {
        let _ = self.command(args).status();
    }

    /// Runs silently; true on success.
    pub fn ok(&self, args: &[&str]) -> bool {
        self.command(args).stdout(Stdio::null()).stderr(Stdio::null()).status().is_ok_and(|s| s.success())
    }

    pub fn wait(&self, ms: u64) {
        self.soft(&["wait", &ms.to_string()]);
    }

    pub fn visible(&self, selector: &str) -> bool {
        self.ok(&["is", "visible", selector])
    }

    pub fn any_visible(&self, selectors: &[&str]) -> bool {
        selectors.iter().any(|s| self.visible(s))
    }

    pub fn press(&self, selector: &str) -> bool {
        self.ok(&["press", selector])
    }

    pub fn any_press(&self, selectors: &[&str]) -> bool {
        selectors.iter().any(|s| self.press(s))
    }

    pub fn wait_sel(&self, selector: &str, ms: u64) -> bool {
        self.ok(&["wait", selector, &ms.to_string()])
    }

    pub fn find(&self, text: &str, action: &str) -> bool {
        self.ok(&["find", text, action, "--first"])
    }

    pub fn shot(&self, path: &Path) {
        self.soft(&["screenshot", &path.display().to_string()]);
    }

    /// Screenshot plus the raw tree, then the failure.
    pub fn fail(&self, shot: &Path, why: &str) -> anyhow::Error {
        self.shot(shot);
        self.soft(&["snapshot", "-i", "--raw"]);
        anyhow::anyhow!("FAIL: {why}")
    }

    /// The keyboard swipe-typing tutorial's Continue (agent-device, not host taps).
    pub fn dismiss_continue(&self) {
        let _ = self.press("label=\"Continue\"") || self.press("text=\"Continue\"") || self.find("Continue", "press");
    }
}

pub fn is_udid(s: &str) -> bool {
    s.len() >= 20 && s.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

fn simctl(args: &[&str]) -> Option<String> {
    try_output(cmd("xcrun").arg("simctl").args(args))
}

/// The UDID for a simulator name or UDID: a booted match first, then any available one.
pub fn sim_udid(device: &str) -> Option<String> {
    if is_udid(device) {
        return Some(device.into());
    }
    let list: serde_json::Value = serde_json::from_str(&simctl(&["list", "devices", "available", "-j"])?).ok()?;
    let all: Vec<&serde_json::Value> =
        list["devices"].as_object()?.values().filter_map(|v| v.as_array()).flatten().collect();
    let named = |d: &&&serde_json::Value| d["name"].as_str().is_some_and(|n| n.contains(device));
    let pick = all.iter().filter(named).find(|d| d["state"] == "Booted").or_else(|| all.iter().find(named))?;
    pick["udid"].as_str().map(str::to_string)
}

pub fn sim_available(fragment: &str) -> bool {
    simctl(&["list", "devices", "available"]).is_some_and(|l| l.contains(fragment))
}

pub fn ios_device() -> String {
    env_or("WAWONA_IOS_SIM", "iPhone 17 Pro")
}

pub fn boot(device: &str) {
    if simctl(&["bootstatus", device, "-b"]).is_none() {
        let _ = simctl(&["boot", device]);
    }
    let _ = simctl(&["bootstatus", device]);
}

/// Simulator prefs that keep system UI off the lane: no Mac pasteboard sync
/// (the source of CoreSimulatorBridge's Allow Paste alert) and the keyboard
/// tutorials marked seen. Safe to re-run.
pub fn prepare_system_ui(device: &str) {
    let _ = try_output(cmd("defaults").args([
        "write",
        "com.apple.iphonesimulator",
        "PasteboardAutomaticSync",
        "-bool",
        "false",
    ]));
    let Some(udid) = sim_udid(device) else { return };
    let mut pb = cmd("xcrun");
    pb.args(["simctl", "pbcopy", &udid]).stdin(Stdio::null());
    let _ = try_output(&mut pb);
    for (domain, key) in [
        ("com.apple.keyboard", "kbUserDidPath"),
        ("com.apple.keyboard.preferences", "DidShowContinuousPathIntroduction"),
        ("com.apple.keyboard.preferences", "DidShowGestureKeyboardIntroduction"),
        ("com.apple.KeyboardServices", "DidShowContinuousPathIntroduction"),
    ] {
        let _ = simctl(&["spawn", &udid, "defaults", "write", domain, key, "-bool", "YES"]);
    }
}

/// Fresh install of `app`, staged writable: store and artifact bundles are read-only.
pub fn install_ios(device: &str, app: &Path) -> Result<PathBuf> {
    eprintln!("== iOS: install {} ==", app.display());
    let stage = std::env::temp_dir().join(format!("wawona-stage-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&stage);
    std::fs::create_dir_all(&stage)?;
    let staged = stage.join("Wawona.app");
    run(cmd("cp").arg("-R").arg(app).arg(&staged))?;
    run(cmd("chmod").args(["-R", "u+w"]).arg(&staged))?;
    let _ = simctl(&["uninstall", device, IOS_ID]);
    run(cmd("xcrun").args(["simctl", "install", device]).arg(&staged))?;
    Ok(staged)
}

pub fn prepare_runner(ad: &Ad) -> Result<()> {
    ad.run(&["prepare", "ios-runner", "--timeout", &env_or("WAWONA_IOS_PREPARE_TIMEOUT_MS", "600000")])
}

/// Fraction of a 64x64 sample grid brighter than near-black.
pub fn lit_fraction(png: &Path) -> Result<f64> {
    let img = image::open(png)?.to_rgb8();
    let (w, h) = img.dimensions();
    let (mut lit, mut total) = (0u32, 0u32);
    for y in (0..h).step_by((h / 64).max(1) as usize) {
        for x in (0..w).step_by((w / 64).max(1) as usize) {
            total += 1;
            if img.get_pixel(x, y).0.iter().any(|c| *c > 24) {
                lit += 1;
            }
        }
    }
    Ok(lit as f64 / total.max(1) as f64)
}

pub fn assert_lit(png: &Path, label: &str) -> Result<()> {
    let frac = lit_fraction(png)?;
    eprintln!("[{label}] lit-pixel fraction: {frac:.3}");
    if frac <= 0.02 {
        bail!("FAIL: {} is (near-)black", png.display());
    }
    Ok(())
}

pub fn assert_png(png: &Path) -> Result<()> {
    if !png.metadata().is_ok_and(|m| m.len() > 0) {
        bail!("FAIL: missing screenshot {}", png.display());
    }
    Ok(())
}

/// Android through adb, with taps in the 1080x2424 frame the recordings use.
pub struct Adb {
    pub serial: String,
}

const REF_W: f64 = 1080.0;
const REF_H: f64 = 2424.0;

impl Adb {
    /// WAWONA_ANDROID_SERIAL, ANDROID_SERIAL, else the first attached device.
    pub fn find() -> Option<Adb> {
        let serial = std::env::var("WAWONA_ANDROID_SERIAL")
            .or_else(|_| std::env::var("ANDROID_SERIAL"))
            .ok()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                try_output(cmd("adb").arg("devices"))?.lines().skip(1).find_map(|l| {
                    let mut f = l.split_whitespace();
                    let s = f.next()?;
                    (f.next() == Some("device")).then(|| s.to_string())
                })
            })?;
        std::env::set_var("ANDROID_SERIAL", &serial);
        Some(Adb { serial })
    }

    pub fn command(&self) -> Command {
        let mut c = cmd("adb");
        c.args(["-s", &self.serial]);
        c
    }

    pub fn shell(&self, script: &str) -> Option<String> {
        try_output(self.command().args(["shell", script])).map(|s| s.replace('\r', ""))
    }

    pub fn quiet(&self, script: &str) -> bool {
        self.shell(script).is_some()
    }

    pub fn ad(&self, session: &str) -> Ad {
        Ad::android(&self.serial, session)
    }

    /// Fresh install: debug builds rotate keys, so an upgrade can fail INSTALL_FAILED_UPDATE_INCOMPATIBLE.
    pub fn install(&self, apk: &str) -> Result<()> {
        eprintln!("== Android: install {apk} ==");
        let _ = self.shell(&format!("pm uninstall {ANDROID_ID}"));
        run(self.command().args(["install", apk]))
    }

    pub fn install_from_env(&self) -> Result<()> {
        match std::env::var("WAWONA_ANDROID_APK") {
            Ok(apk) if !apk.is_empty() => self.install(&apk),
            _ => Ok(()),
        }
    }

    fn size(&self) -> Option<(f64, f64)> {
        let out = self.shell("wm size")?;
        let dims = out.lines().find_map(|l| l.strip_prefix("Physical size: "))?;
        let (w, h) = dims.trim().split_once('x')?;
        Some((w.parse().ok()?, h.parse().ok()?))
    }

    pub fn scale(&self, x: u32, y: u32) -> (u32, u32) {
        match self.size() {
            Some((w, h)) => ((x as f64 * w / REF_W + 0.5) as u32, (y as f64 * h / REF_H + 0.5) as u32),
            None => (x, y),
        }
    }

    pub fn tap(&self, x: u32, y: u32) -> bool {
        self.quiet(&format!("input tap {x} {y}"))
    }

    pub fn tap_ref(&self, x: u32, y: u32) -> bool {
        let (x, y) = self.scale(x, y);
        self.tap(x, y)
    }

    pub fn key(&self, code: u32) {
        self.quiet(&format!("input keyevent {code}"));
    }

    /// The UiAutomator hierarchy; Compose often hides text from agent-device's filters.
    pub fn uia(&self) -> Option<String> {
        let out = try_output(self.command().args(["exec-out", "uiautomator", "dump", "/dev/tty"]))?;
        if out.contains("<hierarchy") {
            return Some(out);
        }
        let _ = self.shell("uiautomator dump /sdcard/wawona-ui.xml").or_else(|| self.shell("uiautomator dump"))?;
        ["/sdcard/wawona-ui.xml", "/sdcard/window_dump.xml"]
            .iter()
            .filter_map(|p| try_output(self.command().args(["exec-out", "cat", p])))
            .find(|s| s.contains("<hierarchy"))
    }

    pub fn has_text(&self, text: &str) -> bool {
        self.uia().is_some_and(|x| x.contains(&format!("text=\"{text}\"")))
    }

    pub fn has_id(&self, id: &str) -> bool {
        let re = regex::Regex::new(&format!(r#"(?i)resource-id="[^"]*{}""#, regex::escape(id))).unwrap();
        self.uia().is_some_and(|x| re.is_match(&x))
    }

    /// Taps the center of the first node whose attributes match `pattern`.
    fn uia_tap(&self, pattern: &str, label: &str) -> bool {
        let Some(xml) = self.uia() else { return false };
        let node = regex::Regex::new(pattern).unwrap();
        let bounds = regex::Regex::new(r#"bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]""#).unwrap();
        let Some(line) = xml.split('>').find(|l| node.is_match(l)) else { return false };
        let Some(b) = bounds.captures(line) else { return false };
        let n: Vec<u32> = (1..5).map(|i| b[i].parse().unwrap_or(0)).collect();
        let (cx, cy) = ((n[0] + n[2]) / 2, (n[1] + n[3]) / 2);
        if cx == 0 || cy == 0 || n[2] <= n[0] || n[3] <= n[1] {
            return false;
        }
        eprintln!("== Android: uia tap {label} at {cx},{cy} ==");
        self.tap(cx, cy)
    }

    pub fn uia_tap_text(&self, text: &str) -> bool {
        self.uia_tap(&format!(r#"text="{}""#, regex::escape(text)), &format!("text={text}"))
    }

    pub fn uia_tap_id(&self, id: &str) -> bool {
        self.uia_tap(&format!(r#"resource-id="[^"]*{}""#, regex::escape(id)), &format!("id={id}"))
    }

    pub fn screencap(&self, out: &Path) -> Result<()> {
        let png = self.command().args(["exec-out", "screencap", "-p"]).output()?.stdout;
        write(out, png)
    }

    /// The Welcome screen's Continue is a filled blue pill near (540,1390).
    pub fn welcome_continue_visible(&self) -> bool {
        let tmp = std::env::temp_dir().join(format!("wawona-cap-{}.png", std::process::id()));
        let px = self.screencap(&tmp).ok().and_then(|_| image::open(&tmp).ok()).and_then(|img| {
            let (x, y) = self.scale(540, 1390);
            let img = img.to_rgb8();
            (x < img.width() && y < img.height()).then(|| img.get_pixel(x, y).0)
        });
        let _ = std::fs::remove_file(&tmp);
        px.is_some_and(|[r, g, b]| b > 110 && b as i32 > r as i32 + 15 && b > g)
    }

    /// Alt+D, niri's Mod+D in nested mode. `keycombination` exists on API 34+.
    pub fn alt_d(&self) -> bool {
        if self.quiet("input keycombination 57 32") {
            return true;
        }
        eprintln!("WARN: input keycombination unavailable; trying the sendevent Alt+D fallback");
        let dev = self
            .shell("getevent -pl 2>/dev/null | awk '/add device/ {d=$NF} /name:.*Virtual/ {print d; exit}'")
            .unwrap_or_default();
        let dev = dev.trim();
        if dev.is_empty() {
            eprintln!("WARN: no virtual input device for sendevent; Alt+D skipped");
            return false;
        }
        // Linux input codes: KEY_LEFTALT=56, KEY_D=32.
        self.quiet(&format!(
            "sendevent {dev} 1 56 1; sendevent {dev} 1 32 1; sendevent {dev} 0 0 0; sendevent {dev} 1 32 0; sendevent {dev} 1 56 0; sendevent {dev} 0 0 0"
        ))
    }

    /// System dialogs and ANR prompts that eat taps.
    pub fn dismiss_blockers(&self, ad: &Ad) {
        self.quiet("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS");
        ad.ok(&["alert", "dismiss"]);
        for label in ["label=\"Wait\"", "label=\"Close app\""] {
            if ad.visible(label) {
                ad.press(label);
            }
        }
    }

    /// id= first (Compose testTagsAsResourceId), then the UiAutomator bounds.
    pub fn press_id(&self, ad: &Ad, id: &str) -> bool {
        ad.press(&format!("id=\"{id}\"")) || self.uia_tap_id(id)
    }

    pub fn press_text(&self, ad: &Ad, text: &str) -> bool {
        self.uia_tap_text(text)
            || ad.find(text, "press")
            || ad.press(&format!("label=\"{text}\""))
            || ad.press(&format!("text=\"{text}\""))
    }

    /// One pass over the Welcome screen; CI is fail-fast.
    pub fn dismiss_welcome(&self, ad: &Ad) {
        if self.has_id("wwn.machines.root") || self.has_text("Machine Configuration") {
            return;
        }
        let _ = self.press_id(ad, "wwn.welcome.continue");
        let _ = self.press_text(ad, "Continue");
        self.tap_ref(540, 1404);
        self.tap(540, 1404);
        ad.wait(2500);
        self.dismiss_blockers(ad);
    }

    /// Settles the immersive-mode coach mark that blocks compositor input.
    pub fn quiet_immersive(&self) {
        self.quiet("settings put secure immersive_mode_confirmations confirmed");
    }
}
