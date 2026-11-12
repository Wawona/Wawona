//! `cargo xtask lab smoke <lane>`: the deterministic GUI smokes, through
//! agent-device on the iOS simulator, an Android emulator, macOS and the
//! vphone research VM.

use super::ad::*;
use super::clients;
use crate::util::*;
use anyhow::{bail, Result};
use std::path::Path;

#[derive(Clone, Copy, clap::ValueEnum)]
pub enum Lane {
    /// Machines, Settings, Add Machine and Start on the simulator.
    Ios,
    /// The iOS lane, then iOS fuzzel on the same runner lease.
    IosCi,
    /// Foot as the Default Machine; asserts a lit session frame.
    IosFoot,
    /// libssh2 CLI in the PTY (wawona-ios-shell-cli.ad).
    IosShellCli,
    /// Darwin CLI replay (wawona-ios-darwin-cli.ad).
    IosDarwinCli,
    /// Start opens Wawona Terminal, iOS then Android.
    Terminal,
    TerminalIos,
    TerminalAndroid,
    /// Machines, Start and the session on an emulator.
    Android,
    /// The APK's bundled OpenSSH (not Dropbear), plus `ssh -V` when the ABI runs.
    AndroidShellSsh,
    /// Host keymap lanes, P0: iOS, watchOS, Android, macOS.
    Xkb,
    XkbIos,
    XkbIpados,
    XkbWatchos,
    XkbTvos,
    XkbVisionos,
    XkbAndroid,
    XkbMacos,
    /// TrollStore Mode B on the vphone lab. Lab evidence only, never a Gate: products proof.
    Vphone,
    /// iOS, Android, then fuzzel.
    All,
}

pub fn main(lane: Lane) -> Result<()> {
    require_agent_device()?;
    let visionos = matches!(lane, Lane::XkbVisionos) || ios_device().to_lowercase().contains("vision");
    if visionos && !env_flag("WAWONA_TARGET_VISIONOS") {
        bail!("refusing a visionOS target; set WAWONA_TARGET_VISIONOS=1 for visionOS work");
    }
    match lane {
        Lane::Ios => ios(false)?,
        Lane::IosCi => {
            ios(true)?;
            if env_flag("WAWONA_SKIP_FUZZEL") {
                eprintln!("== ios-ci: fuzzel skipped (WAWONA_SKIP_FUZZEL=1) ==");
            } else {
                super::fuzzel::ios()?;
            }
            stop_daemon();
        }
        Lane::IosFoot => ios_foot()?,
        Lane::IosShellCli => ios_replay("wawona-ios-shell-cli", false)?,
        Lane::IosDarwinCli => {
            std::fs::create_dir_all(artifacts()?.join("darwin-cli/mode-a"))?;
            ios_replay("wawona-ios-darwin-cli", false)?
        }
        Lane::Terminal => {
            ios_replay("wawona-ios-terminal-start", true)?;
            android_terminal()?
        }
        Lane::TerminalIos => ios_replay("wawona-ios-terminal-start", true)?,
        Lane::TerminalAndroid => android_terminal()?,
        Lane::Android => android()?,
        Lane::AndroidShellSsh => android_shell_ssh()?,
        Lane::Xkb => {
            for p in ["ios", "watchos", "android", "macos"] {
                xkb(p)?;
            }
        }
        Lane::XkbIos => xkb("ios")?,
        Lane::XkbIpados => xkb("ipados")?,
        Lane::XkbWatchos => xkb("watchos")?,
        Lane::XkbTvos => xkb("tvos")?,
        Lane::XkbVisionos => xkb("visionos")?,
        Lane::XkbAndroid => xkb("android")?,
        Lane::XkbMacos => xkb("macos")?,
        Lane::Vphone => vphone()?,
        Lane::All => {
            ios(false)?;
            android()?;
            if env_flag("WAWONA_SKIP_FUZZEL") {
                eprintln!("== fuzzel: skipped (WAWONA_SKIP_FUZZEL=1) ==");
            } else {
                super::fuzzel::main(super::fuzzel::Lane::All)?;
            }
        }
    }
    eprintln!("== done; artifacts in {} ==", artifacts()?.display());
    Ok(())
}

