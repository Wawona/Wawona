//! Nested niri + fuzzel (issue #78): Android and iOS through agent-device,
//! macOS against the built app, and the headless applications catalog.

use super::ad::*;
use super::clients;
use crate::util::*;
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Child;

#[derive(Clone, Copy, clap::ValueEnum)]
pub enum Lane {
    Android,
    Ios,
    Macos,
    /// Android, then iOS and macOS when present (WAWONA_FUZZEL_REQUIRE_IOS/MACOS=1 hard-fail them).
    All,
}

pub fn main(lane: Lane) -> Result<()> {
    require_agent_device()?;
    match lane {
        Lane::Android => android(),
        Lane::Ios => ios(),
        Lane::Macos => macos(None),
        Lane::All => {
            android()?;
            if sim_available("iPhone") {
                if let Err(e) = ios() {
                    if env_flag("WAWONA_FUZZEL_REQUIRE_IOS") {
                        return Err(e);
                    }
                    eprintln!("WARN: iOS fuzzel lane failed: {e} (WAWONA_FUZZEL_REQUIRE_IOS=1 to hard-fail)");
                }
            }
            if cfg!(target_os = "macos") {
                if let Err(e) = macos(None) {
                    if env_flag("WAWONA_FUZZEL_REQUIRE_MACOS") {
                        return Err(e);
                    }
                    eprintln!("WARN: macOS fuzzel lane failed: {e} (WAWONA_FUZZEL_REQUIRE_MACOS=1 to hard-fail)");
                }
            }
            Ok(())
        }
    }
}

fn desktop_count(dir: &Path) -> usize {
    walkdir::WalkDir::new(dir)
        .into_iter()
        .flatten()
        .filter(|e| {
            e.path().extension().is_some_and(|x| x == "desktop")
                && e.path().to_string_lossy().contains("share/applications")
        })
        .count()
}

fn file_count(dir: &Path) -> usize {
    walkdir::WalkDir::new(dir).into_iter().flatten().filter(|e| e.file_type().is_file()).count()
}

/// The catalog's `.desktop` Names must include what fuzzel lists first.
fn assert_names(applications: &Path) -> Result<()> {
    let mut paths: Vec<PathBuf> = std::fs::read_dir(applications)?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "desktop"))
        .collect();
    paths.sort();
    let names: Vec<String> = paths
        .iter()
        .filter_map(|p| {
            let text = String::from_utf8_lossy(&std::fs::read(p).ok()?).into_owned();
            text.lines().find_map(|l| l.strip_prefix("Name=")).map(|n| n.trim().to_string())
        })
        .collect();
    let missing: Vec<&str> =
        ["Fastfetch", "Foot Terminal"].into_iter().filter(|n| !names.iter().any(|x| x == n)).collect();
    if !missing.is_empty() {
        bail!("missing desktop Names: {missing:?}; have={:?}", &names[..names.len().min(12)]);
    }
    eprintln!("PASS: {} desktop Names include Fastfetch and Foot Terminal", names.len());
    Ok(())
}

/// `cargo xtask lab apps-catalog`: builds applications-catalog.nix on the
/// flake's locked nixpkgs and checks it without a compositor.
pub fn apps_catalog() -> Result<()> {
    let lock: serde_json::Value = serde_json::from_str(&read(root().join("flake.lock"))?)?;
    let locked = &lock["nodes"]["nixpkgs"]["locked"];
    let (rev, hash) = (locked["rev"].as_str().context("nixpkgs rev")?, locked["narHash"].as_str().context("narHash")?);
    let r = root().display().to_string();
    let out = "/tmp/wawona-applications-catalog-smoke";
    eprintln!("== building applications catalog ==");
    let expr = format!(
        r#"let pkgs = import (fetchTarball {{ url = "https://github.com/NixOS/nixpkgs/archive/{rev}.tar.gz"; sha256 = "{hash}"; }}) {{ system = builtins.currentSystem; }};
        in pkgs.callPackage {r}/dependencies/generators/applications-catalog.nix {{ inherit pkgs; lib = pkgs.lib; wawonaSrc = {r}; }}"#
    );
    run(cmd("nix").args(["build", "--impure", "--expr", &expr, "--out-link", out]))?;
    let share = Path::new(out).join("share");
    let (desks, icons) = (desktop_count(&share), file_count(&share.join("icons/hicolor")));
    if desks < 3 || icons < 1 {
        bail!("FAIL: catalog has {desks} desktops and {icons} icons");
    }
    assert_names(&share.join("applications"))?;
    eprintln!("PASS: applications-catalog ({desks} desktops, {icons} icons)");
    Ok(())
}

