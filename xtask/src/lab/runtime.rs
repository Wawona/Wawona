//! Gate: products runtime smokes: install or start the built product, assert
//! it stays alive, and keep the evidence under
//! `.agent-device/test-artifacts/ci-<platform>-runtime/`.

use crate::util::*;
use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::Duration;

fn out_dir(platform: &str) -> Result<PathBuf> {
    let d = PathBuf::from(env_or("WAWONA_SMOKE_OUT", &format!(".agent-device/test-artifacts/ci-{platform}-runtime")));
    std::fs::create_dir_all(&d)?;
    Ok(d)
}

fn summary(line: &str) {
    if let Ok(p) = std::env::var("GITHUB_STEP_SUMMARY") {
        let _ = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(p)
            .and_then(|mut f| std::io::Write::write_all(&mut f, format!("{line}\n").as_bytes()));
    }
}

fn log_head(p: &Path, lines: usize) {
    for l in std::fs::read_to_string(p).unwrap_or_default().lines().take(lines) {
        eprintln!("  {l}");
    }
}

/// A child this smoke started and kills on every exit path.
struct Owned(Child);

impl Owned {
    fn spawn(c: &mut Command, log: &Path) -> Result<Owned> {
        let f = std::fs::File::create(log)?;
        let child = c.stdin(Stdio::null()).stdout(f.try_clone()?).stderr(f).spawn().with_context(|| render(c))?;
        Ok(Owned(child))
    }
    fn alive(&mut self) -> bool {
        matches!(self.0.try_wait(), Ok(None))
    }
}