fn install_ios_from_env(device: &str) -> Result<()> {
    match std::env::var("WAWONA_IOS_APP") {
        Ok(app) if !app.is_empty() => install_ios(device, Path::new(&app)).map(|_| ()),
        _ => Ok(()),
    }
}

fn clear(prefix: &str) -> Result<()> {
    for e in std::fs::read_dir(artifacts()?)?.flatten() {
        let n = e.file_name().to_string_lossy().into_owned();
        if n.starts_with(prefix) && n.ends_with(".png") {
            let _ = std::fs::remove_file(e.path());
        }
    }
    Ok(())
}

const MACHINES: &[&str] =
    &["id=\"wwn.machines.root\"", "label=\"Machine Configuration\"", "text=\"Machine Configuration\""];

/// `keep_runner`: leave the XCTest lease for a following lane on the same session.
fn ios(keep_runner: bool) -> Result<()> {
    let device = ios_device();
    let art = artifacts()?;
    let ad = Ad::ios(&device, "wawona-ios-smoke");
    eprintln!("== iOS: boot simulator '{device}' ==");
    boot(&device);
    prepare_system_ui(&device);
    install_ios_from_env(&device)?;
    clear("ios-")?;

    // prepare and open share one daemon: stopping it makes open re-acquire the
    // runner lease under a 90 s RPC timeout, which flakes as "Daemon request timed out".
    prepare_runner(&ad)?;
    if !ad.ok(&["open", IOS_ID, "--relaunch"]) {
        eprintln!("== iOS: open timed out; prepare the same session again and retry once ==");
        stop_daemon();
        let _ = prepare_runner(&ad);
        ad.run(&["open", IOS_ID, "--relaunch"])?;
    }
    ad.wait(2500);
    ad.dismiss_continue();
    ad.soft(&["snapshot", "-i"]);
    ad.shot(&art.join("ios-first-screen.png"));

    // XCTest often collapses the Welcome modal to one node, so id= and label=
    // miss Continue. Points are logical (iPhone 17 Pro: 402x874).
    if !ad.any_visible(MACHINES) {
        let _ = ad.any_press(&["id=\"wwn.welcome.continue\"", "label=\"Continue\"", "text=\"Continue\""])
            || ad.find("Continue", "press");
        ad.ok(&["click", "201", "493"]);
        ad.wait(2500);
    }
    ad.dismiss_continue();
    let home = |long: u64| {
        ad.wait_sel(MACHINES[0], long)
            || ad.wait_sel(MACHINES[2], 8000)
            || ad.wait_sel(MACHINES[1], 5000)
            || ad.find("Machine Configuration", "exists")
    };
    if !home(20000) {
        ad.ok(&["click", "201", "500"]);
        ad.wait(2000);
        if !home(10000) && !ad.find("Start", "exists") {
            return Err(ad.fail(&art.join("ios-machines-root.png"), "iOS Machines home not reached after Welcome"));
        }
    }
    ad.shot(&art.join("ios-machines-root.png"));

    // A stray tap can leave Edit Machine open; its Cancel is often hittable:false.
    if ad.any_visible(&["text=\"Edit Machine Profile\"", "label=\"Edit Machine Profile\""]) {
        ad.any_press(&["label=\"Cancel\"", "text=\"Cancel\""]);
        ad.ok(&["swipe", "201", "560", "201", "860", "350"]);
        ad.ok(&["back"]);
        ad.wait_sel(MACHINES[0], 8000);
    }

    // Global Settings is in-app: the gear, then Display.
    if !ad.any_press(&["id=\"wwn.settings\"", "label=\"Settings\"", "id=\"wwn.settings.open\""]) {
        return Err(ad.fail(&art.join("ios-settings-open-fail.png"), "Settings gear not found on Machines home"));
    }
    ad.wait(1500);
    if !(ad.wait_sel("id=\"wwn.settings.root\"", 15000)
        || ad.wait_sel("text=\"Display\"", 8000)
        || ad.wait_sel("label=\"Display\"", 5000))
    {
        return Err(
            ad.fail(&art.join("ios-settings-root-missing.png"), "Global Settings host not visible after the gear")
        );
    }
    if !ad.any_press(&["id=\"wwn.settings.display\"", "label=\"Display\"", "text=\"Display\""]) {
        return Err(ad.fail(&art.join("ios-settings-display-missing.png"), "Settings Display row not found"));
    }
    if !(ad.wait_sel("id=\"wwn.settings.display\"", 10000) || ad.wait_sel("text=\"Display\"", 5000)) {
        return Err(ad.fail(&art.join("ios-settings-display-missing.png"), "Settings Display section not visible"));
    }
    ad.shot(&art.join("ios-settings-display.png"));

    // The Apple Watch companion section (#151) sits below Environment and Local Shell.
    let watch = ["id=\"wwn.settings.appleWatch\"", "text=\"Apple Watch\""];
    let mut found = false;
    for _ in 0..5 {
        if ad.any_visible(&watch) {
            found = true;
            break;
        }
        ad.ok(&["swipe", "200", "720", "200", "280", "400"]);
        ad.wait(400);
    }
    if !found {
        return Err(ad.fail(
            &art.join("ios-settings-apple-watch-missing.png"),
            "wwn.settings.appleWatch not visible in Settings",
        ));
    }
    ad.any_press(&watch);
    ad.wait(800);
    ad.shot(&art.join("ios-settings-apple-watch.png"));
    ad.any_press(&["id=\"wwn.settings.done\"", "label=\"Done\""]);
    ad.wait_sel(MACHINES[0], 15000);

    ad.any_press(&["id=\"wwn.machines.add\"", "label=\"Add Machine\""]);
    ad.wait(1200);
    ad.shot(&art.join("ios-add-machine-sheet.png"));
    ad.press(MACHINES[0]);
    ad.ok(&["back"]);
    ad.wait(800);

    // Start: id, label, then the card's Start point (the fuzzel .ad uses 69,374).
    if !(ad.any_press(&["id=\"wwn.machines.start\"", "label=\"Start\""])
        || ad.find("Start", "press")
        || ad.ok(&["click", "69", "374"]))
    {
        return Err(ad.fail(&art.join("ios-start-fail.png"), "Start control not found (id=wwn.machines.start)"));
    }
    ad.wait(2500);
    ad.dismiss_continue();
    ad.wait(5000);
    ad.dismiss_continue();
    ad.shot(&art.join("ios-weston-session.png"));
    ad.soft(&["close"]);
    if !keep_runner {
        stop_daemon();
    }
    Ok(())
}

