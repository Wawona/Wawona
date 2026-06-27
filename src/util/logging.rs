//! Standardized logging utility for Wawona
//!
//! This module provides the `wlog!` macro which ensures all Rust logs
//! follow the `YYYY-MM-DD HH:MM:SS [MODULE] Message` format.
//!
//! Hot-path logging (ProcessEvents, SurfaceCommitted, etc.) uses `wlog_hot!`
//! and is silent unless `WWN_FFI_DEBUG=1` is set in the environment.
//!
//! Logs write to a preserved stderr fd (see [`init_preserved_stderr`]). In-process
//! zsh on iOS dup2()s the PTY onto fds 0–2 for the whole process; without this,
//! compositor trace output would appear inside weston-terminal.

use std::ffi::c_int;
use std::sync::OnceLock;

static PRESERVED_STDERR: OnceLock<c_int> = OnceLock::new();

/// Capture stderr before in-process shell spawn hijacks fd 2. Safe to call repeatedly.
pub fn init_preserved_stderr() {
    PRESERVED_STDERR.get_or_init(|| {
        let fd = unsafe { libc::dup(libc::STDERR_FILENO) };
        if fd < 0 {
            libc::STDERR_FILENO
        } else {
            fd
        }
    });
}

fn preserved_stderr_fd() -> c_int {
    init_preserved_stderr();
    *PRESERVED_STDERR.get().unwrap_or(&libc::STDERR_FILENO)
}

pub fn write_log_line(module: &str, message: &str) {
    let now = chrono::Local::now();
    let line = format!(
        "{} [{}] {}\n",
        now.format("%Y-%m-%d %H:%M:%S"),
        module,
        message
    );
    unsafe {
        libc::write(
            preserved_stderr_fd(),
            line.as_ptr() as *const libc::c_void,
            line.len(),
        );
    }
}

/// Per-tick / per-frame FFI trace logging — off unless `WWN_FFI_DEBUG=1`.
pub fn hot_logs_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| {
        matches!(
            std::env::var("WWN_FFI_DEBUG").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        )
    })
}

#[macro_export]
macro_rules! wlog {
    ($module:expr, $($arg:tt)*) => {{
        $crate::util::logging::write_log_line($module, &format!($($arg)*));
    }};
}

/// Hot-path logging — silent unless `WWN_FFI_DEBUG=1`.
#[macro_export]
macro_rules! wlog_hot {
    ($module:expr, $($arg:tt)*) => {{
        if $crate::util::logging::hot_logs_enabled() {
            $crate::util::logging::write_log_line($module, &format!($($arg)*));
        }
    }};
}

/// Per-frame trace logging — compiled out by default.
/// Build with `--features verbose-logs` to enable.
#[macro_export]
macro_rules! wtrace {
    ($module:expr, $($arg:tt)*) => {{
        #[cfg(feature = "verbose-logs")]
        {
            $crate::util::logging::write_log_line($module, &format!($($arg)*));
        }
        #[cfg(not(feature = "verbose-logs"))]
        {
            let _ = ($module, format_args!($($arg)*));
        }
    }};
}

/// Standardized module identifiers
pub const MAIN: &str = "MAIN";
pub const CORE: &str = "CORE";
pub const FFI: &str = "FFI";
pub const BRIDGE: &str = "BRIDGE";
pub const WAYLAND: &str = "WAYLAND";
pub const METAL: &str = "METAL";
pub const INPUT: &str = "INPUT";
pub const C_API: &str = "C_API";
pub const SEAT: &str = "SEAT";
pub const DISPLAY: &str = "DISPLAY";
pub const COMPOSITOR: &str = "COMPOSITOR";
pub const STATE: &str = "STATE";
pub const PREFS: &str = "PREFS";
pub const BUFFER: &str = "BUFFER";