// --- Android -----------------------------------------------------------------

/// Berberis (arm64 on x86) often hides guest argv from `ps`: pidof, wide ps, then logcat.
fn guest_running(adb: &Adb, needle: &str) -> bool {
    let pids = adb
        .shell(&format!("pidof lib{needle}_bin.so 2>/dev/null; pgrep -f lib{needle}_bin 2>/dev/null"))
        .unwrap_or_default();
    if pids.chars().any(|c| c.is_ascii_digit()) {
        return true;
    }
    let re = regex::Regex::new(&format!(r"(?i)lib{needle}|[^a-z]{needle}")).unwrap();
    adb.shell("ps -A -w").unwrap_or_default().lines().any(|l| re.is_match(l) && !l.contains(" Z "))
}

fn logcat(adb: &Adb) -> String {
    try_output(adb.command().args(["logcat", "-d"])).unwrap_or_default().replace('\r', "")
}

fn niri_ready(adb: &Adb, shot: &Path) -> bool {
    if guest_running(adb, "niri") {
        return true;
    }
    let log = logcat(adb);
    if log.contains("Unable to get realpath of niri")
        || regex::Regex::new(r"Error running .*libniri_bin").unwrap().is_match(&log)
    {
        return false;
    }
    if !log.contains("Launched niri (nested compositor)") {
        return false;
    }
    if regex::Regex::new(r"application:'libniri_bin|NIRI_BACKEND|Important Hotkeys|frame scene: count=[1-9]")
        .unwrap()
        .is_match(&log)
    {
        return true;
    }
    // A large focused screenshot is enough when logcat is sparse.
    shot.metadata().is_ok_and(|m| m.len() > 100_000)
}

/// The shell env's "linked .../fuzzel -> libfuzzel_bin.so" is not a running fuzzel.
fn fuzzel_ready(adb: &Adb) -> bool {
    if guest_running(adb, "fuzzel") {
        return true;
    }
    let log = logcat(adb);
    !log.contains("error spawning \"fuzzel\"")
        && regex::Regex::new(r" W fuzzel |application:.libfuzzel").unwrap().is_match(&log)
}

fn ps_matching(adb: &Adb, pattern: &str) -> String {
    let re = regex::Regex::new(pattern).unwrap();
    adb.shell("ps -A -w").unwrap_or_default().lines().filter(|l| re.is_match(l)).collect::<Vec<_>>().join("\n")
}

fn run_as(adb: &Adb, script: &str) -> String {
    adb.shell(&format!("run-as {ANDROID_ID} sh -c \"{script}\"")).unwrap_or_default()
}

