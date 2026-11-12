//! `cargo xtask install`, `uninstall` and `cli`: put a Release macOS build at
//! /Applications/Wawona.app with its launch agents and Mode B helper, and the
//! host-PATH wrappers for every bundled executable.
//!
//! The wrappers and the env.sh they source stay shell (`xtask/assets/`):
//! the user's shell runs them. They point at the installed app, not at a
//! build directory or a GC-able store path.

use crate::util::*;
use anyhow::{bail, Context, Result};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::Duration;

const ENV_TEMPLATE: &str = include_str!("../assets/cli-env.sh");
const WRAPPER_TEMPLATE: &str = include_str!("../assets/cli-wrapper.sh");
const MARKER: &str = "# Wawona CLI wrapper. Do not edit.";
// Existing installs carry these lines in their shell files; strip matches them.
const PATH_BEGIN: &str = "# BEGIN Wawona CLI bins (nix run .#install)";
const PATH_END: &str = "# END Wawona CLI bins";
const SYSTEM_RC: &str = "/etc/zshenv.local";
const APP_DST: &str = "/Applications/Wawona.app";
const BUNDLE_ID: &str = "com.aspauldingcode.Wawona";
const COMPOSITOR: &str = "com.aspauldingcode.wawona.compositorhost";
const MENUBAR: &str = "com.aspauldingcode.wawona.menubar";
const APPLAUNCH: &str = "com.aspauldingcode.wawona.applaunch";
const MODEB_LOGIN: &str = "com.aspauldingcode.wawona.modeb-login";
const MODEB_HELPER: &str = "/Library/Application Support/Wawona/run-modeb.sh";

#[derive(clap::Subcommand)]
pub enum Cli {
    /// Write a wrapper on PATH for each executable bundled in `app`.
    Register {
        app: PathBuf,
        /// Only the user's shell files: skip /etc/zshenv.local and its administrator prompt.
        #[arg(long)]
        user_only: bool,
    },
    /// Remove the wrappers and the PATH hooks.
    Unregister,
    /// Root step: append the PATH block to a file once.
    #[command(hide = true)]
    Append { file: PathBuf, block: PathBuf },
    /// Root step: remove the PATH block from a file.
    #[command(hide = true)]
    Strip { file: PathBuf },
}

fn home() -> PathBuf {
    PathBuf::from(env_or("HOME", "/"))
}

fn cli_dir() -> PathBuf {
    home().join("Library/Wawona/cli")
}

fn env_sh() -> PathBuf {
    cli_dir().join("env.sh")
}

fn manifest() -> PathBuf {
    home().join("Library/Wawona/cli-bins.list")
}

fn local_bin() -> PathBuf {
    home().join(".local/bin")
}

fn executable(p: &Path) -> bool {
    p.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

fn writable(p: &Path) -> bool {
    let Ok(c) = std::ffi::CString::new(p.as_os_str().as_encoded_bytes()) else { return false };
    // SAFETY: access(2) only reads the path.
    unsafe { libc::access(c.as_ptr(), libc::W_OK) == 0 }
}

fn write_mode(p: &Path, body: &str, mode: u32) -> Result<()> {
    std::fs::write(p, body).with_context(|| p.display().to_string())?;
    std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode))?;
    Ok(())
}

pub fn cli(c: Cli) -> Result<()> {
    match c {
        Cli::Register { app, user_only } => register(&app, !user_only),
        Cli::Unregister => {
            unregister();
            println!("Removed Wawona CLI wrappers from PATH.");
            Ok(())
        }
        Cli::Append { file, block } => {
            if !std::fs::read_to_string(&file).unwrap_or_default().contains(PATH_BEGIN) {
                let mut body = std::fs::read_to_string(&file).unwrap_or_default();
                body += &std::fs::read_to_string(block)?;
                write_mode(&file, &body, 0o644)?;
            }
            Ok(())
        }
        Cli::Strip { file } => strip_block(&file),
    }
}

/// Names that get no wrapper: the app, hidden or library files, the Mode B
/// TTY daemons, and anything that would shadow Apple's /bin or /usr/bin.
fn skip(name: &str) -> bool {
    matches!(name, "" | "Wawona" | "Wawona.debug" | ".foot-wrapped")
        || name.starts_with('.')
        || name.ends_with(".dylib")
        || name.ends_with(".so")
        || matches!(name, "igettyd" | "igetty" | "modeb-ttyd" | "modeb-tty" | "modeb-getty")
        || executable(&Path::new("/bin").join(name))
        || executable(&Path::new("/usr/bin").join(name))
}

