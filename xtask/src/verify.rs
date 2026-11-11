//! `cargo xtask verify <check>`: repository gates CI and the build phases run.

use crate::util::*;
use anyhow::{bail, Result};

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// VERSION and Cargo.toml carry today's CalVer (YY.M.D, Los Angeles).
    Calver,
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Calver => calver(),
    }
}

/// Fails closed when the CalVer is not today's. A release rebuild of a past
/// tip sets WAWONA_ALLOW_STALE_CALVER=1.
pub fn calver() -> Result<()> {
    if std::env::var("WAWONA_ALLOW_STALE_CALVER").as_deref() == Ok("1") {
        eprintln!("calver: skipped (WAWONA_ALLOW_STALE_CALVER=1)");
        return Ok(());
    }
    let today = output(cmd("date").env("TZ", "America/Los_Angeles").arg("+%y.%-m.%-d"))?;
    let root = root();
    let file = read(root.join("VERSION"))?.trim().to_string();
    let manifest: toml::Table = toml::from_str(&read(root.join("Cargo.toml"))?)?;
    let cargo = manifest.get("package").and_then(|p| p.get("version")).and_then(|v| v.as_str()).unwrap_or("");
    if file != today || cargo != today {
        bail!(
            "CalVer mismatch: today (America/Los_Angeles) {today}, VERSION {file}, Cargo.toml {cargo}.\n\
             Bump VERSION and Cargo.toml to {today} and sync Cargo.lock. A deliberate stale rebuild sets WAWONA_ALLOW_STALE_CALVER=1."
        );
    }
    Ok(())
}
