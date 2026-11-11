//! `cargo xtask lab leak <target>`: launch the product, sample its memory
//! for WAWONA_LEAK_HOLD_SEC, and fail on growth.
//!
//! Runner tools only: simctl and `vmmap` phys_footprint on Apple, adb,
//! UiAutomator and `dumpsys meminfo` TOTAL PSS on Android. xctrace
//! Allocations is empty on the iOS 26 simulator, so it is not used.
//! A pass is a plateau: after the warm-up sample, (max - min) is at most
//! WAWONA_LEAK_PLATEAU_MB and the series is not a strict climb of at least
//! WAWONA_LEAK_MONO_MB.

use super::ad::*;
use crate::util::*;
use anyhow::Result;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::process::Stdio;

#[derive(Clone, Copy, PartialEq, clap::ValueEnum)]
pub enum Target {
    Ios,
    Android,
    Macos,
    All,
    /// Print the verdicts already written.
    Summary,
}

fn num(var: &str, default: f64) -> f64 {
    std::env::var(var).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn out_root() -> PathBuf {
    root().join(".agent-device/test-artifacts/leak-idle-gate")
}

fn now_iso() -> String {
    try_output(cmd("date").args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])).unwrap_or_default().trim().to_string()
}

pub fn plateau(samples: &[f64], plateau_mb: f64, mono_mb: f64) -> Value {
    let steady = samples.get(1..).unwrap_or_default();
    let (mut status, mut reason, mut spread) = ("fail", "no_samples".to_string(), None);
    if !steady.is_empty() {
        let (mn, mx) = steady.iter().fold((f64::MAX, f64::MIN), |(a, b), &x| (a.min(x), b.max(x)));
        let s = mx - mn;
        spread = Some(s);
        let strict = steady.windows(2).all(|w| w[0] < w[1]);
        let climb = if steady.len() >= 2 { steady[steady.len() - 1] - steady[0] } else { 0.0 };
        (status, reason) = if s > plateau_mb {
            ("fail", format!("plateau_spread_mb={s:.2}>{plateau_mb}"))
        } else if strict && climb >= mono_mb {
            ("fail", format!("monotonic_climb_mb={climb:.2}>={mono_mb}"))
        } else {
            ("pass", format!("plateau_spread_mb={s:.2}<={plateau_mb}"))
        };
    }
    json!({
        "status": status,
        "reason": reason,
        "samples_mb": samples,
        "ignored_warmup_samples": if samples.is_empty() { 0 } else { 1 },
        "steady_samples_mb": steady,
        "spread_mb": spread,
        "plateau_limit_mb": plateau_mb,
        "mono_limit_mb": mono_mb,
    })
}

/// "Physical footprint:  71.8M" or "PhysFootprint: 73400K", in MB.
pub fn phys_footprint_mb(text: &str) -> Option<f64> {
    let line = text
        .lines()
        .find(|l| {
            let l = l.to_lowercase();
            l.contains("physfootprint") || l.contains("physical footprint")
        })
        .or_else(|| text.lines().find(|l| l.to_lowercase().contains("phys_footprint")))?;
    let c = regex::Regex::new(r"[: ]([0-9]+(?:\.[0-9]+)?)\s*([KkMmGg])").unwrap().captures(line)?;
    let v: f64 = c[1].parse().ok()?;
    Some(match &c[2] {
        "K" | "k" => v / 1024.0,
        "G" | "g" => v * 1024.0,
        _ => v,
    })
}

/// TOTAL PSS from `dumpsys meminfo`; the line's last integer is SWAP PSS, not PSS.
pub fn total_pss_mb(text: &str) -> Option<f64> {
    let kb = text
        .lines()
        .find_map(|l| regex::Regex::new(r"TOTAL PSS:\s+([0-9]+)").unwrap().captures(l).map(|c| c[1].to_string()))
        .or_else(|| {
            text.lines()
                .find_map(|l| regex::Regex::new(r"^\s*TOTAL\s+([0-9]+)").unwrap().captures(l).map(|c| c[1].to_string()))
        })?;
    Some(kb.parse::<f64>().ok()? / 1024.0)
}

fn apple_mb(pid: u32, udid: Option<&str>) -> Option<f64> {
    let p = pid.to_string();
    let sim = udid.and_then(|u| try_output(cmd("xcrun").args(["simctl", "spawn", u, "vmmap", "--summary", &p])));
    let out = sim.filter(|s| !s.trim().is_empty()).or_else(|| try_output(cmd("vmmap").args(["--summary", &p])))?;
    phys_footprint_mb(&out)
}