fn resolve(app: &Path, name: &str) -> Option<PathBuf> {
    [app.join("Contents/Resources/bin").join(name), app.join("Contents/MacOS").join(name)]
        .into_iter()
        .find(|p| executable(p))
}

fn dest_dirs() -> Vec<PathBuf> {
    let mut v = vec![local_bin()];
    let system = Path::new("/usr/local/bin");
    if system.is_dir() && writable(system) {
        v.push(system.into());
    }
    v
}

fn wrapper(app: &Path, name: &str) -> String {
    WRAPPER_TEMPLATE
        .replace("@MARKER@", MARKER)
        .replace("@APP@", &app.display().to_string())
        .replace("@NAME@", name)
        .replace("@ENV_SH@", &env_sh().display().to_string())
}

fn ours(p: &Path) -> bool {
    p.is_file() && std::fs::read_to_string(p).is_ok_and(|s| s.contains(MARKER))
}

fn path_block() -> String {
    format!(
        "\n{PATH_BEGIN}\n# nix-darwin /etc/zshenv sources this for every zsh, login or not.\n\
         if [ -d \"$HOME/.local/bin\" ]; then\n  PATH=\"$HOME/.local/bin:$PATH\"\n  export PATH\nfi\n{PATH_END}\n"
    )
}

fn strip_block(file: &Path) -> Result<()> {
    let Ok(body) = std::fs::read_to_string(file) else { return Ok(()) };
    if !body.contains(PATH_BEGIN) {
        return Ok(());
    }
    let mut out = String::new();
    let mut skipping = false;
    for line in body.lines() {
        match line {
            PATH_BEGIN => skipping = true,
            PATH_END => skipping = false,
            _ if !skipping => {
                out += line;
                out.push('\n');
            }
            _ => {}
        }
    }
    if out.is_empty() && file == Path::new(SYSTEM_RC) {
        std::fs::remove_file(file)?;
    } else {
        std::fs::write(file, out)?;
    }
    Ok(())
}

/// Runs `args` as root: directly when root, else `sudo -n`, else the
/// administrator prompt.
fn as_root(args: &[String]) -> bool {
    // SAFETY: getuid cannot fail.
    if unsafe { libc::getuid() } == 0 {
        return try_output(cmd(&args[0]).args(&args[1..])).is_some();
    }
    if try_output(cmd("sudo").arg("-n").args(args)).is_some() {
        return true;
    }
    let quoted: Vec<String> = args.iter().map(|a| format!("'{}'", a.replace('\'', r"'\''"))).collect();
    let script = format!("do shell script \"{}\" with administrator privileges", quoted.join(" ").replace('"', "\\\""));
    try_output(cmd("/usr/bin/osascript").args(["-e", &script])).is_some()
}

fn self_args(rest: &[&str]) -> Result<Vec<String>> {
    let mut v = vec![std::env::current_exe()?.display().to_string()];
    v.extend(rest.iter().map(|s| s.to_string()));
    Ok(v)
}

fn ensure_path(system: bool) -> Result<()> {
    for rc in [".zprofile", ".zshrc", ".bash_profile"].map(|r| home().join(r)) {
        let body = std::fs::read_to_string(&rc).ok();
        if body.as_deref().is_some_and(|b| b.contains(PATH_BEGIN)) {
            continue;
        }
        if rc.exists() && !writable(&rc) {
            eprintln!("Note: {} is not writable (home-manager).", rc.display());
            continue;
        }
        if rc.is_file() || rc.ends_with(".zprofile") {
            let body = body.unwrap_or_default() + &path_block();
            if std::fs::write(&rc, body).is_err() {
                eprintln!("Note: could not append the PATH snippet to {}", rc.display());
            }
        }
    }
    if !system {
        return Ok(());
    }
    if std::fs::read_to_string(SYSTEM_RC).is_ok_and(|b| b.contains(PATH_BEGIN)) {
        println!("PATH hook already present: {SYSTEM_RC}");
        return Ok(());
    }
    std::fs::create_dir_all(cli_dir())?;
    let block = cli_dir().join("path-block.sh");
    std::fs::write(&block, path_block())?;
    if as_root(&self_args(&["cli", "append", SYSTEM_RC, &block.display().to_string()])?) {
        println!("PATH hook installed for all zsh: {SYSTEM_RC}");
    } else {
        eprintln!("Note: could not write {SYSTEM_RC} (needs administrator once).");
        eprintln!("  Cursor and nested zsh are not login shells, so ~/.zprofile is skipped.");
        eprintln!("  This shell: export PATH=\"$HOME/.local/bin:$PATH\"");
        eprintln!("  Or add home.sessionPath = [ \"$HOME/.local/bin\" ]; and rebuild.");
    }
    Ok(())
}

