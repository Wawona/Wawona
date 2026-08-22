//! Standardized logging utility for Wawona
//!
//! This module provides the `wlog!` macro which ensures all Rust logs
//! follow the `YYYY-MM-DD HH:MM:SS [MODULE] Message` format.
//!
//! Hot-path logging (ProcessEvents, SurfaceCommitted, etc.) uses `wlog_hot!`
//! and is silent unless `WWN_FFI_DEBUG=1` is set in the environment.
//!
//! Logs write to a preserved stderr fd (see [`init_preserved_stderr`]). In-process
//! zsh on iOS dup2()s the PTY onto fds 0-2 for the whole process; without this,
//! compositor trace output would appear inside weston-terminal.

use std::collections::VecDeque;
use std::ffi::{CStr, CString, c_char, c_int};
use std::sync::{Mutex, OnceLock};

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

const RING_CAP: usize = 2048;
const LINE_CAP: usize = 1024;

struct RingEntry {
    machine: String,
    line: String,
}

struct LogRing {
    machine: String,
    entries: VecDeque<RingEntry>,
}

fn log_ring() -> &'static Mutex<LogRing> {
    static RING: OnceLock<Mutex<LogRing>> = OnceLock::new();
    RING.get_or_init(|| {
        Mutex::new(LogRing {
            machine: String::new(),
            entries: VecDeque::with_capacity(RING_CAP),
        })
    })
}

fn push_ring_line(module: &str, message: &str, formatted: &str) {
    let _ = (module, message);
    let mut line = formatted.trim_end_matches('\n').to_string();
    if line.len() > LINE_CAP {
        line.truncate(LINE_CAP);
    }
    let mut ring = log_ring().lock().unwrap_or_else(|e| e.into_inner());
    if ring.entries.len() >= RING_CAP {
        ring.entries.pop_front();
    }
    let machine = ring.machine.clone();
    ring.entries.push_back(RingEntry { machine, line });
}

pub fn set_ring_machine(machine_id: &str) {
    let mut ring = log_ring().lock().unwrap_or_else(|e| e.into_inner());
    ring.machine = machine_id.to_string();
}

pub fn dump_ring(machine_filter: Option<&str>) -> String {
    let ring = log_ring().lock().unwrap_or_else(|e| e.into_inner());
    let mut out = String::new();
    for e in &ring.entries {
        if let Some(id) = machine_filter {
            if id.is_empty() || e.machine != id {
                continue;
            }
        }
        if !out.is_empty() {
            out.push('\n');
        }
        if !e.machine.is_empty() {
            out.push_str(&format!("{{{}}} {}", e.machine, e.line));
        } else {
            out.push_str(&e.line);
        }
    }
    if out.is_empty() {
        "(no captured log lines yet)".to_string()
    } else {
        out
    }
}

fn format_log_line(module: &str, message: &str) -> String {
    let now = chrono::Local::now();
    format!(
        "{} [{}] {}",
        now.format("%Y-%m-%d %H:%M:%S"),
        module,
        message
    )
}

pub fn write_log_line(module: &str, message: &str) {
    let line = format_log_line(module, message) + "\n";
    push_ring_line(module, message, &line);
    unsafe {
        libc::write(
            preserved_stderr_fd(),
            line.as_ptr() as *const libc::c_void,
            line.len(),
        );
    }
}

/// ObjC/C `WWNLog` already wrote stderr. Ring only (do not print again).
#[no_mangle]
pub extern "C" fn wwn_log_ring_append(module: *const c_char, msg: *const c_char) {
    let module = unsafe {
        if module.is_null() {
            "?"
        } else {
            CStr::from_ptr(module).to_str().unwrap_or("?")
        }
    };
    let msg = unsafe {
        if msg.is_null() {
            ""
        } else {
            CStr::from_ptr(msg).to_str().unwrap_or("")
        }
    };
    let line = format_log_line(module, msg);
    push_ring_line(module, msg, &line);
}

#[no_mangle]
pub extern "C" fn wwn_log_ring_set_machine(machine_id: *const c_char) {
    let id = unsafe {
        if machine_id.is_null() {
            ""
        } else {
            CStr::from_ptr(machine_id).to_str().unwrap_or("")
        }
    };
    set_ring_machine(id);
}

/// Caller frees with `WWNStringFree`. `machine_id` NULL dumps every line.
#[no_mangle]
pub extern "C" fn wwn_log_ring_dump(machine_id: *const c_char) -> *mut c_char {
    let filter = unsafe {
        if machine_id.is_null() {
            None
        } else {
            CStr::from_ptr(machine_id).to_str().ok()
        }
    };
    let text = dump_ring(filter);
    CString::new(text.replace('\0', "")).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Per-tick / per-frame FFI trace logging. Off unless `WWN_FFI_DEBUG=1`.
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

/// Hot-path logging. Silent unless `WWN_FFI_DEBUG=1`.
#[macro_export]
macro_rules! wlog_hot {
    ($module:expr, $($arg:tt)*) => {{
        if $crate::util::logging::hot_logs_enabled() {
            $crate::util::logging::write_log_line($module, &format!($($arg)*));
        }
    }};
}

/// Per-frame trace logging. Compiled out by default.
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

#[cfg(test)]
mod tests {
    use super::*;

    fn reset_ring() {
        let mut ring = log_ring().lock().unwrap_or_else(|e| e.into_inner());
        ring.machine.clear();
        ring.entries.clear();
    }

    #[test]
    fn dump_filters_by_machine() {
        reset_ring();
        set_ring_machine("weston-1");
        write_log_line("WESTON", "nested launch");
        set_ring_machine("kmscube-1");
        write_log_line("KMSCUBE", "metal present");
        let weston = dump_ring(Some("weston-1"));
        assert!(weston.contains("nested launch"), "{weston}");
        assert!(!weston.contains("metal present"), "{weston}");
        let all = dump_ring(None);
        assert!(all.contains("nested launch"));
        assert!(all.contains("metal present"));
    }
}