fn ios_foot() -> Result<()> {
    eprintln!("== iOS Foot: Start Default Machine (bundledAppID=foot) ==");
    let device = ios_device();
    let art = artifacts()?;
    prepare_system_ui(&device);
    install_ios_from_env(&device)?;
    let target = std::env::var("WAWONA_IOS_UDID").unwrap_or_else(|_| device.clone());
    clients::set_ios("foot", &target, IOS_ID)?;
    let ad = Ad::ios(&target, "wawona-ios-foot");
    stop_daemon();
    prepare_runner(&ad)?;

    let console = art.join("ios-foot-e2e-console.log");
    let mut log = sim_udid(&target).and_then(|udid| {
        let mut c = cmd("xcrun");
        c.args(["simctl", "spawn", &udid, "log", "stream", "--level", "debug", "--predicate"]).arg(
            r#"processImagePath CONTAINS "Wawona" OR eventMessage CONTAINS "foot" OR eventMessage CONTAINS "FOOT" OR eventMessage CONTAINS "Launching""#,
        );
        let f = std::fs::File::create(&console).ok()?;
        c.stdout(f.try_clone().ok()?).stderr(f).spawn().ok()
    });

    // Welcome is skipped through prefs; a strict .ad replay would fail on the missing Continue.
    ad.run(&["open", IOS_ID, "--relaunch"])?;
    ad.wait(2500);
    ad.dismiss_continue();
    ad.shot(&art.join("ios-foot-e2e-01-home.png"));
    if !(ad.any_press(&["id=\"wwn.machines.start\"", "label=\"Start\""]) || ad.find("Start", "press")) {
        return Err(ad.fail(&art.join("ios-foot-e2e-start-fail.png"), "Start control not found for the Foot machine"));
    }
    ad.wait(2500);
    ad.dismiss_continue();
    ad.wait(8000);
    ad.dismiss_continue();
    let shot = art.join("ios-foot-e2e-02-session.png");
    ad.shot(&shot);
    ad.soft(&["close"]);
    if let Some(child) = log.as_mut() {
        let _ = child.kill();
        let _ = child.wait();
    }
    assert_png(&shot)?;

    let text = std::fs::read_to_string(&console).unwrap_or_default().to_lowercase();
    if text.contains("refusing foot launch") {
        bail!("FAIL: the foot compatibility shim is still linked");
    }
    if text.contains("failed to set initial tiocswinsz") && !text.contains("ignored on apple mobile") {
        bail!("FAIL: foot died on TIOCSWINSZ (Apple-mobile PTY)");
    }
    if text.contains("launching in-process foot") || text.contains("foot_main") {
        eprintln!("PASS: foot_main launch in the simulator console");
    } else {
        eprintln!("note: foot_main not in the console log (os_log may not match); the screenshot is the gate");
    }
    assert_lit(&shot, "ios-foot")?;
    eprintln!("== iOS Foot e2e PASSED ==");
    stop_daemon();
    Ok(())
}