/// Samples every WAWONA_LEAK_SAMPLE_SEC through the hold; true when the plateau holds.
fn sample_hold(target: &str, dir: &Path, sample: impl Fn() -> Option<f64>) -> Result<bool> {
    let hold = num("WAWONA_LEAK_HOLD_SEC", 60.0) as u64;
    let every = (num("WAWONA_LEAK_SAMPLE_SEC", 15.0) as u64).max(1);
    let mut timeline = format!(
        "# target={target} hold_sec={hold} sample_sec={every} plateau_mb={}\n# t_sec mb iso\n",
        num("WAWONA_LEAK_PLATEAU_MB", 20.0)
    );
    let mut samples = Vec::new();
    let mut t = 0;
    loop {
        let Some(mb) = sample() else {
            eprintln!("FAIL: empty sample at t={t}s ({target})");
            write(dir.join(format!("{target}-timeline.txt")), &timeline)?;
            return Ok(false);
        };
        timeline += &format!("{t} {mb:.3} {}\n", now_iso());
        samples.push(mb);
        if t >= hold {
            break;
        }
        sleep_ms(every * 1000);
        t += every;
    }
    write(dir.join(format!("{target}-timeline.txt")), timeline)?;
    write(
        dir.join(format!("{target}-samples.csv")),
        samples.iter().map(|s| format!("{s:.3}")).collect::<Vec<_>>().join(",") + "\n",
    )?;
    let verdict = plateau(&samples, num("WAWONA_LEAK_PLATEAU_MB", 20.0), num("WAWONA_LEAK_MONO_MB", 8.0));
    let pass = verdict["status"] == "pass";
    write(dir.join(format!("{target}-plateau.json")), serde_json::to_string_pretty(&verdict)? + "\n")?;
    Ok(pass)
}

fn verdict(target: &str, status: &str, reason: &str) -> Result<()> {
    let dir = out_root().join(target);
    std::fs::create_dir_all(&dir)?;
    let mut payload = json!({
        "target": target,
        "status": status,
        "reason": reason,
        "ts": now_iso(),
        "hold_sec": num("WAWONA_LEAK_HOLD_SEC", 60.0) as u64,
        "plateau_mb": num("WAWONA_LEAK_PLATEAU_MB", 20.0),
    });
    if let Some(p) = std::fs::read_to_string(dir.join(format!("{target}-plateau.json")))
        .ok()
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
    {
        payload["plateau"] = p;
    }
    let body = serde_json::to_string_pretty(&payload)? + "\n";
    write(dir.join("verdict.json"), &body)?;
    write(dir.join(format!("verdict-{target}.json")), &body)?;
    write(dir.join("status.txt"), format!("{status}\n"))?;
    write(dir.join(format!("status-{target}.txt")), format!("{status}\n"))?;
    eprintln!("== verdict {target}: {status} ({reason}) ==");
    Ok(())
}

/// Ok(true) pass, Ok(false) fail; a skip writes its verdict and returns Ok(!strict).
fn skip(target: &str, why: &str) -> Result<bool> {
    verdict(target, "skip", why)?;
    Ok(!env_flag("WAWONA_LEAK_STRICT"))
}

fn fail(target: &str, why: &str) -> Result<bool> {
    verdict(target, "fail", why)?;
    Ok(false)
}

fn ios() -> Result<bool> {
    let dir = out_root().join("ios");
    std::fs::create_dir_all(&dir)?;
    let device = ios_device();
    let bundle = env_or("WAWONA_IOS_BUNDLE", IOS_ID);
    eprintln!("== iOS leak-idle: simulator '{device}' (simctl) ==");
    if !sim_available(&format!("{device} (")) {
        eprintln!("Creating simulator '{device}'");
        let types = output(cmd("xcrun").args(["simctl", "list", "devicetypes"]))?;
        let runtimes = output(cmd("xcrun").args(["simctl", "list", "runtimes"]))?;
        let ty = types
            .lines()
            .find(|l| l.contains(&format!("{device} (")))
            .and_then(|l| l.rsplit('(').next())
            .map(|s| s.trim_end_matches(')'));
        let rt = runtimes.lines().rfind(|l| l.starts_with("iOS")).and_then(|l| l.split_whitespace().last());
        if let (Some(ty), Some(rt)) = (ty, rt) {
            run(cmd("xcrun").args(["simctl", "create", &device, ty, rt]))?;
        }
    }
    let Some(udid) = sim_udid(&device) else { return fail("ios", "no_sim_udid") };
    boot(&udid);
    if let Ok(app) = std::env::var("WAWONA_IOS_APP") {
        if !app.is_empty() {
            install_ios(&udid, Path::new(&app))?;
        }
    }
    let terminate = || {
        let _ = try_output(cmd("xcrun").args(["simctl", "terminate", &udid, &bundle]));
    };
    terminate();
    let launch = cmd("xcrun").args(["simctl", "launch", &udid, &bundle]).output()?;
    write(dir.join("launch.out"), &launch.stdout)?;
    write(dir.join("launch.err"), &launch.stderr)?;
    if !launch.status.success() {
        return fail("ios", &format!("simctl_launch_rc={}", launch.status.code().unwrap_or(-1)));
    }
    let pid_of = || {
        let list = try_output(cmd("xcrun").args(["simctl", "spawn", &udid, "launchctl", "list"]))?;
        list.lines()
            .filter(|l| l.split_whitespace().nth(2).is_some_and(|c| c.contains(&bundle)))
            .find_map(|l| l.split_whitespace().next()?.parse::<u32>().ok())
    };
    let mut pid = None;
    for _ in 0..45 {
        pid = pid_of();
        if pid.is_some() {
            break;
        }
        sleep_ms(1000);
    }
    let _ = try_output(cmd("xcrun").args(["simctl", "io", &udid, "screenshot"]).arg(dir.join("ios-running.png")));
    let Some(pid) = pid else {
        terminate();
        return fail("ios", "pid_not_found");
    };
    eprintln!("== iOS pid={pid} udid={udid} ==");
    let ok = sample_hold("ios", &dir, || apple_mb(pid, Some(&udid)))?;
    terminate();
    if !ok {
        return fail("ios", "plateau_or_sample");
    }
    let _ = try_output(cmd("xcrun").args(["simctl", "io", &udid, "screenshot"]).arg(dir.join("ios-after-stop.png")));
    verdict("ios", "pass", "plateau_ok")?;
    Ok(true)
}