fn clear_wrappers() {
    for p in std::fs::read_to_string(manifest()).unwrap_or_default().lines().filter(|l| !l.is_empty()) {
        if ours(Path::new(p)) {
            let _ = std::fs::remove_file(p);
        }
    }
    for dir in [local_bin(), PathBuf::from("/usr/local/bin")] {
        for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
            if ours(&e.path()) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    let _ = std::fs::remove_file(manifest());
}

fn unregister() {
    clear_wrappers();
    if std::fs::read_to_string(SYSTEM_RC).is_ok_and(|b| b.contains(PATH_BEGIN)) {
        if let Ok(a) = self_args(&["cli", "strip", SYSTEM_RC]) {
            as_root(&a);
        }
    }
    for rc in [".zprofile", ".zshrc", ".bash_profile"].map(|r| home().join(r)) {
        if rc.is_file() && writable(&rc) {
            let _ = strip_block(&rc);
        }
    }
    let _ = std::fs::remove_dir_all(cli_dir());
}

fn register(app: &Path, system: bool) -> Result<()> {
    if !app.is_dir() {
        bail!("Wawona.app is missing at {}", app.display());
    }
    let app = &std::fs::canonicalize(app)?;
    clear_wrappers();
    std::fs::create_dir_all(cli_dir())?;
    write_mode(&env_sh(), &ENV_TEMPLATE.replace("@APP@", &app.display().to_string()), 0o644)?;
    std::fs::create_dir_all(local_bin())?;
    let mut listed = Vec::new();
    let mut names: Vec<String> = Vec::new();
    for dir in ["Contents/Resources/bin", "Contents/MacOS"] {
        let mut entries: Vec<String> = std::fs::read_dir(app.join(dir))
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        entries.sort();
        for name in entries {
            if skip(&name) || names.contains(&name) || resolve(app, &name).is_none() {
                continue;
            }
            for d in dest_dirs() {
                std::fs::create_dir_all(&d)?;
                write_mode(&d.join(&name), &wrapper(app, &name), 0o755)?;
                listed.push(d.join(&name));
            }
            names.push(name);
        }
    }
    // `wawona` runs the app binary itself.
    if executable(&app.join("Contents/MacOS/Wawona")) {
        for d in dest_dirs() {
            let dest = d.join("wawona");
            if !dest.exists() || ours(&dest) {
                write_mode(&dest, &wrapper(app, "Wawona"), 0o755)?;
                listed.push(dest);
            }
        }
        names.push("wawona".into());
    }
    let body: String = listed.iter().map(|p| format!("{}\n", p.display())).collect();
    std::fs::write(manifest(), body)?;
    ensure_path(system)?;
    println!("Registered {} Wawona CLI tools in {}", names.len(), local_bin().display());
    println!("  examples: weston-terminal niri foot kmscube waypipe");
    println!("  skipped Apple-shadowing names (ssh, zsh, vi, ...): use the bundle bin/");
    println!("Already-open shells: export PATH=\"$HOME/.local/bin:$PATH\"");
    Ok(())
}

struct Agents {
    domain: String,
    dir: PathBuf,
    runtime: PathBuf,
}

impl Agents {
    fn new() -> Agents {
        Agents {
            domain: format!("gui/{}", uid()),
            dir: home().join("Library/LaunchAgents"),
            runtime: PathBuf::from(format!("/tmp/wawona-{}", uid())),
        }
    }

    fn loaded(&self, label: &str) -> bool {
        try_output(cmd("launchctl").args(["print", &format!("{}/{label}", self.domain)])).is_some()
    }

    fn unload(&self, label: &str, remove_plist: bool) {
        let _ = try_output(cmd("launchctl").args(["bootout", &format!("{}/{label}", self.domain)]));
        let _ = try_output(cmd("launchctl").args(["remove", label]));
        if remove_plist {
            let _ = std::fs::remove_file(self.dir.join(format!("{label}.plist")));
        }
        wait_for(5, 250, || !self.loaded(label));
    }

    fn write(&self, label: &str, exec: &Path, mode: &str, log: &str) -> Result<()> {
        use plist::{Dictionary, Value};
        let mut env = Dictionary::new();
        env.insert("PATH".into(), "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin".into());
        env.insert("XDG_RUNTIME_DIR".into(), self.runtime.display().to_string().into());
        env.insert("WAYLAND_DISPLAY".into(), "wayland-0".into());
        env.insert("WAWONA_SKIP_LAUNCH_AGENT_BOOTSTRAP".into(), "1".into());
        let mut d = Dictionary::new();
        d.insert("Label".into(), label.into());
        d.insert("ProgramArguments".into(), Value::Array(vec![exec.display().to_string().into(), mode.into()]));
        d.insert("RunAtLoad".into(), true.into());
        d.insert("KeepAlive".into(), true.into());
        d.insert("ThrottleInterval".into(), 5.into());
        d.insert("StandardOutPath".into(), format!("/tmp/{log}-{}.log", uid()).into());
        d.insert("StandardErrorPath".into(), format!("/tmp/{log}-{}.error.log", uid()).into());
        d.insert("EnvironmentVariables".into(), Value::Dictionary(env));
        Value::Dictionary(d).to_file_xml(self.dir.join(format!("{label}.plist")))?;
        Ok(())
    }

    /// Bootstrap fresh: kickstart on a loaded job would keep its old program path.
    fn load(&self, label: &str) -> Result<()> {
        self.unload(label, false);
        let plist = self.dir.join(format!("{label}.plist")).display().to_string();
        // launchd returns EIO for a few hundred ms after a bootout.
        if wait_for(5, 500, || try_output(cmd("launchctl").args(["bootstrap", &self.domain, &plist])).is_some()) {
            let _ = try_output(cmd("launchctl").args(["kickstart", "-k", &format!("{}/{label}", self.domain)]));
            return Ok(());
        }
        run(cmd("launchctl").args(["bootstrap", &self.domain, &plist]))
    }

    fn verify(&self, label: &str, exec: &Path) -> Result<()> {
        let mut last = String::new();
        let ok = wait_for(5, 250, || {
            last =
                try_output(cmd("launchctl").args(["print", &format!("{}/{label}", self.domain)])).unwrap_or_default();
            let field = |k: &str| last.lines().find_map(|l| l.trim().strip_prefix(k).map(str::to_string));
            let pid = field("pid = ").and_then(|p| p.parse::<u32>().ok());
            field("program = ").as_deref() == Some(&exec.display().to_string()) && pid.is_some_and(alive)
        });
        if !ok {
            bail!("{label} is not running this build (want {}):\n{last}", exec.display());
        }
        println!("  {label} running");
        Ok(())
    }

    fn stop_runtime(&self) {
        println!("Stopping running Wawona instances for a clean reinstall...");
        self.unload(COMPOSITOR, false);
        self.unload(MENUBAR, false);
        self.unload(APPLAUNCH, true);
        // A standard quit Apple event, so the app can save state first.
        let quit = format!("tell application id \"{BUNDLE_ID}\" to quit");
        if try_output(cmd("/usr/bin/osascript").args(["-e", &quit])).is_some() {
            std::thread::sleep(Duration::from_secs(1));
        }
        kill_wawona();
        for lock in ["compositor-host.lock", "menubar.lock", "instance.lock"] {
            let _ = std::fs::remove_file(self.runtime.join(lock));
        }
    }
}

/// TERM, then KILL, every installed or built Wawona process: a stale flock
/// would make the new compositor host exit as "already running".
fn kill_wawona() {
    let pids = || -> Vec<i32> {
        try_output(cmd("ps").args(["-axo", "pid=,args="]))
            .unwrap_or_default()
            .lines()
            .filter(|l| l.contains("/Contents/MacOS/Wawona"))
            .filter_map(|l| l.split_whitespace().next()?.parse().ok())
            .collect()
    };
    for (signal, settle) in [(libc::SIGTERM, 400), (libc::SIGKILL, 0)] {
        for pid in pids() {
            // SAFETY: kill(2) on a pid read just now.
            unsafe { libc::kill(pid, signal) };
        }
        std::thread::sleep(Duration::from_millis(settle));
    }
}

fn lsregister(app_dst: &Path) {
    let ls = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
    if !Path::new(ls).exists() {
        return;
    }
    // Launch Services must not resolve `open -a Wawona` to a stale copy whose
    // libraries are gone (a vanished volume or a collected store path).
    let found = try_output(cmd("/usr/bin/mdfind").arg(format!("kMDItemCFBundleIdentifier == \"{BUNDLE_ID}\"")))
        .unwrap_or_default();
    let store: Vec<PathBuf> = std::fs::read_dir("/nix/store")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().ends_with("-wawona-macos"))
        .map(|e| e.path().join("Applications/Wawona.app"))
        .collect();
    for p in found.lines().map(PathBuf::from).chain(store) {
        if p != app_dst && executable(&p.join("Contents/MacOS/Wawona")) {
            println!("Unregistering stale Launch Services copy: {}", p.display());
            let _ = try_output(cmd(ls).arg("-u").arg(&p));
        }
    }
    let _ = try_output(cmd(ls).arg("-f").arg(app_dst));
}