/// A recorded replay on the simulator. `install`: honour WAWONA_IOS_APP first.
fn ios_replay(name: &str, install: bool) -> Result<()> {
    eprintln!("== iOS: agent-device replay {name}.ad ==");
    let device = env_or("WAWONA_IOS_DEVICE", &ios_device());
    stop_daemon();
    prepare_system_ui(&device);
    if install {
        install_ios_from_env(&device)?;
    }
    let ad = Ad::ios(&device, name);
    let _ = prepare_runner(&ad);
    // Replay starts its own daemon and needs the runner lease.
    stop_daemon();
    let result = ad.run(&["replay", &root().join(format!(".agent-device/{name}.ad")).display().to_string()]);
    stop_daemon();
    result
}

fn android_terminal() -> Result<()> {
    let Some(adb) = Adb::find() else {
        eprintln!("== Android Terminal Start: skip (no device or emulator) ==");
        return Ok(());
    };
    eprintln!("== Android Terminal Start: serial={} ==", adb.serial);
    adb.install_from_env()?;
    stop_daemon();
    let ad = adb.ad("wawona-android-terminal-start");
    let result =
        ad.run(&["replay", &root().join(".agent-device/wawona-android-terminal-start.ad").display().to_string()]);
    stop_daemon();
    result
}

fn android_machines(adb: &Adb, ad: &Ad) -> bool {
    adb.has_id("wwn.machines.root")
        || ["Machine Configuration", "Default Machine", "All Machines", "Disconnected"].iter().any(|t| adb.has_text(t))
        || (adb.has_text("Start") && adb.has_text("Edit"))
        || ad.find("Machine Configuration", "exists")
        || ad.find("Default Machine", "exists")
}

