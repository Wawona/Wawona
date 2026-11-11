//! Wawona's build and repository tasks: `cargo xtask <command>`.

mod backend;
mod deps;
mod macho;
mod slices;
mod tools;
mod util;
mod verify;
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
    /// Repository gates.
    #[command(subcommand)]
    Verify(verify::Cmd),
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
        Cmd::Verify(c) => verify::main(c),
        Cmd::Xcode(c) => xcode::main(c),
    }
}
