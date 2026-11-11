//! Wawona's build and repository tasks: `cargo xtask <command>`.

mod appium;
mod artifact;
mod backend;
mod ci;
mod deps;
mod gen;
mod install;
mod lab;
mod macho;
mod package;
mod parity;
mod product;
mod prove;
mod secrets;
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
    /// Regenerate committed files from their sources.
    #[command(subcommand)]
    Gen(gen::Cmd),
    /// Run one Verification report lane (`--help` lists them).
    Prove(prove::Args),
    /// Runtime smokes and lab drives of a built product.
    #[command(subcommand)]
    Lab(lab::Cmd),
    /// Release secrets: check, run a command with them, sync to GitHub, fastlane match, rulesets.
    #[command(subcommand)]
    Secrets(secrets::Cmd),
    /// Install the Release macOS build to /Applications with its launch agents, Mode B helper and CLI wrappers.
    Install {
        /// The Wawona.app to install (default: this checkout's Release build).
        #[arg(long)]
        app: Option<std::path::PathBuf>,
    },
    /// Remove what `install` put on this Mac and restore Aqua.
    Uninstall {
        #[arg(long, hide = true)]
        privileged: bool,
    },
    /// The host-PATH wrappers for the executables bundled in Wawona.app.
    #[command(subcommand)]
    Cli(install::Cli),
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
        Cmd::Gen(c) => gen::main(c),
        Cmd::Prove(a) => prove::main(a),
        Cmd::Lab(c) => lab::main(c),
        Cmd::Secrets(c) => secrets::main(c),
        Cmd::Install { app } => install::install(app),
        Cmd::Uninstall { privileged } => install::uninstall(privileged),
        Cmd::Cli(c) => install::cli(c),
        Cmd::Tip(a) => tip::main(a),
        Cmd::Xcode(c) => xcode::main(c),
    }
}