fn android() -> Result<bool> {
    let dir = out_root().join("android");
    std::fs::create_dir_all(&dir)?;
    let Some(adb) = Adb::find() else {
        eprintln!("== Android: no device ==");
        return skip("android", "no_device");
    };
    eprintln!("== Android leak-idle: serial={} (adb + uiautomator) ==", adb.serial);
    adb.quiet_immersive();
    adb.install_from_env()?;
    let blockers = || adb.quiet("am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS");
    let force_stop = || adb.quiet(&format!("am force-stop {ANDROID_ID}"));
    let activity = env_or("WAWONA_ANDROID_ACTIVITY", &format!("{ANDROID_ID}.MainActivity"));
    force_stop();
    let started = try_output(adb.command().args(["shell", &format!("am start -W -n {ANDROID_ID}/{activity}")]))
        .unwrap_or_default();
    write(dir.join("am-start.txt"), started)?;
    sleep_ms(3000);
    blockers();
    let _ = adb.uia_tap_id("wwn.welcome.continue") || adb.uia_tap_text("Continue");
    sleep_ms(2000);
    blockers();
    let evidence = |png: &str, xml: &str| {
        let _ = adb.screencap(&dir.join(png));
        if let Some(x) = adb.uia() {
            let _ = write(dir.join(xml), x);
        }
    };
    if !wait_for(20, 1000, || adb.has_id("wwn.machines.root"))
        && !wait_for(8, 1000, || adb.has_text("Machine Configuration"))
    {
        evidence("android-no-machines.png", "android-no-machines-ui.xml");
        force_stop();
        return fail("android", "machines_home_not_reached");
    }
    blockers();
    if !(adb.uia_tap_id("wwn.machines.start") || adb.uia_tap_text("Start") || adb.tap_ref(227, 1039)) {
        evidence("android-start-fail.png", "android-start-fail-ui.xml");
        force_stop();
        return fail("android", "start_not_found");
    }
    sleep_ms(5000);
    let _ = adb.screencap(&dir.join("android-running.png"));
    let ok = sample_hold("android", &dir, || total_pss_mb(&adb.shell(&format!("dumpsys meminfo {ANDROID_ID}"))?))?;
    let _ = adb.uia_tap_id("wwn.machines.stop") || adb.uia_tap_text("Stop");
    let _ = adb.screencap(&dir.join(if ok { "android-after-stop.png" } else { "android-after-fail.png" }));
    force_stop();
    if !ok {
        return fail("android", "plateau_or_sample");
    }
    verdict("android", "pass", "plateau_ok")?;
    Ok(true)
}

