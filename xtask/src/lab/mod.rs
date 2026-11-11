//! `cargo xtask lab <name>`: runtime smokes and lab drives of a built product.

mod runtime;

use anyhow::Result;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Install the APK on the running emulator, launch it, assert it stays alive.
    AndroidRuntime,
    /// Install and launch the simulator build, assert it stays alive.
    IosRuntime,
    /// Start the compositor host and hold each bundled client against it.
    MacosRuntime,
    /// Linux nightly: nested Weston with XWayland, then nested niri, on the host.
    Capability,
}

pub fn main(c: Cmd) -> Result<()> {
    std::env::set_current_dir(crate::util::root())?;
    match c {
        Cmd::AndroidRuntime => runtime::android(),
        Cmd::IosRuntime => runtime::ios(),
        Cmd::MacosRuntime => runtime::macos(),
        Cmd::Capability => runtime::capability(),
    }
}