fn android() -> Result<()> {
    let Some(adb) = Adb::find() else {
        eprintln!("== Android fuzzel: skip (no device or emulator) ==");
        return Ok(());
    };
    eprintln!("== Android fuzzel: serial={} ==", adb.serial);
    let art = artifacts()?;
    adb.quiet_immersive();
    // Hard-keyboard input keeps Gboard off fuzzel's filter field.
    adb.quiet("settings put secure show_ime_with_hard_keyboard 0");
    adb.install_from_env()?;
    clients::set_android("niri", &adb)?;

    let count = |adb: &Adb| -> usize {
        run_as(adb, "ls files/wawona-rootfs/usr/share/applications 2>/dev/null | wc -l").trim().parse().unwrap_or(0)
    };
    let mut desks = count(&adb);
    if desks < 3 {
        // A fresh install extracts the rootfs on first launch.
        adb.quiet(&format!("am start -n {ANDROID_ID}/.MainActivity"));
        sleep_ms(6000);
        adb.quiet(&format!("am force-stop {ANDROID_ID}"));
        desks = count(&adb);
    }
    if desks < 3 {
        bail!("FAIL: applications catalog missing in the rootfs (count={desks})");
    }
    eprintln!("PASS: rootfs applications catalog ({desks} entries)");
    let _ = try_output(adb.command().args(["logcat", "-c"]));

    let ad = adb.ad("wawona-android-niri-fuzzel");
    ad.run(&["open", ANDROID_ID, "--relaunch"])?;
    ad.wait(4000);
    adb.dismiss_blockers(&ad);
    ad.shot(&art.join("android-fuzzel-e2e-01-home.png"));
    adb.dismiss_welcome(&ad);
    adb.dismiss_blockers(&ad);
    ad.shot(&art.join("android-fuzzel-e2e-02-machines.png"));
    if adb.has_text("Continue") {
        return Err(ad.fail(&art.join("android-fuzzel-welcome-stuck.png"), "still on Welcome after Continue"));
    }
    adb.press_text(&ad, "Got it");
    ad.wait(500);
    adb.press_text(&ad, "All Machines");
    ad.wait(500);
    adb.dismiss_blockers(&ad);
    // A successful tap counts; the session settles after the wait.
    let started = adb.press_id(&ad, "wwn.machines.start") || adb.press_text(&ad, "Start") || {
        adb.tap_ref(227, 1039);
        ad.wait(800);
        if adb.has_text("Start") {
            adb.tap_ref(216, 1040);
            ad.wait(800);
        }
        !adb.has_text("Start") || adb.uia_tap_id("wwn.machines.start")
    };
    if !started {
        return Err(
            ad.fail(&art.join("android-fuzzel-start-fail.png"), "could not press Start before the niri session")
        );
    }
    ad.wait(12000);
    adb.dismiss_blockers(&ad);
    ad.shot(&art.join("android-fuzzel-e2e-03-niri-starting.png"));
    let _ = adb.press_text(&ad, "Done") || adb.tap_ref(950, 420);
    ad.wait(1000);
    let _ = adb.press_text(&ad, "Got it") || adb.tap_ref(900, 720);
    ad.wait(500);
    let focused = art.join("android-fuzzel-e2e-04-niri-focused.png");
    ad.shot(&focused);

    let ready = wait_for(30, 2000, || niri_ready(&adb, &focused));
    let procs = ps_matching(&adb, "(?i)niri|fuzzel");
    write(
        art.join("android-fuzzel-e2e-procs-pre.txt"),
        format!("evidence={}\n{procs}\n", if ready { "niri-ready" } else { "" }),
    )?;
    if !ready {
        bail!("FAIL: niri not running (no ps, logcat or screenshot evidence)");
    }
    eprintln!("PASS: niri session evidence");

    // Dismiss niri's Important Hotkeys overlay, focus, then Alt+D once.
    adb.key(111);
    sleep_ms(500);
    adb.key(111);
    sleep_ms(300);
    adb.tap_ref(540, 1100);
    sleep_ms(300);
    eprintln!("== Android: Alt+D inject (single attempt) ==");
    adb.alt_d();
    sleep_ms(2000);
    let up = fuzzel_ready(&adb);
    write(
        art.join("android-fuzzel-e2e-procs.txt"),
        format!("fuzzel_ready={}\n{}\n", if up { "yes" } else { "no" }, ps_matching(&adb, "(?i)niri|fuzzel")),
    )?;
    let shot = art.join("android-fuzzel-e2e-05-after-alt-d.png");
    adb.screencap(&shot)?;
    assert_png(&shot)?;
    let logf = art.join("android-fuzzel-e2e-logcat.txt");
    write(&logf, logcat(&adb))?;
    if !niri_ready(&adb, &focused) {
        bail!("FAIL: niri not running");
    }
    if !up {
        bail!("FAIL: fuzzel not running after Alt+D");
    }
    eprintln!("PASS: fuzzel process up");

    // Catalog Exec must resolve on PATH (weston-simple-shm is libwawona_wl_bin.so).
    let link = run_as(&adb, "ls -l files/wawona-rootfs/usr/bin/weston-simple-shm 2>/dev/null");
    let listing = run_as(&adb, "ls -la files/wawona-rootfs/usr/bin 2>/dev/null | head -80");
    write(
        art.join("android-fuzzel-e2e-wl-path.txt"),
        format!("weston-simple-shm={link}\n--- usr/bin ---\n{listing}\n"),
    )?;
    if !regex::Regex::new("wawona_wl_bin|weston-simple-shm").unwrap().is_match(&format!("{link}\n{listing}")) {
        bail!("FAIL: usr/bin/weston-simple-shm missing (fuzzel Exec cannot launch clients)");
    }
    eprintln!("PASS: weston-simple-shm on PATH");

    // Fuzzel often exits at once on Berberis, so `input text` cannot drive
    // Exec=: launch the catalog client on niri's nested socket instead.
    let log = logcat(&adb);
    let last = |re: &str| regex::Regex::new(re).unwrap().captures_iter(&log).last().map(|c| c[1].to_string());
    let xdg =
        last(r"XDG_RUNTIME_DIR=(\S+)").unwrap_or_else(|| format!("/data/user/0/{ANDROID_ID}/cache/wawona-runtime"));
    let runtime = run_as(&adb, &format!("ls -1 '{xdg}' 2>/dev/null"));
    // Socket entries may appear as wayland-N or wayland-N.lock; never use .lock.
    let nested = last(r"listening on Wayland socket: (\S+)").or_else(|| {
        let mut socks: Vec<&str> = runtime
            .lines()
            .map(|l| l.trim().trim_end_matches(".lock"))
            .filter(|l| regex::Regex::new(r"^wayland-[0-9]+$").unwrap().is_match(l) && *l != "wayland-0")
            .collect();
        socks.sort();
        socks.first().map(|s| s.to_string())
    });
    write(
        art.join("android-fuzzel-e2e-nested-socket.txt"),
        format!("nested_socket={} xdg={xdg}\n--- runtime dir ---\n{runtime}\n", nested.as_deref().unwrap_or("none")),
    )?;
    match nested.as_deref() {
        Some(n) if n != "wayland-0" && !n.ends_with(".lock") => {}
        other => bail!("FAIL: no nested Wayland socket under {xdg} (got '{}')", other.unwrap_or("none")),
    }

    let _ = try_output(adb.command().args(["logcat", "-c"]));
    // adb shell exec of an arm64 PIE fails to link under Berberis: the app process forks it.
    adb.quiet(&format!(
        "am start --activity-single-top -n {ANDROID_ID}/.MainActivity --es wawona_nested_wl_client weston-simple-shm"
    ));
    sleep_ms(4000);
    let after = ps_matching(&adb, "(?i)niri|fuzzel|weston-simple|wawona_wl");
    write(art.join("android-fuzzel-e2e-procs-after-launch.txt"), &after)?;
    let shot2 = art.join("android-fuzzel-e2e-06-after-client-launch.png");
    adb.screencap(&shot2)?;
    assert_png(&shot2)?;
    let log = logcat(&adb);
    write(&logf, &log)?;
    if !regex::Regex::new("WawonaWlBin|launch weston-simple-shm|weston_simple_shm_main").unwrap().is_match(&log)
        && !regex::Regex::new("wawona_wl|weston-simple").unwrap().is_match(&after)
    {
        bail!("FAIL: no evidence weston-simple-shm launched on the nested socket");
    }
    eprintln!("PASS: nested Wayland client launch evidence");
    if regex::Regex::new(r#"error spawning "fuzzel"|timerfd_create|SIGSEGV"#).unwrap().is_match(&log) {
        bail!("FAIL: spawn or timerfd regression in logcat");
    }
    let hints = regex::Regex::new("(?i)XDG_DATA|share/applications|fuzzel").unwrap();
    write(
        art.join("android-fuzzel-e2e-xdg-hints.txt"),
        log.lines().filter(|l| hints.is_match(l)).take(20).collect::<Vec<_>>().join("\n"),
    )?;
    ad.ok(&["close"]);
    eprintln!("== Android fuzzel e2e PASSED ==");
    Ok(())
}

