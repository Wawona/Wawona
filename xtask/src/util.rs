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

/// Lines of `git ls-files` for the patterns, relative to the checkout.
pub fn git_files(patterns: &[&str]) -> Result<Vec<PathBuf>> {
    let s = output(cmd("git").current_dir(root()).arg("ls-files").arg("-z").arg("--").args(patterns))?;
    Ok(s.split('\0').filter(|l| !l.is_empty()).map(PathBuf::from).collect())
}
