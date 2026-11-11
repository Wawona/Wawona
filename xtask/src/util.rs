use anyhow::{bail, Context, Result};
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// The Wawona checkout (the parent of `xtask/`).
pub fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

pub fn cmd(program: impl AsRef<OsStr>) -> Command {
    Command::new(program)
}

/// Runs a command, failing with its rendering when it exits non-zero.
pub fn run(c: &mut Command) -> Result<()> {
    eprintln!("+ {}", render(c));
    let status = c.status().with_context(|| format!("spawn {}", render(c)))?;
    if !status.success() {
        bail!("{} exited with {status}", render(c));
    }
    Ok(())
}

/// Runs a command and returns its trimmed stdout.
pub fn output(c: &mut Command) -> Result<String> {
    let out = c.stderr(Stdio::inherit()).output().with_context(|| format!("spawn {}", render(c)))?;
    if !out.status.success() {
        bail!("{} exited with {}", render(c), out.status);
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Like [`output`], but `None` when the program is missing or fails.
pub fn try_output(c: &mut Command) -> Option<String> {
    let out = c.stderr(Stdio::null()).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn render(c: &Command) -> String {
    std::iter::once(c.get_program())
        .chain(c.get_args())
        .map(|a| a.to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn read(p: impl AsRef<Path>) -> Result<String> {
    let p = p.as_ref();
    std::fs::read_to_string(p).with_context(|| format!("read {}", p.display()))
}

pub fn write(p: impl AsRef<Path>, s: impl AsRef<[u8]>) -> Result<()> {
    let p = p.as_ref();
    if let Some(d) = p.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::write(p, s).with_context(|| format!("write {}", p.display()))
}

/// Replaces `link` with a symlink to `target`.
pub fn symlink(target: impl AsRef<Path>, link: impl AsRef<Path>) -> Result<()> {
    let link = link.as_ref();
    if link.symlink_metadata().is_ok() {
        if link.is_dir() && !link.symlink_metadata()?.file_type().is_symlink() {
            std::fs::remove_dir_all(link)?;
        } else {
            std::fs::remove_file(link)?;
        }
    }
    if let Some(d) = link.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::os::unix::fs::symlink(target.as_ref(), link).with_context(|| format!("symlink {}", link.display()))
}

pub fn env_or(k: &str, default: &str) -> String {
    std::env::var(k).ok().filter(|v| !v.is_empty()).unwrap_or_else(|| default.to_string())
}

pub fn env_flag(k: &str) -> bool {
    std::env::var(k).is_ok_and(|v| v == "1")
}

/// Starts `c` in its own session (a closing agent or CI shell cannot hang it
/// up), appending its output to `log`. Returns its pid.
pub fn detached(mut c: Command, log: impl AsRef<Path>) -> Result<u32> {
    use std::os::unix::process::CommandExt;
    let log = log.as_ref();
    if let Some(d) = log.parent() {
        std::fs::create_dir_all(d)?;
    }
    let out = std::fs::OpenOptions::new().create(true).append(true).open(log)?;
    c.stdin(Stdio::null()).stdout(out.try_clone()?).stderr(out);
    // SAFETY: setsid is async-signal-safe and touches no parent state.
    unsafe {
        c.pre_exec(|| if libc::setsid() < 0 { Err(std::io::Error::last_os_error()) } else { Ok(()) });
    }
    Ok(c.spawn().with_context(|| format!("spawn {}", render(&c)))?.id())
}

/// Polls `f` every `step_ms` until it holds or `secs` pass.
pub fn wait_for(secs: u64, step_ms: u64, mut f: impl FnMut() -> bool) -> bool {
    let end = std::time::Instant::now() + std::time::Duration::from_secs(secs);
    loop {
        if f() {
            return true;
        }
        if std::time::Instant::now() >= end {
            return false;
        }
        std::thread::sleep(std::time::Duration::from_millis(step_ms));
    }
}

/// A 2xx from `url` within two seconds.
pub fn http_ok(url: &str) -> bool {
    ureq::get(url).config().timeout_global(Some(std::time::Duration::from_secs(2))).build().call().is_ok()
}

pub fn socket_accepts(p: impl AsRef<Path>) -> bool {
    std::os::unix::net::UnixStream::connect(p).is_ok()
}

pub fn alive(pid: u32) -> bool {
    // SAFETY: signal 0 only checks that the pid exists.
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

/// Sends SIGTERM to the pid recorded in `pid_file` (if it is alive) and
/// removes the file.
pub fn stop_recorded(pid_file: impl AsRef<Path>) {
    let p = pid_file.as_ref();
    if let Some(pid) = std::fs::read_to_string(p).ok().and_then(|s| s.trim().parse::<u32>().ok()) {
        if alive(pid) {
            // SAFETY: the pid was recorded by the process this tool started.
            unsafe { libc::kill(pid as i32, libc::SIGTERM) };
            wait_for(5, 100, || !alive(pid));
        }
    }
    let _ = std::fs::remove_file(p);
}

/// `export K='V'` for `eval "$(cargo xtask …)"`.
pub fn export_line(k: &str, v: &str) -> String {
    format!("export {k}='{}'", v.replace('\'', r"'\''"))
}

pub fn uid() -> u32 {
    // SAFETY: getuid cannot fail.
    unsafe { libc::getuid() }
}

/// `WAWONA_RUNTIME`, else `XDG_RUNTIME_DIR`, else `/tmp/wawona-<uid>`.
pub fn wawona_runtime() -> PathBuf {
    std::env::var("WAWONA_RUNTIME")
        .or_else(|_| std::env::var("XDG_RUNTIME_DIR"))
        .ok()
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/tmp/wawona-{}", uid())))
}