/// Compose on CI often gives an empty interactive snapshot, and UiAutomator
/// may omit text: positive markers first, then the Continue pill gone.
fn android_wait_home(adb: &Adb, ad: &Ad) -> bool {
    for elapsed in (0..30).map(|s| s * 1000) {
        if android_machines(adb, ad) {
            return true;
        }
        if elapsed >= 2500 && !adb.welcome_continue_visible() {
            eprintln!("== Android: Machines home by screencap (Continue dismissed) ==");
            return true;
        }
        sleep_ms(1000);
    }
    android_machines(adb, ad) || !adb.welcome_continue_visible()
}

fn android() -> Result<()> {
    let Some(adb) = Adb::find() else {
        eprintln!("== Android: skip (no device or emulator; set WAWONA_ANDROID_SERIAL) ==");
        return Ok(());
    };
    eprintln!("== Android: serial={} ==", adb.serial);
    adb.quiet_immersive();
    adb.install_from_env()?;
    let art = artifacts()?;
    let ad = adb.ad("wawona-android-smoke");
    clear("android-")?;

    ad.run(&["open", ANDROID_ID, "--relaunch"])?;
    ad.wait(4000);
    adb.dismiss_blockers(&ad);
    ad.soft(&["snapshot", "-i"]);
    ad.shot(&art.join("android-first-screen.png"));
    adb.dismiss_welcome(&ad);
    // UiAutomator taps and press often no-op on the Compose Welcome.
    adb.tap_ref(540, 1390);
    adb.tap(540, 1390);
    ad.wait(2000);
    adb.dismiss_blockers(&ad);
    if !android_wait_home(&adb, &ad) {
        return Err(ad.fail(&art.join("android-machines-root.png"), "Machines home not reached after Welcome"));
    }
    ad.shot(&art.join("android-machines-root.png"));
    if adb.has_text("Continue") && !android_machines(&adb, &ad) {
        return Err(ad.fail(&art.join("android-welcome-stuck.png"), "still on Welcome after Continue"));
    }
    adb.press_text(&ad, "Got it");
    ad.wait(500);

    // Settings and Add sheets leave a scrim that eats Start taps.
    if ["Cancel", "Wawona Settings", "Add Machine Profile"].iter().any(|t| adb.has_text(t))
        || adb.has_id("wwn.settings.root")
        || adb.has_id("wwn.machines.editor")
    {
        adb.press_text(&ad, "Cancel");
        let _ = adb.press_id(&ad, "wwn.settings.done") || adb.press_text(&ad, "Done");
        ad.ok(&["back"]);
        adb.key(4);
        ad.wait(800);
    }
    adb.dismiss_blockers(&ad);
    // A successful tap is enough: Compose still shows Start while CONNECTING.
    let started = adb.press_id(&ad, "wwn.machines.start")
        || adb.press_text(&ad, "Start")
        || adb.tap_ref(227, 1039)
        || adb.tap(227, 1032);
    if !started {
        if let Some(x) = adb.uia() {
            let _ = write(art.join("android-start-fail-ui.xml"), x);
        }
        return Err(ad.fail(&art.join("android-start-fail.png"), "could not press Start (id=wwn.machines.start)"));
    }
    ad.wait(8000);
    adb.dismiss_blockers(&ad);
    let _ = adb.press_text(&ad, "Got it") || adb.tap_ref(900, 720);
    ad.wait(500);
    let shot = art.join("android-weston-session.png");
    ad.shot(&shot);
    if assert_png(&shot).is_err() {
        adb.screencap(&shot)?;
    }
    ad.soft(&["close"]);
    Ok(())
}

