//! Wawona's build and repository tasks: `cargo xtask <command>`.

mod appium;
mod artifact;
mod backend;
mod ci;
mod deps;
mod macho;
mod package;
mod parity;
mod product;
mod slices;
mod testflight;
mod tip;
mod tools;
mod util;
mod verify;
mod wlcs;
mod workspace;
mod xcode;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "cargo xtask", about = "Wawona build and repository tasks")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Build libwawona for one slice into .build/backend/<slice>.
    Backend(backend::Args),
    /// Fetch prebuilt dependency slices into .deps (or pack/push them in CI).
    #[command(args_conflicts_with_subcommands = true)]
    Deps {
        #[command(subcommand)]
        cmd: Option<deps::Cmd>,
        #[command(flatten)]
        get: deps::GetArgs,
    },
    /// Build an app (simulator unless --device) through its Xcode scheme or Gradle.
    Build(product::Args),
    /// Run tests: rust, ios (XCTest on a simulator) or android (unit tests).
    Test(product::Args),
    /// Archive an app for release; --export signs and exports it.
    Archive(product::ArchiveArgs),
    /// Mode B wrappers and the macOS DMG.
    #[command(subcommand)]
    Package(package::Cmd),
    /// Repository gates (`--list` names them).
    Verify(verify::Args),
    /// Verification findings: emit one, or summarize them.
    #[command(subcommand)]
    Report(verify::report::Cmd),
    /// The Appium UI suite and its offline checks.
    #[command(subcommand)]
    Appium(appium::Cmd),
    /// Policy gates on built apps and archives (graphics matrix, Mode A/B firewall, size).
    #[command(subcommand)]
    Artifact(artifact::Cmd),
    /// GitHub Actions bookkeeping.
    #[command(subcommand)]
    Ci(ci::Cmd),
    /// Prepare the path crates of a Wawona workspace (coreutils, waypipe, libghostty).
    #[command(subcommand)]
    Workspace(workspace::Cmd),
    /// Build (when stale), check and clean-launch the tip app every UI proof uses.
    Tip(tip::Args),
    /// Wawona.xcodeproj build phases.
    #[command(subcommand)]
    Xcode(xcode::Cmd),
}

fn main() -> Result<()> {
    if let Some(r) = tools::dispatch() {
        return r;
    }
    match Cli::parse().cmd {
        Cmd::Backend(a) => backend::main(a),
        Cmd::Deps { cmd, get } => deps::main(cmd.unwrap_or(deps::Cmd::Get(get))),
        Cmd::Build(a) => product::build(a),
        Cmd::Test(a) => product::test(a),
        Cmd::Archive(a) => product::archive(a),
        Cmd::Package(c) => package::main(c),
        Cmd::Verify(a) => verify::main(a),
        Cmd::Report(c) => verify::report::main(c),
        Cmd::Appium(c) => appium::main(c),
        Cmd::Artifact(c) => artifact::main(c),
        Cmd::Ci(c) => ci::main(c),
        Cmd::Workspace(c) => workspace::main(c),
        Cmd::Tip(a) => tip::main(a),
        Cmd::Xcode(c) => xcode::main(c),
    }
}
