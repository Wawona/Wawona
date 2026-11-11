//! `cargo xtask lab matrix [platform...]`: every bundled client on every
//! target that has a runnable build, with a summary naming each FAIL cell.
//!
//! Apple simulators and macOS start the client through WAWONA_AUTO_CLIENT
//! (the Machines Start path, no XCUITest runner to time out on cold CI);
//! WAWONA_MATRIX_USE_AGENT_DEVICE=1 presses Start instead. Android drives
//! Start through adb and UiAutomator.

use super::ad::*;
use super::clients;
use crate::util::*;
use anyhow::{bail, Result};
use serde_json::json;
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};

const PLATFORMS: &[&str] = &["ios", "ipados", "visionos", "tvos", "watchos", "android", "macos"];

struct Row {
    platform: String,
    client: String,
    status: &'static str,
    reason: String,
    hold: u64,
    dir: PathBuf,
}

struct Gate {
    out: PathBuf,
    rows: Vec<Row>,
}

impl Gate {
    fn log(&self, line: &str) {
        eprintln!("{line}");
        let mut f = std::fs::OpenOptions::new().create(true).append(true).open(self.out.join("matrix.log")).unwrap();
        let _ = std::io::Write::write_all(&mut f, format!("{line}\n").as_bytes());
    }

    fn record(&mut self, platform: &str, client: &str, status: &'static str, reason: String, hold: u64, dir: &Path) {
        self.log(&format!("RESULT {platform}/{client}: {status}. {reason}"));
        self.rows.push(Row { platform: platform.into(), client: client.into(), status, reason, hold, dir: dir.into() });
    }
}

fn sim_for(platform: &str) -> String {
    match platform {
        "ipados" => env_or("WAWONA_IPAD_SIM", "iPad Pro 13-inch (M5)"),
        "visionos" => env_or("WAWONA_VISION_SIM", "Apple Vision Pro"),
        "tvos" => env_or("WAWONA_TVOS_SIM", "Apple TV 4K (3rd generation)"),
        "watchos" => env_or("WAWONA_WATCH_SIM", "Apple Watch Series 11 (46mm)"),
        _ => ios_device(),
    }
}

fn app_for(platform: &str) -> String {
    let (var, default) = match platform {
        "ipados" => ("WAWONA_IPAD_APP", "/tmp/wawona-ipad-gate.app"),
        "visionos" => ("WAWONA_VISION_APP", "/tmp/wawona-vision-gate.app"),
        "tvos" => ("WAWONA_TVOS_APP", "/tmp/wawona-tvos-gate.app"),
        "watchos" => ("WAWONA_WATCH_APP", "/tmp/wawona-watch-gate.app"),
        "macos" => ("WAWONA_MACOS_APP", ""),
        "android" => ("WAWONA_ANDROID_APK", ""),
        _ => ("WAWONA_IOS_APP", "/tmp/wawona-ios-gate.app"),
    };
    env_or(var, default)
}

fn bundle_for(platform: &str) -> String {
    match platform {
        "watchos" => env_or("WAWONA_WATCH_BUNDLE", "com.aspauldingcode.Wawona.watch"),
        _ => env_or("WAWONA_IOS_BUNDLE", IOS_ID),
    }
}

fn hold_for(client: &str) -> u64 {
    std::env::var("WAWONA_MATRIX_HOLD").ok().and_then(|h| h.parse().ok()).unwrap_or_else(|| clients::hold_secs(client))
}

fn scan_fail(log: &Path) -> Option<&'static str> {
    let text = std::fs::read_to_string(log).unwrap_or_default().to_lowercase();
    clients::FAIL_PATTERNS.iter().copied().find(|p| text.contains(&p.to_lowercase()))
}

/// iOS 26 labels the job UIKitApplication:<bundle>[...].
fn apple_pid(udid: &str, bundle: &str) -> Option<u32> {
    let list = try_output(cmd("xcrun").args(["simctl", "spawn", udid, "launchctl", "list"]))?;
    list.lines().filter(|l| l.contains(bundle)).find_map(|l| l.split_whitespace().next()?.parse().ok())
}

