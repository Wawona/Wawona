//! The processes an Appium run needs around Wawona: the Appium server,
//! WebDriverAgentMac, the Colima guest and the waypipe clients it streams.
//! Each is started detached with a pidfile, and only recorded pids are
//! stopped.

use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};

use crate::util::*;

/// Matrix client id to the guest command (an apt or PATH name in Colima).
pub const GUESTS: [(&str, &str); 23] = [
    ("weston", "weston"),
    ("weston_terminal", "weston-terminal"),
    ("niri", "niri"),
    ("swaywm", "sway"),
    ("hyprland", "Hyprland"),
    ("weston_simple_shm", "weston-simple-shm"),
    ("weston-simple-shm", "weston-simple-shm"),
    ("foot", "foot"),
    ("ghostty_terminal", "ghostty"),
    ("konsole", "konsole"),
    ("firefox_wayland", "firefox"),
    ("thunar", "thunar"),
    ("dolphin", "dolphin"),
    ("mangowm", "mango"),
    ("cosmic_de", "cosmic-comp"),
    ("phosh_de", "phosh"),
    ("kde_plasma_de", "plasmashell"),
    ("kde_plasma_mobile_de", "plasmashell"),
    ("gnome_de", "gnome-shell"),
    // The lab's own clients, not in the matrix.
    ("weston-terminal", "weston-terminal"),
    ("weston-flower", "weston-flower"),
    ("weston-smoke", "weston-smoke"),
    ("nested-weston", "weston --backend=wayland --socket=nested-lab --width=900 --height=600"),
];

pub fn guest(client: &str) -> Option<&'static str> {
    GUESTS.iter().find(|(c, _)| *c == client).map(|(_, g)| *g)
}

/// The apt package and the command line for a guest command. Qt guests must
/// not fall back to xcb (there is no DISPLAY over waypipe); Firefox comes
/// from the deb, since the snap proxies WAYLAND_DISPLAY and cannot reach the
/// waypipe socket.
fn guest_recipe(target: &str) -> (&str, String) {
    let (pkg, line) = match target {
        "firefox" => ("firefox", "env MOZ_ENABLE_WAYLAND=1 QT_QPA_PLATFORM=wayland firefox"),
        "konsole" => ("konsole", "env QT_QPA_PLATFORM=wayland konsole"),
        "dolphin" => ("dolphin", "env QT_QPA_PLATFORM=wayland dolphin"),
        "mango" => ("mango", "env WLR_BACKENDS=wayland mango -c /home/lima.guest/.config/mango/config.toml"),
        // Ubuntu installs phosh under libexec with no PATH entry.
        "phosh" => ("phosh", "/usr/libexec/phosh"),
        "gnome-shell" => ("gnome-shell", "gnome-shell --wayland --nested"),
        "plasmashell" => ("plasma-workspace", "env QT_QPA_PLATFORM=wayland plasmashell"),
        "niri" => ("niri", "env NIRI_BACKEND=nested niri"),
        "Hyprland" => ("hyprland", "Hyprland"),
        "weston" => ("weston", "weston --backend=wayland --socket=appium-colima-weston --width=1024 --height=768"),
        "weston-terminal" | "weston-simple-shm" | "weston-flower" | "weston-smoke" => ("weston", target),
        t if t.starts_with("weston ") => ("weston", t),
        t => (t, t),
    };
    (pkg, line.to_string())
}

fn ssh_config() -> PathBuf {
    std::env::var("COLIMA_SSH_CONFIG").map(PathBuf::from).unwrap_or_else(|_| {
        let home = std::env::var("COLIMA_HOME").unwrap_or_else(|_| format!("{}/.colima", env_or("HOME", "")));
        Path::new(&home).join("ssh_config")
    })
}

/// The first concrete `Host` alias of Colima's generated SSH config
/// (`COLIMA_SSH_HOST` wins).
pub fn colima_host(config: &Path) -> Result<String> {
    if let Ok(h) = std::env::var("COLIMA_SSH_HOST") {
        if !h.is_empty() {
            return Ok(h);
        }
    }
    let text = read(config).with_context(|| "Colima SSH config missing; run `cargo xtask appium colima`")?;
    text.lines()
        .filter_map(|l| {
            let mut w = l.split_whitespace();
            w.next().filter(|k| k.eq_ignore_ascii_case("host"))?;
            w.find(|h| !h.contains(['*', '?', '!'])).map(String::from)
        })
        .next()
        .with_context(|| format!("no concrete Host alias in {}", config.display()))
}