/// The APK ships OpenSSH as libssh*_bin.so. An emulator ABI may not exec the
/// aarch64 binary, so the banner in the APK is the portable gate.
fn android_shell_ssh() -> Result<()> {
    eprintln!("== Android shell SSH: OpenSSH jniLibs banner ==");
    let apk = env_or("WAWONA_ANDROID_APK", "");
    if apk.is_empty() || !Path::new(&apk).is_file() {
        eprintln!("WAWONA_ANDROID_APK missing; skip android-shell-ssh");
        return Ok(());
    }
    let mut zip = zip::ZipArchive::new(std::fs::File::open(&apk)?)?;
    let re = regex::Regex::new(r"libssh(_keygen)?_bin\.so$").unwrap();
    let names: Vec<String> = zip.file_names().filter(|n| re.is_match(n)).map(str::to_string).collect();
    if names.is_empty() {
        bail!("FAIL: the APK has no libssh_bin.so / libssh_keygen_bin.so");
    }
    let mut found = false;
    for n in &names {
        let mut bytes = Vec::new();
        std::io::Read::read_to_end(&mut zip.by_name(n)?, &mut bytes)?;
        let has = |needle: &[u8]| bytes.windows(needle.len()).any(|w| w.eq_ignore_ascii_case(needle));
        if has(b"dropbear") {
            bail!("FAIL: Dropbear strings in {n}");
        }
        if bytes.windows(8).any(|w| w == b"OpenSSH_") {
            found = true;
            eprintln!("OK OpenSSH_ in {n}");
        } else {
            eprintln!("note: no OpenSSH_ banner in {n}");
        }
    }
    if !found {
        bail!("FAIL: no OpenSSH_ banner in the bundled ssh libraries");
    }
    if let Some(adb) = Adb::find() {
        let so = adb
            .shell(&format!("find /data/app /data/data/{ANDROID_ID} -name libssh_bin.so 2>/dev/null | head -1"))
            .unwrap_or_default();
        let so = so.trim();
        if !so.is_empty() {
            eprintln!("== Android: exec {so} -V ==");
            let out = try_output(adb.command().args(["shell", &format!("\"{so}\" -V 2>&1")])).unwrap_or_default();
            let _ = write(artifacts()?.join("android-shell-ssh-V.txt"), &out);
            if out.contains("OpenSSH_") {
                eprintln!("OK on-device ssh -V");
            } else {
                eprintln!("note: on-device -V unavailable (ABI); the APK banner passed");
            }
        }
    }
    Ok(())
}