pub fn install(app: Option<PathBuf>) -> Result<()> {
    let src = match app {
        Some(a) => a,
        None => crate::product::target("macos")?.app(false, true),
    };
    let src = std::fs::canonicalize(&src).with_context(|| format!("no Wawona.app at {}", src.display()))?;
    let dst = Path::new(APP_DST);
    let exec = dst.join("Contents/MacOS/Wawona");
    let dylib = dst.join("Contents/Library/Wawona/iland/libwayland-mac.dylib");
    if !executable(&src.join("Contents/MacOS/Wawona")) {
        bail!("no Wawona executable in {} (cargo xtask build macos --release)", src.display());
    }
    if !src.join("Contents/Library/Wawona/iland/libwayland-mac.dylib").is_file() {
        bail!("{} has no Mode B dylib; macOS Desktop Replacement needs libwayland-mac.dylib", src.display());
    }
    let agents = Agents::new();
    std::fs::create_dir_all(&agents.dir)?;
    std::fs::create_dir_all(&agents.runtime)?;
    let _ = std::fs::set_permissions(&agents.runtime, std::fs::Permissions::from_mode(0o700));

    agents.stop_runtime();
    println!("Installing Wawona.app to {APP_DST}");
    let _ = std::fs::remove_dir_all(dst);
    run(cmd("/usr/bin/ditto").arg(&src).arg(dst))?;
    let _ = try_output(cmd("chmod").args(["-R", "u+w", APP_DST]));
    if !executable(&exec) {
        bail!("the Wawona executable is missing after the copy to {APP_DST}");
    }
    // Global Settings are in-app only; drop PrefPanes older installs left.
    let _ = std::fs::remove_dir_all(home().join("Library/PreferencePanes/Wawona.prefPane"));
    let _ = std::fs::remove_dir_all("/Library/PreferencePanes/Wawona.prefPane");
    let _ = std::fs::remove_dir_all(dst.join("Contents/Resources/PreferencePanes"));
    lsregister(dst);

    // Classic Take Over needs the helper and dylib of this build (Path B).
    println!("Installing the Desktop Replacement helper (iowatchdog-then-unload).");
    println!("Administrator authorization may be required once.");
    run(cmd(&exec).arg("--mode-b-stage")).context("installing the Desktop Replacement helper")?;
    let helper = std::fs::read_to_string(MODEB_HELPER).unwrap_or_default();
    let want = [
        APP_DST,
        "WWN_MODEB_INSERT=compositor-only",
        "WWN_MODEB_LOCK=helper-argv-only",
        "WWN_MODEB_WD=iowatchdog-then-unload",
        "WWN_MODEB_GATE=live-fb-before-ws-unload",
    ];
    if let Some(missing) = want.iter().find(|w| !helper.contains(*w)) {
        bail!("{MODEB_HELPER} does not match this install (missing {missing})");
    }
    println!("Mode B helper installed: {MODEB_HELPER}");

    // --mode-b-stage may have started the new binary; stop it so the agents bind to this install.
    agents.stop_runtime();
    agents.write(COMPOSITOR, &exec, "--compositor-host", "wawona-compositor")?;
    agents.write(MENUBAR, &exec, "--menubar", "wawona-menubar")?;
    agents.load(COMPOSITOR)?;
    agents.load(MENUBAR)?;
    println!("Wawona launch agents installed and running {}:", exec.display());
    agents.verify(COMPOSITOR, &exec)?;
    agents.verify(MENUBAR, &exec)?;
    println!("Mode B dylib: {}", dylib.display());
    println!("Registering bundled software on PATH...");
    register(dst, true)
}