fn sim_log(udid: &str, out: &Path) -> Option<Child> {
    let f = std::fs::File::create(out).ok()?;
    cmd("xcrun")
        .args(["simctl", "spawn", udid, "log", "stream", "--level", "debug", "--predicate"])
        .arg(r#"processImagePath CONTAINS "Wawona" OR eventMessage CONTAINS "Wawona" OR eventMessage CONTAINS "WESTON" OR eventMessage CONTAINS "NIRI" OR eventMessage CONTAINS "niri" OR eventMessage CONTAINS "Launching""#)
        .stdout(f.try_clone().ok()?)
        .stderr(f)
        .spawn()
        .ok()
}

fn stop(child: Option<Child>) {
    if let Some(mut c) = child {
        let _ = c.kill();
        let _ = c.wait();
    }
}

/// Machines Start through agent-device; the first open on a cold session can
/// time out building the runner, so the sequence runs twice.
fn agent_device_start(platform: &str, sim: &str, bundle: &str, cell: &Path) -> bool {
    let plat = if platform == "ipados" { "ios" } else { platform };
    let ad = Ad::new(&["--platform", plat, "--device", sim, "--session", &format!("wawona-{platform}-matrix")]);
    for _ in 0..2 {
        ad.ok(&["open", bundle, "--relaunch"]);
        ad.wait(3000);
        ad.ok(&["alert", "dismiss"]);
        if !ad.visible("id=\"wwn.machines.root\"") {
            let _ = ad.press("id=\"wwn.welcome.continue\"")
                || ad.press("label=\"Continue\"")
                || ad.find("Continue", "press");
            ad.wait(1500);
            ad.ok(&["alert", "dismiss"]);
        }
        if ad.press("id=\"wwn.machines.start\"") || ad.press("label=\"Start\"") || ad.find("Start", "press") {
            ad.wait(3000);
            ad.shot(&cell.join("running.png"));
            return true;
        }
        ad.wait(2000);
    }
    ad.fail(&cell.join("start-fail.png"), "Start not pressed");
    false
}

fn apple_cell(g: &mut Gate, platform: &str, client: &str) -> Result<()> {
    let (app, sim, bundle) = (app_for(platform), sim_for(platform), bundle_for(platform));
    let cell = g.out.join(platform).join(client);
    std::fs::create_dir_all(&cell)?;
    let hold = hold_for(client);
    if let Some(skip) = clients::skip_reason(platform, client) {
        g.record(platform, client, "SKIP", skip, hold, &cell);
        return Ok(());
    }
    if app.is_empty() || !Path::new(&app).is_dir() {
        g.record(platform, client, "SKIP", format!("no app at {app}"), hold, &cell);
        return Ok(());
    }
    let Some(udid) = sim_udid(&sim) else {
        g.record(platform, client, "SKIP", format!("no simulator matching '{sim}'"), hold, &cell);
        return Ok(());
    };
    g.log(&format!("== {platform} / {client}  sim={sim} udid={udid} hold={hold}s =="));
    boot(&udid);
    // Install first: `defaults write` through simctl needs the app container.
    if let Err(e) = install_ios(&udid, Path::new(&app)) {
        g.record(platform, client, "FAIL", format!("simctl install failed: {e}"), hold, &cell);
        return Ok(());
    }
    if let Err(e) = clients::set_ios(client, &udid, &bundle) {
        g.record(platform, client, "FAIL", format!("prefs set failed: {e}"), hold, &cell);
        return Ok(());
    }
    let terminate = || {
        let _ = try_output(cmd("xcrun").args(["simctl", "terminate", &udid, &bundle]));
    };
    terminate();
    let console = cell.join("console.log");
    let log = sim_log(&udid, &console);

    let settle: u64 = env_or("WAWONA_MATRIX_LAUNCH_SETTLE_SEC", "5").parse().unwrap_or(5);
    let pid = if env_flag("WAWONA_MATRIX_USE_AGENT_DEVICE") {
        if !agent_device_start(platform, &sim, &bundle, &cell) {
            stop(log);
            terminate();
            g.record(
                platform,
                client,
                "FAIL",
                "agent-device Start not pressed (see the cell's snapshot)".into(),
                hold,
                &cell,
            );
            return Ok(());
        }
        apple_pid(&udid, &bundle)
    } else {
        // WWNSceneDelegate reads WAWONA_AUTO_CLIENT and starts the client itself.
        let out = try_output(
            cmd("xcrun").args(["simctl", "launch", &udid, &bundle]).env("SIMCTL_CHILD_WAWONA_AUTO_CLIENT", client),
        )
        .unwrap_or_default();
        let _ = write(cell.join("launch.log"), &out);
        sleep_ms(settle * 1000);
        out.trim().rsplit(": ").next().and_then(|p| p.parse().ok()).or_else(|| apple_pid(&udid, &bundle)).or_else(
            || {
                sleep_ms(2000);
                apple_pid(&udid, &bundle)
            },
        )
    };
    let Some(mut pid) = pid else {
        stop(log);
        terminate();
        g.record(platform, client, "FAIL", "app pid not found after launch".into(), hold, &cell);
        return Ok(());
    };
    let _ = write(cell.join("pid.txt"), pid.to_string());

    let mut alive = true;
    for _ in 0..hold.div_ceil(2) {
        if !crate::util::alive(pid) {
            match apple_pid(&udid, &bundle) {
                Some(p) => pid = p,
                None => {
                    alive = false;
                    break;
                }
            }
        }
        sleep_ms(2000);
    }
    let _ = try_output(cmd("xcrun").args(["simctl", "io", &udid, "screenshot"]).arg(cell.join("running.png")));
    sleep_ms(1000);
    stop(log);
    let (status, reason) = if let Some(p) = scan_fail(&console) {
        ("FAIL", format!("console matched fail pattern: {p}"))
    } else if !alive || apple_pid(&udid, &bundle).is_none() {
        ("FAIL", format!("process died during {hold}s hold"))
    } else {
        ("PASS", format!("alive {hold}s after Start; no fail markers"))
    };
    g.record(platform, client, status, reason, hold, &cell);
    terminate();
    Ok(())
}

fn android_cell(g: &mut Gate, client: &str) -> Result<()> {
    let cell = g.out.join("android").join(client);
    std::fs::create_dir_all(&cell)?;
    let hold = hold_for(client);
    if let Some(skip) = clients::skip_reason("android", client) {
        g.record("android", client, "SKIP", skip, hold, &cell);
        return Ok(());
    }
    let Some(adb) = Adb::find() else {
        g.record("android", client, "SKIP", "no adb device".into(), hold, &cell);
        return Ok(());
    };
    g.log(&format!("== android / {client}  serial={} hold={hold}s ==", adb.serial));
    let apk = app_for("android");
    if !apk.is_empty() && Path::new(&apk).is_file() && adb.install(&apk).is_err() {
        g.record("android", client, "FAIL", "adb install failed".into(), hold, &cell);
        return Ok(());
    }
    if let Err(e) = clients::set_android(client, &adb) {
        g.record("android", client, "FAIL", format!("prefs set failed: {e}"), hold, &cell);
        return Ok(());
    }
    let _ = try_output(adb.command().args(["logcat", "-c"]));
    let force_stop = || adb.quiet(&format!("am force-stop {ANDROID_ID}"));
    force_stop();
    let blockers = || adb.quiet("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS");
    let machines = || {
        adb.has_id("wwn.machines.root")
            || ["Machine Configuration", "Default Machine", "All Machines", "Disconnected"]
                .iter()
                .any(|t| adb.has_text(t))
    };
    let activity = env_or("WAWONA_ANDROID_ACTIVITY", &format!("{ANDROID_ID}.MainActivity"));
    let started = try_output(adb.command().args(["shell", &format!("am start -W -n {ANDROID_ID}/{activity}")]))
        .unwrap_or_default();
    let _ = write(cell.join("am-start.txt"), started);
    sleep_ms(4000);
    blockers();
    if !machines() {
        let _ = adb.uia_tap_id("wwn.welcome.continue") || adb.uia_tap_text("Continue");
        adb.tap_ref(540, 1390);
        adb.tap(540, 1390);
        sleep_ms(2000);
        blockers();
    }
    sleep_ms(2000);
    blockers();
    let home = wait_for(30, 1000, || machines() || !adb.welcome_continue_visible());
    if home
        && (["Cancel", "Wawona Settings", "Add Machine Profile"].iter().any(|t| adb.has_text(t))
            || adb.has_id("wwn.settings.root")
            || adb.has_id("wwn.machines.editor"))
    {
        adb.uia_tap_text("Cancel");
        let _ = adb.uia_tap_id("wwn.settings.done") || adb.uia_tap_text("Done");
        adb.key(4);
        sleep_ms(1000);
    }
    blockers();
    let pressed = home
        && (adb.uia_tap_id("wwn.machines.start")
            || adb.uia_tap_text("Start")
            || adb.tap_ref(227, 1039)
            || adb.tap(227, 1032));
    if !pressed {
        let _ = adb.screencap(&cell.join("start-fail.png"));
        if let Some(x) = adb.uia() {
            let _ = write(cell.join("start-fail-ui.xml"), x);
        }
        force_stop();
        g.record("android", client, "FAIL", "Start control not pressed (see start-fail-ui.xml)".into(), hold, &cell);
        return Ok(());
    }
    sleep_ms(6000);
    blockers();
    let logcat = |name: &str| {
        let text = try_output(adb.command().args(["logcat", "-d"])).unwrap_or_default();
        let _ = write(cell.join(name), text);
    };
    logcat("logcat-pre.txt");
    for _ in 0..hold.div_ceil(2) {
        if adb.shell(&format!("pidof {ANDROID_ID}")).is_none_or(|p| p.trim().is_empty()) {
            logcat("logcat.txt");
            force_stop();
            g.record("android", client, "FAIL", "process died during hold".into(), hold, &cell);
            return Ok(());
        }
        sleep_ms(2000);
    }
    logcat("logcat.txt");
    let _ = adb.screencap(&cell.join("running.png"));
    let (status, reason) = match scan_fail(&cell.join("logcat.txt")) {
        Some(p) => ("FAIL", format!("logcat matched: {p}")),
        None => ("PASS", format!("alive {hold}s after Start; no fail markers")),
    };
    let _ = adb.uia_tap_id("wwn.machines.stop") || adb.uia_tap_text("Stop");
    force_stop();
    g.record("android", client, status, reason, hold, &cell);
    Ok(())
}

fn macos_cell(g: &mut Gate, client: &str) -> Result<()> {
    let cell = g.out.join("macos").join(client);
    std::fs::create_dir_all(&cell)?;
    let hold = hold_for(client);
    if let Some(skip) = clients::skip_reason("macos", client) {
        g.record("macos", client, "SKIP", skip, hold, &cell);
        return Ok(());
    }
    let mut app = PathBuf::from(app_for("macos"));
    if !app.is_dir() {
        app = crate::product::target("macos").map(|t| t.app(false, true)).unwrap_or_default();
    }
    if !app.is_dir() {
        g.record("macos", client, "SKIP", "no Wawona.app (set WAWONA_MACOS_APP)".into(), hold, &cell);
        return Ok(());
    }
    if let Some(other) = try_output(cmd("pgrep").args(["-x", "Wawona"])) {
        bail!("another Wawona is running (pid {}); quit it before the macOS matrix", other.trim());
    }
    g.log(&format!("== macos / {client}  app={} hold={hold}s ==", app.display()));
    let key = clients::prefs_key(client)?;
    let id = format!("e2e-{client}-default");
    let profile = json!([{
        "id": id, "name": "Default Machine", "type": "native",
        "sshHost": "", "sshUser": "", "sshPort": 22, "sshPassword": "",
        "remoteCommand": "", "launchers": [], "favorite": false,
        "runtimeOverrides": {"bundledAppID": client},
        "settingsOverrides": {"NativeClientId": client, key: true},
        "nativeLauncher": client,
    }]);
    for (k, ty, v) in [
        ("wawona.machineProfiles.v1", "-string", profile.to_string()),
        ("wawona.activeMachineId.v1", "-string", id.clone()),
        (key, "-bool", "YES".into()),
        ("hasSeenWelcome", "-bool", "YES".into()),
    ] {
        run(cmd("defaults").args(["write", IOS_ID, k, ty, &v]))?;
    }
    // An unpacked CI artifact keeps quarantine and loses +x (LaunchServices 111,
    // "Permission denied"); the signature stays valid, so exec it directly.
    let _ = try_output(cmd("xattr").arg("-cr").arg(&app));
    for dir in ["Contents/MacOS", "Contents/Resources/bin"] {
        let _ = try_output(cmd("chmod").args(["-R", "u+x"]).arg(app.join(dir)));
    }
    let app_log = cell.join("app.log");
    let f = std::fs::File::create(&app_log)?;
    let mut child = cmd(app.join("Contents/MacOS/Wawona"))
        .env("WAWONA_AUTO_CLIENT", client)
        .stdin(Stdio::null())
        .stdout(f.try_clone()?)
        .stderr(f)
        .spawn()?;
    let _ = write(cell.join("pid.txt"), child.id().to_string());
    let mut died = false;
    for _ in 0..hold.div_ceil(2) {
        if child.try_wait()?.is_some() {
            died = true;
            break;
        }
        sleep_ms(2000);
    }
    // NSTask clients log "<id> terminated (status N ...)"; in-process iland clients "<id> exit rc=N".
    let death = regex::Regex::new(&format!(
        r"{} (terminated \(status [1-9]| exit rc=[1-9]|exit code: [1-9])",
        regex::escape(client)
    ))?;
    let text = std::fs::read_to_string(&app_log).unwrap_or_default();
    let (status, reason) = if died {
        ("FAIL", "host process died during hold (crash?)".to_string())
    } else if let Some(p) = scan_fail(&app_log) {
        ("FAIL", format!("app.log matched fail pattern: {p}"))
    } else if let Some(line) = text.lines().rfind(|l| death.is_match(l)) {
        ("FAIL", format!("client did not stay up: {line}"))
    } else {
        ("PASS", format!("alive {hold}s after WAWONA_AUTO_CLIENT start; no fail markers"))
    };
    let _ = child.kill();
    let _ = child.wait();
    g.record("macos", client, status, reason, hold, &cell);
    Ok(())
}

fn summary(g: &Gate) -> Result<String> {
    let count = |s: &str| g.rows.iter().filter(|r| r.status == s).count();
    let cells = |s: &str| {
        g.rows.iter().filter(|r| r.status == s).map(|r| format!("{}/{}", r.platform, r.client)).collect::<Vec<_>>()
    };
    let mut md = format!(
        "# Watch: bundled clients summary\n\n- PASS: {}\n- FAIL: {}\n- SKIP: {}\n\n",
        count("PASS"),
        count("FAIL"),
        count("SKIP")
    );
    let fails = cells("FAIL");
    if fails.is_empty() {
        md += "MATRIX_FAIL platforms/clients: (none)\n\n";
    } else {
        md += "## FAIL cells\n\n| Platform | Client | Reason |\n|----------|--------|--------|\n";
        for r in g.rows.iter().filter(|r| r.status == "FAIL") {
            md += &format!("| {} | {} | {} |\n", r.platform, r.client, r.reason);
        }
        md += &format!("\nMATRIX_FAIL platforms/clients: {}\n\n", fails.join(", "));
    }
    md += "## All results\n\n| Platform | Client | Status | Reason |\n|----------|--------|--------|--------|\n";
    let mut tsv = String::from("platform\tclient\tstatus\treason\thold_sec\tartifact_dir\n");
    for r in &g.rows {
        md += &format!("| {} | {} | {} | {} |\n", r.platform, r.client, r.status, r.reason);
        tsv += &format!("{}\t{}\t{}\t{}\t{}\t{}\n", r.platform, r.client, r.status, r.reason, r.hold, r.dir.display());
    }
    let rows: Vec<_> = g
        .rows
        .iter()
        .map(|r| json!({"platform": r.platform, "client": r.client, "status": r.status, "reason": r.reason, "hold_sec": r.hold, "artifact_dir": r.dir}))
        .collect();
    let payload = json!({
        "counts": {"PASS": count("PASS"), "FAIL": count("FAIL"), "SKIP": count("SKIP")},
        "fail": fails, "pass": cells("PASS"), "skip": cells("SKIP"), "rows": rows,
    });
    write(g.out.join("SUMMARY.md"), &md)?;
    write(g.out.join("results.tsv"), tsv)?;
    write(g.out.join("summary.json"), serde_json::to_string_pretty(&payload)? + "\n")?;
    Ok(md)
}

/// Exit 1 on any FAIL; 2 with WAWONA_MATRIX_STRICT=1 and no PASS.
pub fn main(platforms: Vec<String>) -> Result<()> {
    let stamp = output(cmd("date").args(["-u", "+%Y%m%dT%H%M%SZ"]))?.trim().to_string();
    let out = std::env::var("WAWONA_MATRIX_OUT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| root().join(".agent-device/test-artifacts/bundled-clients-matrix").join(&stamp));
    std::fs::create_dir_all(&out)?;
    let mut g = Gate { out, rows: Vec::new() };
    let platforms: Vec<String> =
        if platforms.is_empty() { PLATFORMS.iter().map(|s| s.to_string()).collect() } else { platforms };
    let list: Vec<String> = match std::env::var("WAWONA_MATRIX_CLIENTS") {
        Ok(csv) if !csv.is_empty() => csv.split(',').map(str::to_string).collect(),
        _ => clients::KEEP.iter().map(|s| s.to_string()).collect(),
    };
    g.log(&format!("Watch: bundled clients gate. {stamp}"));
    g.log(&format!("Output: {}", g.out.display()));
    g.log(&format!("Platforms: {}", platforms.join(" ")));
    g.log(&format!("Clients: {}", list.join(",")));
    for p in &platforms {
        g.log(&format!("======== PLATFORM {p} ({} clients) ========", list.len()));
        if env_flag("WAWONA_MATRIX_USE_AGENT_DEVICE") && matches!(p.as_str(), "ios" | "ipados" | "visionos") {
            let plat = if p == "ipados" { "ios" } else { p };
            let ad = Ad::new(&["--platform", plat, "--device", &sim_for(p)]);
            if prepare_runner(&ad).is_err() {
                g.log("WARN: prepare ios-runner failed (continuing; per-cell open retries)");
            }
        }
        for c in &list {
            match p.as_str() {
                "ios" | "ipados" | "visionos" | "tvos" | "watchos" => apple_cell(&mut g, p, c)?,
                "android" => android_cell(&mut g, c)?,
                "macos" => macos_cell(&mut g, c)?,
                other => bail!("unknown platform {other} (one of {})", PLATFORMS.join(", ")),
            }
        }
    }
    let md = summary(&g)?;
    g.log(&md);
    let n = |s: &str| g.rows.iter().filter(|r| r.status == s).count();
    g.log(&format!("MATRIX_PASS count={}", n("PASS")));
    g.log(&format!("MATRIX_SKIP count={}", n("SKIP")));
    if n("FAIL") > 0 {
        let cells: Vec<String> =
            g.rows.iter().filter(|r| r.status == "FAIL").map(|r| format!("{}/{}", r.platform, r.client)).collect();
        g.log(&format!("MATRIX_FAIL count={} cells={}", n("FAIL"), cells.join(",")));
        std::process::exit(1);
    }
    if env_flag("WAWONA_MATRIX_STRICT") && n("PASS") == 0 {
        g.log("MATRIX_FAIL: STRICT=1 and zero PASS cells");
        std::process::exit(2);
    }
    g.log("MATRIX_OK");
    Ok(())
}