fn xkb(platform: &str) -> Result<()> {
    let art = artifacts()?;
    let session = format!("xkb-{platform}");
    // Replay and prepare must share one lease.
    stop_daemon();
    let ad = match platform {
        "ios" | "ipados" | "tvos" | "visionos" => {
            let (var, default, listed) = match platform {
                "ios" => ("WAWONA_IOS_SIM", "iPhone 17 Pro", "iPhone"),
                "ipados" => ("WAWONA_IPAD_SIM", "iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M5)"),
                "tvos" => ("WAWONA_TV_SIM", "Apple TV 4K (3rd generation)", "Apple TV"),
                _ => ("WAWONA_VISION_SIM", "Apple Vision Pro", "Vision"),
            };
            let device = env_or(var, default);
            if platform != "ios" && !sim_available(listed) {
                eprintln!("SKIP xkb-{platform}: no '{listed}' simulator installed");
                return Ok(());
            }
            eprintln!("== xkb {platform}: Multi-Touch + weston-terminal ==");
            boot(&device);
            let _ = clients::set_ios("weston-terminal", &device, IOS_ID);
            let ad = Ad::ios(&device, &session);
            if platform != "tvos" {
                prepare_system_ui(&device);
            }
            if matches!(platform, "ios" | "ipados") {
                let _ = prepare_runner(&ad);
            }
            ad
        }
        "watchos" => {
            // agent-device has no watchOS runner: simctl launch and simctl io screenshot.
            let device = env_or("WAWONA_WATCH_SIM", "Apple Watch Series 11 (46mm)");
            eprintln!("== xkb watchOS: Start + MINIMAL_KEYMAP (no Watch blob) ==");
            if !sim_available("Watch") {
                eprintln!("SKIP xkb-watchos: no Watch simulator listed");
                return Ok(());
            }
            boot(&device);
            let _ = try_output(cmd("xcrun").args([
                "simctl",
                "launch",
                &device,
                &env_or("WAWONA_WATCH_BUNDLE", "com.aspauldingcode.Wawona.watch"),
            ]));
            sleep_ms(4000);
            let shot = art.join("xkb-watchos-term.png");
            let _ = try_output(cmd("xcrun").args(["simctl", "io", &device, "screenshot"]).arg(&shot));
            eprintln!("xkb-watchos: simctl screenshot at {}", shot.display());
            return Ok(());
        }
        "android" => {
            let Some(adb) = Adb::find() else {
                eprintln!("SKIP xkb-android: no adb device or emulator");
                return Ok(());
            };
            let chars = adb.shell("getprop ro.build.characteristics").unwrap_or_default();
            if chars.contains("watch") {
                eprintln!("SKIP xkb-android: {} is Wear OS ({}), not a phone", adb.serial, chars.trim());
                return Ok(());
            }
            eprintln!("== xkb Android: Touchpad Off + OSK type ==");
            let _ = clients::set_android("weston-terminal", &adb);
            adb.ad(&session)
        }
        "macos" => {
            eprintln!("== xkb macOS Mode A: type into weston-terminal (no Take Over) ==");
            let ad = Ad::macos(&session).with(&["--device", "mba"]);
            // agent-device reads mixed-case bundle ids as names: open by display name.
            ad.run(&["open", "Wawona"])?;
            ad.wait(3000);
            ad.any_press(&["id=\"wwn.machines.start\"", "label=\"Start\""]);
            ad.wait(6000);
            if !ad.ok(&["type", "xkbhello"]) {
                ad.ok(&["close"]);
                bail!("xkb-macos: type failed (macos-helper timeout or no session)");
            }
            let shot = art.join("xkb-macos-term.png");
            ad.shot(&shot);
            ad.ok(&["close"]);
            return assert_png(&shot);
        }
        other => bail!("unknown xkb platform: {other}"),
    };
    for suffix in ["term", "typed"] {
        let _ = std::fs::remove_file(art.join(format!("xkb-{platform}-{suffix}.png")));
    }
    // prepare held the XCTest lease; replay starts its own daemon.
    stop_daemon();
    if let Err(e) = ad.run(&["replay", &root().join(".agent-device/wawona-xkb-smoke.ad").display().to_string()]) {
        bail!("xkb-{platform} replay failed: {e}");
    }
    ad.shot(&art.join(format!("xkb-{platform}-term.png")));
    let logs = try_output(cmd("agent-device").arg("logs").args(ad_common_args(&ad))).unwrap_or_default();
    for l in
        logs.lines().filter(|l| l.contains("xkb: using") || l.contains("text_input") || l.contains("HostKeymapBridge"))
    {
        eprintln!("{l}");
    }
    ad.ok(&["close"]);
    stop_daemon();
    Ok(())
}

fn ad_common_args(ad: &Ad) -> Vec<String> {
    ad.args()
}

fn vphone() -> Result<()> {
    let device = env_or("WAWONA_VPHONE_DEVICE", "vphone wawona-jb");
    let session = "wawona-ios-vphone-smoke";
    eprintln!("== vphone Mode B replay (research VM, not the Simulator) ==");
    std::fs::create_dir_all(artifacts()?.join("modeb-ios"))?;
    run(cmd("agent-device").args(["devices", "--device", &device]))?;
    let _ = try_output(cmd("agent-device").args(["packages", "status", "--device", &device]));
    eprintln!("== packages tipa open-jit com.aspauldingcode.Wawona.ModeB ==");
    let _ = cmd("agent-device")
        .args([
            "packages",
            "tipa",
            "open-jit",
            "com.aspauldingcode.Wawona.ModeB",
            "--device",
            &device,
            "--session",
            session,
        ])
        .status();
    let replay = root().join(".agent-device/wawona-ios-vphone-smoke.ad");
    run(cmd("agent-device").arg("replay").arg(replay).args([
        "--device",
        &device,
        "--session",
        session,
        "--platform",
        "ios",
    ]))
}