pub fn uninstall(privileged: bool) -> Result<()> {
    if privileged {
        return uninstall_root();
    }
    let agents = Agents::new();
    for label in [COMPOSITOR, MENUBAR, APPLAUNCH, MODEB_LOGIN] {
        agents.unload(label, true);
    }
    kill_wawona();
    unregister();
    let _ = std::fs::remove_dir_all(home().join("Library/PreferencePanes/Wawona.prefPane"));
    if executable(Path::new(MODEB_HELPER)) {
        let _ = try_output(cmd("/usr/bin/sudo").args(["-n", MODEB_HELPER, "--restore-aqua"]));
    }
    let dst = Path::new(APP_DST);
    let mut need_admin = dst.exists() && std::fs::remove_dir_all(dst).is_err();
    need_admin |= [
        "/Library/Application Support/Wawona",
        "/etc/sudoers.d/wawona-modeb",
        "/Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist",
    ]
    .iter()
    .any(|p| Path::new(p).exists());
    if need_admin {
        println!("Requesting administrator privileges to finish the uninstall...");
        if !as_root(&self_args(&["uninstall", "--privileged"])?) {
            bail!("administrator authorization is required to remove a root-owned Wawona.app and the Mode B files");
        }
    }
    if dst.exists() {
        bail!("{APP_DST} is still present");
    }
    println!("Removed the launch agents ({COMPOSITOR}, {MENUBAR}, {APPLAUNCH}), Wawona.app and the Mode B files.");
    Ok(())
}