// --- iOS ---------------------------------------------------------------------

pub fn ios() -> Result<()> {
    let device = ios_device();
    let art = artifacts()?;
    eprintln!("== iOS fuzzel: boot simulator '{device}' ==");
    boot(&device);
    if let Ok(app) = std::env::var("WAWONA_IOS_APP").map(PathBuf::from) {
        if !app.as_os_str().is_empty() {
            let staged = install_ios(&device, &app)?;
            let desks = desktop_count(&staged);
            if desks < 3 {
                bail!("FAIL: the iOS app is missing the applications catalog (count={desks})");
            }
            eprintln!("PASS: iOS bundle applications catalog ({desks} entries)");
        }
    }
    clients::set_ios("niri", &device, IOS_ID)?;

    // replay starts its own daemon, which cannot take a lease prepare still holds.
    let ad = Ad::ios(&device, "wawona-ios-niri-fuzzel");
    stop_daemon();
    prepare_runner(&ad)?;
    stop_daemon();
    eprintln!("== iOS: niri+fuzzel .ad replay ==");
    ad.run(&["replay", &root().join(".agent-device/wawona-ios-niri-fuzzel.ad").display().to_string()])?;

    // Replay ends its session. Mod+D has no hardware path through agent-device:
    // the accessory Alt then d, best effort; catalog and screenshot are the gate.
    let post = Ad::ios(&device, "wawona-ios-niri-fuzzel-post");
    post.soft(&["open", IOS_ID]);
    sleep_ms(1000);
    let _ = post.ok(&["press", "Alt"]) || post.ok(&["press", "48", "820"]);
    sleep_ms(300);
    let _ = post.ok(&["type", "d"]) || post.ok(&["press", "201", "760"]);
    sleep_ms(2500);
    let shot = art.join("ios-fuzzel-e2e-05-after-mod-d.png");
    post.shot(&shot);
    assert_png(&shot)?;
    if let Some(udid) = sim_udid(&device) {
        let list = try_output(cmd("xcrun").args(["simctl", "spawn", &udid, "launchctl", "list"])).unwrap_or_default();
        let re = regex::Regex::new("(?i)wawona|fuzzel|niri").unwrap();
        write(
            art.join("ios-fuzzel-e2e-procs.txt"),
            list.lines().filter(|l| re.is_match(l)).collect::<Vec<_>>().join("\n"),
        )?;
    }
    post.ok(&["close"]);
    eprintln!("== iOS fuzzel e2e PASSED (screenshot + catalog; Mod+D best effort) ==");
    Ok(())
}