impl Drop for Owned {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

/// Starts `bin` and waits for `socket` to appear under `runtime`.
fn host(mut c: Command, runtime: &Path, socket: &str, wait: u64, log: &Path) -> Result<Owned> {
    std::fs::create_dir_all(runtime)?;
    std::fs::set_permissions(runtime, std::os::unix::fs::PermissionsExt::from_mode(0o700))?;
    for stale in [socket.to_string(), format!("{socket}.lock"), "instance.lock".into()] {
        let _ = std::fs::remove_file(runtime.join(stale));
    }
    let mut h = Owned::spawn(c.env("XDG_RUNTIME_DIR", runtime), log)?;
    let path = runtime.join(socket);
    let mut died = false;
    let up = wait_for(wait, 500, || {
        died = !h.alive();
        died || socket_accepts(&path)
    });
    if !up || died {
        log_head(log, 120);
        bail!("{} before {} appeared", if died { "the compositor exited" } else { "timed out" }, path.display());
    }
    eprintln!("socket up: {}", path.display());
    Ok(h)
}

pub fn macos() -> Result<()> {
    let bin = match std::env::var("WAWONA_APP_BIN") {
        Ok(b) => PathBuf::from(b),
        Err(_) => crate::product::target("macos")?.app(false, false).join("Contents/MacOS/Wawona"),
    };
    if !is_executable(&bin) {
        bail!("{} is missing: cargo xtask build macos, or set WAWONA_APP_BIN", bin.display());
    }
    let res = bin.parent().and_then(Path::parent).map(|c| c.join("Resources")).unwrap_or_default();
    let runtime = wawona_runtime();
    let socket = env_or("WAYLAND_DISPLAY", "wayland-0");
    let out = out_dir("macos")?;
    let mut c = Command::new(&bin);
    c.arg("--compositor-host");
    let mut h = host(c, &runtime, &socket, env_or("WAWONA_SMOKE_SOCKET_WAIT", "60").parse()?, &out.join("host.log"))?;
    let hold: u64 = env_or("WAWONA_SMOKE_CLIENT_SECS", "6").parse()?;
    let mut failures = 0;
    // weston-clickdot is left out: compositor-host sends a 0x0 first configure
    // (the size authority holds it) and clickdot then crashes.
    for name in ["weston-simple-shm", "weston-flower", "weston-smoke"] {
        let found = [res.join("bin").join(name), res.join("libexec").join(name), bin.with_file_name(name)]
            .into_iter()
            .find(|p| is_executable(p))
            .or_else(|| which(name));
        let Some(client) = found else {
            eprintln!("SKIP  {name} (not bundled)");
            continue;
        };
        let log = out.join(format!("{name}.log"));
        let mut c =
            Owned::spawn(Command::new(&client).env("XDG_RUNTIME_DIR", &runtime).env("WAYLAND_DISPLAY", &socket), &log)?;
        std::thread::sleep(Duration::from_secs(hold));
        if c.alive() {
            eprintln!("PASS  {name}");
        } else {
            eprintln!("FAIL  {name} (exited early: {:?})", c.0.wait()?);
            log_head(&log, 60);
            failures += 1;
        }
    }
    if !h.alive() {
        log_head(&out.join("host.log"), 160);
        bail!("the compositor died during the client matrix");
    }
    if failures > 0 {
        bail!("{failures} client(s) failed");
    }
    summary("**PASS:** macOS compositor-host runtime smoke");
    Ok(())
}

/// Linux nightly: the compositor host, a nested Weston with XWayland on a child
/// socket, then a nested niri when one is available.
pub fn capability() -> Result<()> {
    if !cfg!(target_os = "linux") {
        bail!("the capability lane is Linux-only");
    }
    let runtime = PathBuf::from(env_or("WAWONA_CAP_RUNTIME_DIR", &format!("/tmp/wawona-cap-{}", uid())));
    // The Linux host names its socket wawona-0 (src/linux/service.rs).
    let socket = env_or("WAYLAND_DISPLAY", "wawona-0");
    let out = out_dir("linux-capability")?;
    // The prebuilt binary: the cargo-run app would compile inside the socket wait.
    let ui = output(cmd("nix").args([
        "build",
        &format!("{}#wawona-linux-ui-bin", root().display()),
        "--print-out-paths",
        "--no-link",
    ]))?;
    let bin = PathBuf::from(ui.trim()).join("bin/wawona-linux-compositor-host");
    let wait: u64 = env_or("WAWONA_CAP_SOCKET_WAIT", "90").parse()?;
    let nested_wait: u64 = env_or("WAWONA_CAP_NESTED_WAIT", "30").parse()?;
    let mut h = host(Command::new(&bin), &runtime, &socket, wait, &out.join("host.log"))?;

    let weston = which("weston").map(Ok).unwrap_or_else(|| -> Result<PathBuf> {
        let p = try_output(cmd("nix").args([
            "build",
            &format!("{}#weston", root().display()),
            "--print-out-paths",
            "--no-link",
        ]))
        .map(Ok)
        .unwrap_or_else(|| output(cmd("nix").args(["build", "nixpkgs#weston", "--print-out-paths", "--no-link"])))?;
        Ok(PathBuf::from(p.trim()).join("bin/weston"))
    })?;
    let child = "wayland-cap-child";
    let wlog = out.join("nested-weston.log");
    let mut w = Owned::spawn(
        Command::new(&weston)
            .args(["--backend=wayland", &format!("--socket={child}"), "--xwayland"])
            .env("XDG_RUNTIME_DIR", &runtime)
            .env("WAYLAND_DISPLAY", &socket),
        &wlog,
    )?;
    let mut died = false;
    if !wait_for(nested_wait, 500, || {
        died = !w.alive();
        died || runtime.join(child).exists()
    }) || died
    {
        log_head(&wlog, 120);
        bail!("the nested Weston child socket never appeared");
    }
    eprintln!("PASS: nested child socket up ({child})");
    let wtext = std::fs::read_to_string(&wlog).unwrap_or_default().to_lowercase();
    if ["xwayland", "display=", "x11"].iter().any(|k| wtext.contains(k)) {
        eprintln!("PASS: XWayland bridge initialized");
    } else {
        eprintln!("NOTE: XWayland readiness not in the log (it may start lazily)");
    }

    match std::env::var("WAWONA_CAP_NIRI_BIN").ok().map(PathBuf::from).or_else(|| which("niri")) {
        Some(niri) => {
            let nlog = out.join("nested-niri.log");
            let mut n = Owned::spawn(
                Command::new(&niri)
                    .env("NIRI_BACKEND", "nested")
                    .env("XDG_RUNTIME_DIR", &runtime)
                    .env("WAYLAND_DISPLAY", &socket),
                &nlog,
            )?;
            let re = regex::Regex::new(r"listening on Wayland socket: (\S+)")?;
            let mut sock = None;
            let mut died = false;
            wait_for(nested_wait, 500, || {
                died = !n.alive();
                sock = re
                    .captures(&std::fs::read_to_string(&nlog).unwrap_or_default())
                    .map(|c| c[1].to_string())
                    .filter(|s| runtime.join(s).exists());
                died || sock.is_some()
            });
            match sock {
                Some(s) => eprintln!("PASS: nested niri child socket up ({s})"),
                None => {
                    log_head(&nlog, 120);
                    bail!("the nested niri child socket never appeared");
                }
            }
        }
        None => eprintln!("NOTE: no niri binary (set WAWONA_CAP_NIRI_BIN); skipping the nested niri stage"),
    }
    if !h.alive() {
        bail!("the parent compositor died");
    }
    eprintln!("capability lane PASSED");
    Ok(())
}

pub fn android() -> Result<()> {
    let apk = PathBuf::from(std::env::var("WAWONA_ANDROID_APK").context("set WAWONA_ANDROID_APK")?);
    let pkg = env_or("WAWONA_ANDROID_PACKAGE", "com.aspauldingcode.wawona");
    let activity = env_or("WAWONA_ANDROID_ACTIVITY", "com.aspauldingcode.wawona.MainActivity");
    let out = out_dir("android")?;
    if !apk.is_file() {
        bail!("{} is missing", apk.display());
    }
    let adb = |args: &[&str]| try_output(cmd("adb").args(args));
    run(cmd("adb").arg("wait-for-device"))?;
    if !wait_for(240, 2000, || adb(&["shell", "getprop", "sys.boot_completed"]).is_some_and(|s| s.trim() == "1")) {
        bail!("the emulator never finished booting");
    }
    adb(&["uninstall", &pkg]);
    run(cmd("adb").args(["install", "-r"]).arg(&apk))?;
    adb(&["shell", "am", "force-stop", &pkg]);
    let start = output(cmd("adb").args(["shell", "am", "start", "-W", "-n", &format!("{pkg}/{activity}")]))?;
    std::fs::write(out.join("am-start.txt"), &start)?;
    let alive = wait_for(45, 1000, || {
        adb(&["shell", "pidof", &pkg]).is_some_and(|s| s.trim().chars().any(|c| c.is_ascii_digit()))
    });
    if let Ok(png) = cmd("adb").args(["exec-out", "screencap", "-p"]).output() {
        std::fs::write(out.join("launch.png"), png.stdout)?;
    }
    adb(&["shell", "uiautomator", "dump", "/sdcard/wawona-ui.xml"]);
    adb(&["pull", "/sdcard/wawona-ui.xml", &out.join("wawona-ui.xml").display().to_string()]);
    if !alive {
        let err = adb(&["logcat", "-d", "-t", "80", "*:E"]).unwrap_or_default();
        std::fs::write(out.join("logcat-err.txt"), &err)?;
        eprintln!("{err}");
        bail!("{pkg} is not running after am start");
    }
    eprintln!("PASS: adb install + am start (process alive)");
    // Instrumentation needs the matching debug variant, so it is opt-in.
    if env_flag("WAWONA_ANDROID_ESPRESSO") {
        run(cmd(root().join("android/gradlew"))
            .current_dir(root().join("android"))
            .args([":Wawona:connectedDebugAndroidTest", "--stacktrace"]))?;
        eprintln!("PASS: connectedDebugAndroidTest");
    } else if std::fs::read_to_string(out.join("wawona-ui.xml"))
        .is_ok_and(|x| x.contains("wwn.machines.") || x.contains("wwn.welcome."))
    {
        eprintln!("PASS: the uiautomator dump shows Wawona's accessibility tags");
    }
    summary("**PASS:** Android adb install + launch");
    Ok(())
}

/// simctl install, launch, alive after a settle, screenshot. A simulator app
/// is a host process, so its pid is checked directly.
pub fn ios() -> Result<()> {
    let app = match std::env::var("WAWONA_IOS_APP") {
        Ok(a) => PathBuf::from(a),
        Err(_) => crate::product::target("ios")?.app(false, false),
    };
    let id = env_or("WAWONA_IOS_BUNDLE_ID", "com.aspauldingcode.Wawona");
    let name = env_or("WAWONA_IOS_SIM", "iPhone 17 Pro");
    let out = out_dir("ios")?;
    if !app.join("Info.plist").is_file() {
        bail!("{} is missing: cargo xtask build ios, or set WAWONA_IOS_APP", app.display());
    }
    let list: serde_json::Value =
        serde_json::from_str(&output(cmd("xcrun").args(["simctl", "list", "devices", "available", "--json"]))?)?;
    let udid = list["devices"]
        .as_object()
        .into_iter()
        .flatten()
        .filter(|(rt, _)| rt.contains("iOS"))
        .flat_map(|(_, ds)| ds.as_array().into_iter().flatten())
        .find(|d| d["name"] == name.as_str())
        .and_then(|d| d["udid"].as_str().map(String::from));
    let udid = match udid {
        Some(u) => u,
        None => create_simulator(&name)?,
    };
    let _ = try_output(cmd("xcrun").args(["simctl", "boot", &udid]));
    run(cmd("xcrun").args(["simctl", "bootstatus", &udid, "-b"]))?;
    let _ = try_output(cmd("xcrun").args(["simctl", "terminate", &udid, &id]));
    run(cmd("xcrun").args(["simctl", "install", &udid]).arg(&app))?;
    let launched = output(cmd("xcrun").args(["simctl", "launch", &udid, &id]))?;
    let pid: u32 = launched
        .rsplit(':')
        .next()
        .and_then(|p| p.trim().parse().ok())
        .with_context(|| format!("simctl launch: {launched}"))?;
    std::thread::sleep(Duration::from_secs(env_or("WAWONA_SMOKE_SETTLE_SECS", "10").parse()?));
    let _ = try_output(cmd("xcrun").args(["simctl", "io", &udid, "screenshot"]).arg(out.join("launch.png")));
    if !alive(pid) {
        let crash = try_output(
            cmd("xcrun")
                .args(["simctl", "spawn", &udid, "log", "show", "--last", "2m", "--style", "compact", "--predicate"])
                .arg(format!("process == \"Wawona\" OR eventMessage CONTAINS \"{id}\"")),
        );
        std::fs::write(out.join("log.txt"), crash.unwrap_or_default())?;
        bail!("{id} (pid {pid}) exited within the settle window");
    }
    eprintln!("PASS: simctl install + launch ({id} pid {pid} alive)");
    let _ = try_output(cmd("xcrun").args(["simctl", "terminate", &udid, &id]));
    summary("**PASS:** iOS simulator install + launch");
    Ok(())
}

/// A simulator of device type `name` on the newest available iOS runtime.
fn create_simulator(name: &str) -> Result<String> {
    let json = |what: &str| -> Result<serde_json::Value> {
        Ok(serde_json::from_str(&output(cmd("xcrun").args(["simctl", "list", what, "--json"]))?)?)
    };
    let types = json("devicetypes")?;
    let devtype = types["devicetypes"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|t| t["name"] == name)
        .and_then(|t| t["identifier"].as_str())
        .with_context(|| format!("no simulator device type named {name}"))?
        .to_string();
    let runtimes = json("runtimes")?;
    let runtime = runtimes["runtimes"]
        .as_array()
        .into_iter()
        .flatten()
        .rfind(|r| r["platform"] == "iOS" && r["isAvailable"] == true)
        .and_then(|r| r["identifier"].as_str())
        .context("no available iOS simulator runtime")?
        .to_string();
    eprintln!("creating simulator {name} ({runtime})");
    Ok(output(cmd("xcrun").args(["simctl", "create", name, &devtype, &runtime]))?.trim().to_string())
}

fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

fn which(name: &str) -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?).map(|d| d.join(name)).find(|p| is_executable(p))
}