/// Root half of uninstall: restore Aqua, unload the Mode B daemons, remove
/// what they installed. Leaves watchdogd alone (wawona-mode-b-watchdog-safety).
fn uninstall_root() -> Result<()> {
    let quiet = |args: &[&str]| {
        let _ = try_output(cmd(args[0]).args(&args[1..]));
    };
    if executable(Path::new(MODEB_HELPER)) {
        quiet(&[MODEB_HELPER, "--restore-aqua"]);
    }
    quiet(&["/bin/launchctl", "bootout", "system/com.aspauldingcode.wawona.modeb"]);
    quiet(&["/bin/launchctl", "bootout", "system/com.aspauldingcode.wawona.ws-guard"]);
    for p in ["niri", "weston", "framebufferd", "inputd"] {
        quiet(&["/usr/bin/pkill", "-u", "0", "-x", p]);
    }
    for p in [
        APP_DST,
        "/Library/PreferencePanes/Wawona.prefPane",
        "/Library/Application Support/Wawona",
        "/tmp/libwayland-support/modeb.lock",
    ] {
        let _ = std::fs::remove_dir_all(p);
    }
    for p in [
        "/etc/sudoers.d/wawona-modeb",
        "/Library/LaunchDaemons/com.aspauldingcode.wawona.modeb.plist",
        "/Library/LaunchDaemons/com.aspauldingcode.wawona.ws-guard.plist",
        "/tmp/libwayland-support/modeb-compositor.pid",
    ] {
        let _ = std::fs::remove_file(p);
    }
    quiet(&["/bin/launchctl", "enable", "system/com.apple.WindowServer"]);
    quiet(&["/bin/launchctl", "load", "-w", "/System/Library/LaunchDaemons/com.apple.WindowServer.plist"]);
    if try_output(cmd("/usr/bin/pgrep").args(["-x", "WindowServer"])).is_none() {
        quiet(&["/bin/launchctl", "kickstart", "-k", "system/com.apple.WindowServer"]);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn strip_removes_only_the_block() {
        let dir = std::env::temp_dir().join(format!("wawona-strip-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let rc = dir.join("rc");
        std::fs::write(&rc, format!("a\n{}b\n", super::path_block())).unwrap();
        super::strip_block(&rc).unwrap();
        assert_eq!(std::fs::read_to_string(&rc).unwrap(), "a\n\nb\n");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn templates_have_no_placeholder_left() {
        let w = super::wrapper(std::path::Path::new("/Applications/Wawona.app"), "weston");
        assert!(!w.contains("@MARKER@") && !w.contains("@APP@") && !w.contains("@NAME@") && !w.contains("@ENV_SH@"));
        assert!(w.contains(super::MARKER));
    }
}