fn ssh(config: &Path, host: &str) -> std::process::Command {
    let mut c = cmd("ssh");
    c.arg("-F").arg(config);
    c.args(["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", host]);
    c
}

/// Fail closed unless Colima runs and its guest answers SSH. With
/// `WAWONA_COLIMA_START=1` a stopped VM is started; with
/// `WAWONA_COLIMA_RECOVER=1` an unreachable one is force-restarted.
pub fn ensure_colima() -> Result<(PathBuf, String)> {
    if try_output(cmd("colima").arg("version")).is_none() {
        bail!("colima is not on PATH (brew install colima lima, or a nix profile)");
    }
    let start = || {
        let mut c = cmd("colima");
        c.arg("start");
        if let Ok(t) = std::env::var("WAWONA_COLIMA_VM_TYPE") {
            c.args(["--vm-type", &t]);
        }
        run(&mut c)
    };
    if !cmd("colima").arg("status").output()?.status.success() {
        if !env_flag("WAWONA_COLIMA_START") {
            bail!("colima is not running: `colima start` (or WAWONA_COLIMA_START=1)");
        }
        start()?;
    }
    let config = ssh_config();
    let refresh = || -> Result<String> {
        let text = output(cmd("colima").arg("ssh-config"))?;
        if text.is_empty() {
            bail!("colima ssh-config is empty");
        }
        write(&config, text + "\n")?;
        let host = colima_host(&config)?;
        let probe = ssh(&config, &host).args(["-o", "ConnectTimeout=8", "true"]).output()?;
        if !probe.status.success() {
            bail!("Colima SSH probe failed: {}", String::from_utf8_lossy(&probe.stderr).trim());
        }
        Ok(host)
    };
    let host = match refresh() {
        Ok(h) => h,
        Err(e) if env_flag("WAWONA_COLIMA_RECOVER") => {
            eprintln!("colima: {e:#}; force-restarting the VM");
            run(cmd("colima").args(["stop", "--force"]))?;
            start()?;
            refresh().context("Colima guest unreachable after recovery")?
        }
        Err(e) => {
            return Err(e.context("Colima SSH config or guest is unhealthy (WAWONA_COLIMA_RECOVER=1 restarts it)"))
        }
    };
    println!("colima ok ssh-config={} ssh-host={host}", config.display());
    Ok((config, host))
}

/// `WAWONA_WAYLAND_GUEST`: colima on macOS, nested on Linux. Catalog tests
/// never use Apple Containerization or host binaries.
fn guest_mode() -> Result<String> {
    let mode = env_or("WAWONA_WAYLAND_GUEST", if cfg!(target_os = "macos") { "colima" } else { "nested" });
    match mode.as_str() {
        "colima" | "nested" => Ok(mode),
        other => bail!("WAWONA_WAYLAND_GUEST={other} is not allowed for catalog tests (colima or nested)"),
    }
}

