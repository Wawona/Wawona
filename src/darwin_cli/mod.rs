//! Darwin-style CLI for the Apple-mobile in-process shell.
//!
//! Command logic is Rust. Apple framework calls are registered by Swift.

pub mod capability;
mod commands;
mod format;
pub mod host;
mod state;

use std::ffi::{c_char, CStr};

pub use capability::Capability;

/// Command names the zsh dispatcher may route here.
pub const COMMANDS: &[&str] = &[
    "open",
    "openurl",
    "pbcopy",
    "pbpaste",
    "say",
    "plutil",
    "defaults",
    "xattr",
    "sips",
    "sw_vers",
    "ditto",
    "GetFileInfo",
    "SetFile",
    "mdfind",
    "mdls",
    "mdutil",
    "security",
    "log",
    "system_profiler",
    "ioreg",
    "networksetup",
    "scutil",
    "pmset",
    "caffeinate",
    "diskutil",
    "hdiutil",
    "launchctl",
    "lsregister",
    "softwareupdate",
    "profiles",
    "codesign",
    "spctl",
    "tmutil",
    "osascript",
    "kmutil",
    "csrutil",
    "systemextensionsctl",
    "xcrun",
    "metal",
    "simctl",
    "devicectl",
    "uiopen",
    "uicache",
    "uialert",
    "uinotify",
    "uisave",
    "uishoot",
    "uidisplay",
    "lsrebuild",
    "mgask",
    "ldid",
];

pub fn run_args(args: &[String]) -> i32 {
    commands::run(args)
}

/// Entry used by the Swift `@_cdecl` trampoline.
#[no_mangle]
pub unsafe extern "C" fn wwn_darwin_cli_run(argc: i32, argv: *mut *mut c_char) -> i32 {
    if argc <= 0 || argv.is_null() {
        return 1;
    }
    let mut args = Vec::with_capacity(argc as usize);
    for i in 0..argc {
        let p = *argv.add(i as usize);
        if p.is_null() {
            args.push(String::new());
            continue;
        }
        args.push(CStr::from_ptr(p).to_string_lossy().into_owned());
    }
    commands::run(&args)
}
