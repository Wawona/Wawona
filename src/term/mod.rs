//! In-process link of the Terminal crate screen.
//! Canonical source: github.com/Wawona/Terminal `src/screen.rs`.
//! `screen.rs` in this directory is a symlink. Nix replaces it from the
//! `terminal` flake input in workspace-src. Do not grow a second parser here.

#[path = "screen.rs"]
mod screen;

pub use screen::*;