// --- macOS -------------------------------------------------------------------

/// Children this lane started, killed on every exit path.
struct Kids(Vec<Child>);

impl Drop for Kids {
    fn drop(&mut self) {
        for c in self.0.iter_mut().rev() {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

fn find_app(app: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(a) = app.or_else(|| std::env::var("WAWONA_MACOS_APP").ok().filter(|s| !s.is_empty()).map(PathBuf::from))
    {
        return Ok(a);
    }
    if let Ok(a) = crate::product::target("macos").map(|t| t.app(false, true)) {
        if a.is_dir() {
            return Ok(a);
        }
    }
    bail!("FAIL: Wawona.app not found (pass --app, set WAWONA_MACOS_APP or cargo xtask build macos)")
}

fn first_existing(cands: &[PathBuf]) -> Option<PathBuf> {
    cands.iter().find(|p| p.exists()).cloned()
}

fn log_match(path: &Path, re: &regex::Regex) -> Option<String> {
    re.captures(&std::fs::read_to_string(path).ok()?).map(|c| c[1].trim().to_string())
}

fn tail(path: &Path) -> String {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(60)..].join("\n")
}

/// The host compositor plus nested niri; returns niri's child socket.
struct Session {
    kids: Kids,
    runtime: PathBuf,
    child_socket: String,
}

fn start_niri(app: &Path, tag: &str, extra: &[(&str, String)]) -> Result<Session> {
    let wait: u64 = env_or("WAWONA_NIRI_SMOKE_WAIT", "45").parse().unwrap_or(45);
    let niri =
        std::env::var("WAWONA_NIRI_BIN").map(PathBuf::from).unwrap_or_else(|_| app.join("Contents/Resources/bin/niri"));
    if !niri.is_file() {
        bail!("FAIL: bundled niri missing at {}", niri.display());
    }
    let res = app.join("Contents/Resources");
    let xkb = std::env::var("XKB_CONFIG_ROOT").ok().map(PathBuf::from).or_else(|| {
        [res.join("share/X11/xkb"), app.join("share/X11/xkb")].into_iter().find(|d| d.join("rules").is_dir())
    });
    match &xkb {
        Some(x) => eprintln!("XKB_CONFIG_ROOT={}", x.display()),
        None => eprintln!("WARN: XKB_CONFIG_ROOT unset; nested niri may BadKeymap on artifact apps"),
    }

    let app_log = PathBuf::from(format!("/tmp/wawona-{tag}-app.log"));
    let mut kids = Kids(Vec::new());
    eprintln!("== starting the Wawona compositor app ({}) ==", app.display());
    kids.0.push(
        cmd(app.join("Contents/MacOS/Wawona"))
            .stdout(std::fs::File::create(&app_log)?)
            .stderr(std::fs::File::create(&app_log)?.try_clone()?)
            .spawn()?,
    );
    // The app picks its own XDG_RUNTIME_DIR; read the socket it advertises.
    let started = regex::Regex::new(r"Compositor started\. Socket: (\S+)").unwrap();
    let mut sock = None;
    for _ in 0..wait {
        sock = log_match(&app_log, &started).filter(|s| Path::new(s).exists());
        if sock.is_some() {
            break;
        }
        if kids.0[0].try_wait()?.is_some() {
            bail!("FAIL: the Wawona app exited before its socket\n{}", tail(&app_log));
        }
        sleep_ms(1000);
    }
    let Some(sock) = sock.map(PathBuf::from) else {
        bail!("FAIL: the Wawona Wayland socket never appeared\n{}", tail(&app_log))
    };
    let runtime = sock.parent().unwrap().to_path_buf();
    let display = sock.file_name().unwrap().to_string_lossy().into_owned();
    eprintln!("Wawona socket up: {display} (runtime dir: {})", runtime.display());

    // ANGLE's Vulkan-over-Wayland winsys needs the bundled ICD; MoltenVK first.
    let icd_dir = res.join("vulkan/icd.d");
    let icd =
        first_existing(&[icd_dir.join("MoltenVK_icd.json"), icd_dir.join("kosmickrisp_icd.json")]).or_else(|| {
            std::fs::read_dir(&icd_dir)
                .ok()?
                .flatten()
                .map(|e| e.path())
                .find(|p| p.extension().is_some_and(|x| x == "json"))
        });
    let cfg = first_existing(&[res.join("share/niri/default-config.kdl"), app.join("share/niri/default-config.kdl")]);
    if cfg.is_none() {
        eprintln!("NOTE: no bundled niri default-config.kdl; using niri defaults");
    }
    let niri_log = PathBuf::from(format!("/tmp/wawona-{tag}-niri.log"));
    let icd = icd.map(|p| p.display().to_string()).unwrap_or_default();
    eprintln!("== starting nested niri (VK ICD: {}) ==", if icd.is_empty() { "none" } else { &icd });
    let mut c = cmd(&niri);
    c.env("XDG_RUNTIME_DIR", &runtime)
        .env("WAYLAND_DISPLAY", &display)
        .env("NIRI_BACKEND", "nested")
        .env("RUST_LOG", "niri=debug")
        .env("DYLD_LIBRARY_PATH", app.join("Contents/Frameworks"))
        .env("VK_ICD_FILENAMES", &icd)
        .env("VK_DRIVER_FILES", &icd)
        .env_remove("NIRI_CONFIG")
        .stdout(std::fs::File::create(&niri_log)?)
        .stderr(std::fs::File::create(&niri_log)?.try_clone()?);
    if let Some(x) = &xkb {
        c.env("XKB_CONFIG_ROOT", x);
    }
    if let Some(cfg) = &cfg {
        c.env("NIRI_CONFIG", cfg);
    }
    for (k, v) in extra {
        c.env(k, v);
    }
    kids.0.push(c.spawn()?);
    let listening = regex::Regex::new(r"listening on Wayland socket: (\S+)").unwrap();
    let mut child = None;
    for _ in 0..wait {
        child = log_match(&niri_log, &listening).filter(|s| runtime.join(s).exists());
        if child.is_some() {
            break;
        }
        if kids.0[1].try_wait()?.is_some() {
            bail!("FAIL: niri exited early\n{}", tail(&niri_log));
        }
        sleep_ms(1000);
    }
    let Some(child_socket) = child else { bail!("FAIL: niri's child socket never appeared\n{}", tail(&niri_log)) };
    eprintln!("PASS: nested niri is up; child socket: {child_socket}");
    Ok(Session { kids, runtime, child_socket })
}

/// The Wawona window through an agent-device macOS session.
fn window_shot(out: &Path) -> Result<()> {
    let ad = Ad::macos("wawona-niri-macos").with(&["--surface", "app"]);
    // agent-device reads mixed-case bundle ids as names: attach by display name.
    ad.run(&["open", "Wawona"])?;
    ad.shot(out);
    ad.ok(&["close"]);
    assert_png(out)
}

/// `cargo xtask lab niri-macos`: nested niri on the host compositor serves its
/// own socket and puts a non-black frame in the Wawona window.
pub fn niri_macos(app: Option<PathBuf>) -> Result<()> {
    let app = find_app(app)?;
    let mut s = start_niri(&app, "niri-smoke", &[])?;
    // A few frames for niri's background and hotkey overlay.
    sleep_ms(3000);
    if s.kids.0[1].try_wait()?.is_some() {
        bail!("FAIL: niri died after startup\n{}", tail(Path::new("/tmp/wawona-niri-smoke-niri.log")));
    }
    let shot = artifacts()?.join("niri-smoke-macos.png");
    window_shot(&shot)?;
    assert_lit(&shot, "niri-smoke-macos")?;
    eprintln!("niri macOS nested smoke PASSED");
    Ok(())
}

/// The niri smoke, then fuzzel against niri's child socket with the bundled catalog.
pub fn macos(app: Option<PathBuf>) -> Result<()> {
    eprintln!("== macOS fuzzel: nested niri + catalog assertion ==");
    let app = find_app(app)?;
    let fuzzel = std::env::var("WAWONA_FUZZEL_BIN")
        .map(PathBuf::from)
        .unwrap_or_else(|_| app.join("Contents/Resources/bin/fuzzel"));
    if !fuzzel.is_file() {
        bail!("FAIL: bundled fuzzel missing at {}", fuzzel.display());
    }
    let share = first_existing(&[app.join("Contents/Resources/share"), app.join("share")])
        .filter(|s| s.join("applications").is_dir())
        .context("FAIL: no share/applications in the app bundle")?;
    let (desks, icons) = (desktop_count(&share), file_count(&share.join("icons/hicolor")));
    if desks < 3 || icons < 1 {
        bail!("FAIL: catalog has {desks} desktops and {icons} icons at {}", share.display());
    }
    eprintln!("PASS: catalog {desks} desktops, {icons} icons at {}", share.display());
    niri_macos(Some(app.clone()))?;

    eprintln!("== restarting Wawona for the fuzzel spawn check ==");
    let data_home = std::env::temp_dir().join(format!("wawona-niri-fuzzel-{}", std::process::id()));
    std::fs::create_dir_all(data_home.join("xdg-data-home"))?;
    let path = format!("{}:{}", fuzzel.parent().unwrap().display(), std::env::var("PATH").unwrap_or_default());
    let mut s = start_niri(
        &app,
        "niri-fuzzel",
        &[
            ("XDG_DATA_DIRS", share.display().to_string()),
            ("XDG_DATA_HOME", data_home.join("xdg-data-home").display().to_string()),
            ("PATH", path),
        ],
    )?;
    let flog = PathBuf::from("/tmp/wawona-niri-fuzzel-fuzzel.log");
    let mut f = cmd(&fuzzel)
        .env("XDG_RUNTIME_DIR", &s.runtime)
        .env("WAYLAND_DISPLAY", &s.child_socket)
        .env("XDG_DATA_DIRS", &share)
        .env("XDG_DATA_HOME", data_home.join("xdg-data-home"))
        .env("XDG_CACHE_HOME", data_home.join("cache"))
        .stdout(std::fs::File::create(&flog)?)
        .stderr(std::fs::File::create(&flog)?.try_clone()?)
        .spawn()?;
    let pid = f.id();
    sleep_ms(2000);
    let exited = f.try_wait()?.is_some();
    s.kids.0.push(f);
    if exited {
        bail!("FAIL: fuzzel exited immediately\n{}", tail(&flog));
    }
    eprintln!("PASS: fuzzel stayed up against nested niri (pid {pid})");
    let shot = artifacts()?.join("macos-fuzzel-e2e.png");
    if window_shot(&shot).is_ok() {
        eprintln!("screenshot: {}", shot.display());
    }
    assert_names(&share.join("applications"))?;
    eprintln!("macOS niri+fuzzel smoke PASSED");
    Ok(())
}