/// Samples the idle host: the runner has no TCC grant to press Start.
fn macos() -> Result<bool> {
    let dir = out_root().join("macos");
    std::fs::create_dir_all(&dir)?;
    let mut app = PathBuf::from(env_or("WAWONA_MACOS_APP", ""));
    if !app.is_dir() {
        app = crate::product::target("macos").map(|t| t.app(false, true)).unwrap_or_default();
    }
    if !app.is_dir() {
        eprintln!("== macOS: no Wawona.app (set WAWONA_MACOS_APP) ==");
        return skip("macos", "no_app");
    }
    if let Some(other) = try_output(cmd("pgrep").args(["-x", "Wawona"])) {
        return fail("macos", &format!("another Wawona is running (pid {}); quit it first", other.trim()));
    }
    eprintln!("== macOS leak-idle: {} ==", app.display());
    let _ = try_output(cmd("xattr").arg("-cr").arg(&app));
    for d in ["Contents/MacOS", "Contents/Resources/bin"] {
        let _ = try_output(cmd("chmod").args(["-R", "u+x"]).arg(app.join(d)));
    }
    let log = std::fs::File::create(dir.join("macos-app.log"))?;
    let mut child =
        cmd(app.join("Contents/MacOS/Wawona")).stdin(Stdio::null()).stdout(log.try_clone()?).stderr(log).spawn()?;
    let pid = child.id();
    sleep_ms(num("WAWONA_LEAK_LAUNCH_SETTLE_SEC", 4.0) as u64 * 1000);
    if child.try_wait()?.is_some() {
        return fail("macos", "exited at launch (see macos-app.log)");
    }
    eprintln!("== macOS pid={pid} ==");
    let ok = sample_hold("macos", &dir, || apple_mb(pid, None))?;
    if ok && have("leaks") {
        let out = try_output(cmd("leaks").arg(pid.to_string())).unwrap_or_default();
        write(dir.join("macos-leaks.txt"), out)?;
    }
    let _ = child.kill();
    let _ = child.wait();
    if !ok {
        return fail("macos", "plateau_or_sample");
    }
    verdict("macos", "pass", "plateau_ok")?;
    Ok(true)
}

type Lane = fn() -> Result<bool>;

fn summary() -> bool {
    let (mut pass, mut skip, mut fail) = (vec![], vec![], vec![]);
    let mut dirs: Vec<_> =
        std::fs::read_dir(out_root()).into_iter().flatten().flatten().filter(|e| e.path().is_dir()).collect();
    dirs.sort_by_key(|e| e.file_name());
    for d in dirs {
        let t = d.file_name().to_string_lossy().into_owned();
        match std::fs::read_to_string(d.path().join("status.txt")).unwrap_or_default().trim() {
            "pass" => pass.push(t),
            "skip" => skip.push(t),
            _ => fail.push(t),
        }
    }
    println!("LEAK_GATE_PASS targets={}", pass.join(","));
    println!("LEAK_GATE_SKIP targets={}", skip.join(","));
    if !fail.is_empty() {
        println!("LEAK_GATE_FAIL targets={}", fail.join(","));
    }
    fail.is_empty()
}

/// Exit 1 when a target fails; 2 when WAWONA_LEAK_STRICT=1 and one skipped.
pub fn main(target: Target) -> Result<()> {
    std::fs::create_dir_all(out_root())?;
    if target == Target::Summary {
        std::process::exit(if summary() { 0 } else { 1 });
    }
    eprintln!(
        "== leak-idle-gate: hold={}s sample={}s plateau={}MB mono={}MB ==",
        num("WAWONA_LEAK_HOLD_SEC", 60.0),
        num("WAWONA_LEAK_SAMPLE_SEC", 15.0),
        num("WAWONA_LEAK_PLATEAU_MB", 20.0),
        num("WAWONA_LEAK_MONO_MB", 8.0)
    );
    let lanes: &[(&str, Lane)] = match target {
        Target::Ios => &[("ios", ios)],
        Target::Android => &[("android", android)],
        Target::Macos => &[("macos", macos)],
        _ => &[("ios", ios), ("android", android), ("macos", macos)],
    };
    let (mut failed, mut strict_skip) = (false, false);
    for (name, lane) in lanes {
        if !lane()? {
            let status = std::fs::read_to_string(out_root().join(name).join("status.txt")).unwrap_or_default();
            if status.trim() == "skip" {
                strict_skip = true;
            } else {
                failed = true;
            }
        }
    }
    summary();
    if failed {
        std::process::exit(1);
    }
    if strict_skip {
        std::process::exit(2);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn plateau_ignores_warmup_and_catches_a_climb() {
        assert_eq!(super::plateau(&[300.0, 100.0, 104.0, 102.0], 20.0, 8.0)["status"], "pass");
        assert_eq!(super::plateau(&[100.0, 100.0, 105.0, 110.0], 20.0, 8.0)["status"], "fail");
        assert_eq!(super::plateau(&[100.0, 100.0, 130.0], 20.0, 8.0)["status"], "fail");
        assert_eq!(super::plateau(&[], 20.0, 8.0)["reason"], "no_samples");
    }

    #[test]
    fn parses_footprint_and_pss() {
        assert_eq!(super::phys_footprint_mb("Physical footprint:         71.8M"), Some(71.8));
        assert_eq!(super::phys_footprint_mb("PhysFootprint: 2048K"), Some(2.0));
        let pss = "  TOTAL PSS:    90464            TOTAL RSS:   191800       TOTAL SWAP PSS:      174";
        assert_eq!(super::total_pss_mb(pss), Some(90464.0 / 1024.0));
    }
}