/// Launch a catalog client into the running compositor.
pub fn launch(client: &str) -> Result<()> {
    let rt = wawona_runtime();
    let display = env_or("WAYLAND_DISPLAY", "wayland-0");
    let sock = rt.join(&display);
    if !socket_accepts(&sock) {
        bail!("no Wayland socket at {} (start Wawona first)", sock.display());
    }
    let target = guest(client).with_context(|| format!("no Wayland guest mapping for {client}"))?;
    let art = super::artifacts();
    std::fs::create_dir_all(&art)?;
    if guest_mode()? == "nested" {
        let line = match client {
            "weston" => "weston --backend=wayland --socket=appium-nested-weston --width=1024 --height=768",
            "gnome_de" => "gnome-shell --wayland",
            _ => target,
        };
        let line = if client == "niri" { "env NIRI_BACKEND=nested niri".to_string() } else { line.to_string() };
        let mut c = cmd("bash");
        c.args(["-lc", &line]).env("XDG_RUNTIME_DIR", &rt).env("WAYLAND_DISPLAY", &display);
        let pid = detached(c, art.join(format!("nested-{client}.log")))?;
        append_pid(&art, pid)?;
        println!("nested pid={pid} client={client} cmd={line}");
        return Ok(());
    }
    let (config, host) = ensure_colima()?;
    let (pkg, line) = guest_recipe(target);
    let bin = line.split_whitespace().find(|w| *w != "env" && !w.contains('=')).unwrap_or(target).to_string();
    let path = "export PATH=\"$HOME/.nix-profile/bin:/home/lima.guest/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin:$PATH\"; \
                for p in \"$HOME/.nix-profile/etc/profile.d/nix.sh\" /home/lima.guest/.nix-profile/etc/profile.d/nix.sh; \
                do [ -f \"$p\" ] && . \"$p\"; done; ";
    let have = format!("{path}command -v {bin} >/dev/null || test -x {bin}");
    let apt = format!("{have} || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y {pkg}");
    let log = std::env::temp_dir().join(format!("wawona-colima-apt-{client}.log"));
    let out = ssh(&config, &host).arg(&apt).output()?;
    write(&log, [out.stdout, out.stderr].concat())?;
    if !out.status.success() || !ssh(&config, &host).arg(&have).status()?.success() {
        bail!("the Colima guest has no {bin} (package {pkg}); see {}", log.display());
    }
    // An absolute path keeps waypipe's remote argv independent of login PATH.
    let resolved = output(ssh(&config, &host).arg(format!("{path}command -v {bin}")))?;
    let resolved = resolved.lines().next().unwrap_or("").trim();
    let line = if resolved.starts_with('/') { line.replacen(&bin, resolved, 1) } else { line };
    waypipe(client, &line)
}

fn append_pid(art: &Path, pid: u32) -> Result<()> {
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(art.join("guests.pids"))?;
    writeln!(f, "{pid}")?;
    Ok(())
}

/// The tip app's waypipe (`WAWONA_WAYPIPE_BIN` wins); never an installed copy.
fn waypipe_bin() -> Result<PathBuf> {
    if let Ok(p) = std::env::var("WAWONA_WAYPIPE_BIN") {
        return Ok(PathBuf::from(p));
    }
    let tip = "/tmp/wawona-macos-tip";
    [
        std::env::var("WAWONA_APP_PATH").unwrap_or_default(),
        format!("{tip}/Wawona.app"),
        format!("{tip}/DerivedData/Build/Products/Debug/Wawona.app"),
    ]
    .iter()
    .filter(|a| !a.is_empty())
    .map(|a| Path::new(a).join("Contents/Resources/bin/waypipe"))
    .find(|p| p.is_file())
    .context("no waypipe in the tip app; set WAWONA_APP_PATH (`cargo xtask tip macos`)")
}

/// Stream one guest command over waypipe SSH into Wawona.
fn waypipe(name: &str, line: &str) -> Result<()> {
    let rt = wawona_runtime();
    let (config, host) = (ssh_config(), colima_host(&ssh_config())?);
    let art = root().join(".agent-device/test-artifacts");
    let mut c = cmd(waypipe_bin()?);
    c.args(["--no-gpu", "--remote-bin", &env_or("COLIMA_REMOTE_WAYPIPE", "/usr/bin/waypipe"), "ssh"]);
    c.args(["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-F"]).arg(&config);
    c.args(["-T", &host, "--"]).args(line.split_whitespace());
    c.env("XDG_RUNTIME_DIR", &rt).env("WAYLAND_DISPLAY", "wayland-0");
    let log = art.join(format!("waypipe-ssh-{name}.log"));
    let pid = detached(c, &log)?;
    append_pid(&art, pid)?;
    println!("started {name} pid={pid} -> {}", log.display());
    Ok(())
}

#[derive(clap::Args)]
pub struct LabArgs {
    /// Print the runtime socket and the guest's client binaries.
    #[arg(long)]
    status: bool,
    /// Stop the waypipe sessions this lab started.
    #[arg(long)]
    kill: bool,
    /// A client name and optional command (default: the lab's six clients).
    client: Vec<String>,
}

