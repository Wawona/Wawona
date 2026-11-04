//! In-app Wawona Terminal for Linux.
//!
//! Wawona Terminal on Linux: GTK chrome + Rust libghostty grid
//! (`TerminalSession` / `ghostty_*`).
//! Modules own the PTY session, GTK view, keys, and paint.

mod keys;
mod paint;
mod session;
mod view;

pub use session::{
    launch_subtitle, open_launched, open_shell, shell_command, start_shell, start_terminal,
    terminal_launch, TerminalLaunch,
};
pub use view::build_terminal_view;