/// Colima guests over waypipe SSH into the running Wawona.
pub fn lab(a: LabArgs) -> Result<()> {
    let art = root().join(".agent-device/test-artifacts");
    if a.kill {
        for pid in read(art.join("guests.pids")).unwrap_or_default().lines().filter_map(|l| l.parse::<u32>().ok()) {
            if alive(pid) {
                // SAFETY: pids in guests.pids were started by this tool.
                unsafe { libc::kill(pid as i32, libc::SIGTERM) };
            }
        }
        let _ = std::fs::remove_file(art.join("guests.pids"));
        println!("stopped the recorded waypipe sessions");
        return Ok(());
    }
    let rt = wawona_runtime();
    if a.status {
        let config = ssh_config();
        println!("runtime={} ssh_config={} waypipe={:?}", rt.display(), config.display(), waypipe_bin().ok());
        println!("wayland-0 accepting: {}", socket_accepts(rt.join("wayland-0")));
        let host = colima_host(&config)?;
        run(ssh(&config, &host).arg("command -v waypipe foot weston weston-terminal"))?;
        return Ok(());
    }
    if !socket_accepts(rt.join("wayland-0")) {
        bail!("no compositor at {}/wayland-0 (start Wawona first)", rt.display());
    }
    if let [name, rest @ ..] = a.client.as_slice() {
        let line = if rest.is_empty() { guest_recipe(guest(name).unwrap_or(name)).1 } else { rest.join(" ") };
        waypipe(name, &line)?;
    } else {
        for name in ["foot", "weston-terminal", "weston-simple-shm", "weston-flower", "weston-smoke", "nested-weston"] {
            waypipe(name, &guest_recipe(guest(name).unwrap()).1)?;
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }
    let _ = std::fs::File::create(rt.join("show-session-surface"));
    Ok(())
}

/// A local Appium server on :4723, started once and left running. Testing
/// DYLD paths must not reach Node: they belong to WebDriverAgent only.
pub fn ensure_server() -> Result<()> {
    let host = env_or("WAWONA_APPIUM_HOST", "127.0.0.1");
    let port = env_or("WAWONA_APPIUM_PORT", "4723");
    let url = format!("http://{host}:{port}/status");
    if http_ok(&url) {
        println!("appium already up on {host}:{port}");
        return Ok(());
    }
    let pid_file = env_or("WAWONA_APPIUM_PIDFILE", "/tmp/wawona-appium.pid");
    stop_recorded(&pid_file);
    let home = env_or("HOME", "");
    let mut c = cmd("appium");
    c.args(["--address", &host, "--port", &port, "--base-path", "/", "--log-level", "info"]);
    c.env("APPIUM_HOME", env_or("APPIUM_HOME", &format!("{home}/.local/share/appium-cli")));
    c.env("PATH", format!("{home}/.local/bin:{}", env_or("PATH", "")));
    for k in ["DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH", "DYLD_FALLBACK_FRAMEWORK_PATH", "DYLD_FALLBACK_LIBRARY_PATH"]
    {
        c.env_remove(k);
    }
    let log = env_or("WAWONA_APPIUM_LOG", "/tmp/wawona-appium-server.log");
    let pid = detached(c, &log)?;
    write(&pid_file, pid.to_string())?;
    if !wait_for(40, 1000, || http_ok(&url)) {
        bail!("Appium did not become ready (log {log})");
    }
    println!("appium ready pid={pid} url=http://{host}:{port}");
    Ok(())
}

/// WebDriverAgentMac on :10100 for Mac2. Xcode's Testing frameworks go on
/// the runner's DYLD paths, else it aborts loading lib_TestingInterop.
pub fn ensure_wda() -> Result<()> {
    let host = env_or("WAWONA_MAC2_WDA_HOST", "127.0.0.1");
    let port = env_or("WAWONA_MAC2_WDA_PORT", "10100");
    let url = format!("http://{host}:{port}/status");
    let pid_file = env_or("WAWONA_MAC2_WDA_PIDFILE", "/tmp/wawona-wda-mac.pid");
    if !env_flag("WAWONA_MAC2_FORCE_RESTART") && http_ok(&url) {
        println!("wda-mac already up on {url}");
        return Ok(());
    }
    stop_recorded(&pid_file);
    let app = wda_app()?;
    let dev = PathBuf::from(output(cmd("xcode-select").arg("-p"))?);
    let mac_fw = dev.join("Platforms/MacOSX.platform/Developer/Library/Frameworks");
    let mac_lib = dev.join("Platforms/MacOSX.platform/Developer/usr/lib");
    let shared = dev.parent().context("Developer dir has no parent")?.join("SharedFrameworks");
    let interop = app.join("Contents/Frameworks/lib_TestingInterop.dylib");
    if !interop.exists() && mac_lib.join("lib_TestingInterop.dylib").exists() {
        std::fs::create_dir_all(interop.parent().unwrap())?;
        std::fs::copy(mac_lib.join("lib_TestingInterop.dylib"), &interop)?;
        run(cmd("codesign").args(["--force", "--sign", "-"]).arg(&interop))?;
    }
    let join = |paths: &[&Path], k: &str| {
        let mut v: Vec<String> = paths.iter().map(|p| p.display().to_string()).collect();
        v.extend(std::env::var(k).ok().filter(|s| !s.is_empty()));
        v.join(":")
    };
    let mut c = cmd(app.join("Contents/MacOS/WebDriverAgentRunner-Runner"));
    c.env("DYLD_FRAMEWORK_PATH", join(&[&mac_fw], "DYLD_FRAMEWORK_PATH"))
        .env("DYLD_LIBRARY_PATH", join(&[&mac_lib], "DYLD_LIBRARY_PATH"))
        .env("DYLD_FALLBACK_FRAMEWORK_PATH", join(&[&shared], "DYLD_FALLBACK_FRAMEWORK_PATH"))
        .env("DYLD_FALLBACK_LIBRARY_PATH", join(&[&shared, &mac_lib], "DYLD_FALLBACK_LIBRARY_PATH"))
        .env("USE_PORT", &port)
        .env("USE_HOST", &host);
    let log = env_or("WAWONA_MAC2_WDA_LOG", "/tmp/wawona-wda-mac.log");
    let pid = detached(c, &log)?;
    write(&pid_file, pid.to_string())?;
    if !wait_for(40, 1000, || http_ok(&url)) {
        bail!("WebDriverAgentMac did not become ready (log {log})");
    }
    println!("wda-mac ready pid={pid} url={url} app={}", app.display());
    Ok(())
}

/// A built WebDriverAgentRunner-Runner.app (`WAWONA_MAC2_WDA_APP` wins),
/// building the Mac2 driver's project into /tmp/wda-mac-dd when none exists.
fn wda_app() -> Result<PathBuf> {
    let runner = |a: &Path| a.join("Contents/MacOS/WebDriverAgentRunner-Runner").is_file();
    if let Ok(a) = std::env::var("WAWONA_MAC2_WDA_APP") {
        if runner(Path::new(&a)) {
            return Ok(a.into());
        }
    }
    let home = env_or("HOME", "");
    let dd = Path::new("/tmp/wda-mac-dd");
    let built = dd.join("Build/Products/Debug/WebDriverAgentRunner-Runner.app");
    let drivers = [
        format!("{home}/.appium/node_modules/appium-mac2-driver"),
        format!("{home}/.local/share/appium-cli/node_modules/appium-mac2-driver"),
    ];
    let mut apps = vec![built.clone()];
    apps.extend(
        drivers
            .iter()
            .map(|d| Path::new(d).join("WebDriverAgentMac/build/Build/Products/Debug/WebDriverAgentRunner-Runner.app")),
    );
    if let Some(a) = apps.into_iter().find(|a| runner(a)) {
        return Ok(a);
    }
    let project = drivers
        .iter()
        .map(|d| Path::new(d).join("WebDriverAgentMac/WebDriverAgentMac.xcodeproj"))
        .find(|p| p.is_dir())
        .context("no WebDriverAgentMac project: `appium driver install mac2`")?;
    run(cmd("xcodebuild")
        .arg("-project")
        .arg(&project)
        .args(["-scheme", "WebDriverAgentRunner", "-configuration", "Debug", "-derivedDataPath"])
        .arg(dd)
        .args(["CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "build"]))?;
    runner(&built).then_some(built).context("WebDriverAgentRunner did not build")
}

/// The artifact root: a non-hidden `test-artifacts/appium` on GitHub Actions
/// (upload-artifact skips hidden paths), else [`super::artifacts`].
pub fn prepare_artifacts() -> Result<()> {
    let art = match std::env::var("GITHUB_ACTIONS") {
        Ok(_) => std::env::var("GITHUB_WORKSPACE")
            .map(PathBuf::from)
            .unwrap_or_else(|_| root())
            .join("test-artifacts/appium"),
        Err(_) => super::artifacts(),
    };
    std::fs::create_dir_all(art.join("catalog-gallery"))?;
    if let Ok(env) = std::env::var("GITHUB_ENV") {
        use std::io::Write;
        writeln!(
            std::fs::OpenOptions::new().append(true).create(true).open(env)?,
            "WAWONA_APPIUM_ARTIFACTS={}",
            art.display()
        )?;
    }
    println!("{}", export_line("WAWONA_APPIUM_ARTIFACTS", &art.display().to_string()));
    Ok(())
}

/// Every catalog client (or `only`) into a fresh tip Wawona, a screenshot
/// each, then the gallery check. macOS: Colima guests, the tip app and Mac2.
pub fn catalog(only: &[String]) -> Result<()> {
    let set = |k: &str, v: &str| {
        if std::env::var(k).is_err() {
            std::env::set_var(k, v);
        }
    };
    set("WAWONA_APPIUM_PLATFORM", "macos");
    set("WAWONA_APPIUM_SERVER", "http://127.0.0.1:4723");
    // Dark clients (weston-terminal) can take over four seconds to attach.
    set("WAWONA_CATALOG_SETTLE_SEC", "8");
    // A fresh session per client, so one poisoned session cannot cascade.
    set("WAWONA_APPIUM_DRIVER_SCOPE", "function");
    std::env::remove_var("WAWONA_APPIUM_DRY");
    let me = std::env::current_exe()?;
    if cfg!(target_os = "macos") {
        std::env::set_var("WAWONA_WAYLAND_GUEST", "colima");
        ensure_colima()?;
    } else {
        set("WAWONA_WAYLAND_GUEST", "nested");
    }
    ensure_server()?;
    if cfg!(target_os = "macos") && super::platform() == "macos" {
        for line in output(cmd(&me).args(["tip", "macos"]))?.lines() {
            if let Some((k, v)) = line.strip_prefix("export ").and_then(|l| l.split_once('=')) {
                std::env::set_var(k, v.trim_matches('\''));
            }
        }
        std::env::remove_var("WAWONA_MAC2_FORCE_RESTART");
        ensure_wda()?;
        set("WAWONA_MAC2_WDA_URL", &format!("http://127.0.0.1:{}", env_or("WAWONA_MAC2_WDA_PORT", "10100")));
        // manageApp keeps the bundleId (needed for wwn.* AX); skipAppKill and
        // noReset keep the tip compositor just launched.
        set("WAWONA_MAC2_MANAGE_APP", "1");
        set("WAWONA_APPIUM_NO_RESET", "1");
        set("WAWONA_MAC2_SKIP_APP_KILL", "1");
        std::thread::sleep(std::time::Duration::from_secs(env_or("WAWONA_TIP_SETTLE_SEC", "2").parse().unwrap_or(2)));
    }
    let rt = wawona_runtime();
    if std::env::var("FONTCONFIG_FILE").is_err() && rt.join("fonts.conf").is_file() {
        std::env::set_var("FONTCONFIG_FILE", rt.join("fonts.conf"));
    }
    if !socket_accepts(rt.join("wayland-0")) {
        bail!("no compositor at {}/wayland-0", rt.display());
    }
    let only = only.join(",");
    let mut suite = cmd(&me);
    suite.args(["appium", "run", "--group", "catalog"]);
    let mut gallery = cmd(&me);
    gallery.args(["appium", "gallery"]);
    if !only.is_empty() {
        suite.args(["--only", &only]);
        gallery.args(["--only", &only]);
    }
    run(&mut suite)?;
    run(&mut gallery)?;
    println!("Gallery: {}/catalog-gallery/index.html", super::artifacts().display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host(config: &str) -> String {
        let dir = std::env::temp_dir().join(format!("wwn-colima-{}-{}", std::process::id(), config.len()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("ssh_config");
        std::fs::write(&file, config).unwrap();
        colima_host(&file).unwrap()
    }

    #[test]
    fn colima_host_reads_the_profile_alias() {
        std::env::remove_var("COLIMA_SSH_HOST");
        assert_eq!(host("Host colima-wawona-123-1-macos\n  HostName 127.0.0.1\n"), "colima-wawona-123-1-macos");
        assert_eq!(host("Host *\n  ServerAliveInterval 60\nHost colima-runner\n"), "colima-runner");
    }

    #[test]
    fn guest_recipes() {
        assert_eq!(guest("swaywm"), Some("sway"));
        assert_eq!(guest("__no_such_client__"), None);
        assert_eq!(guest_recipe("plasmashell").0, "plasma-workspace");
        assert_eq!(guest_recipe("weston-terminal"), ("weston", "weston-terminal".into()));
    }
}
